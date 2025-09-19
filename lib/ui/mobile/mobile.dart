/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/native/app_lifecycle.dart';
import 'package:proxypin/native/pip.dart';
import 'package:proxypin/native/vpn.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/ui/component/memory_cleanup.dart';
import 'package:proxypin/ui/toolbox/toolbox.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/content/panel.dart';
import 'package:proxypin/ui/launch/launch.dart';
import 'package:proxypin/ui/mobile/menu/drawer.dart';
import 'package:proxypin/ui/mobile/menu/bottom_navigation.dart';
import 'package:proxypin/ui/mobile/menu/menu.dart';
import 'package:proxypin/ui/mobile/request/list.dart';
import 'package:proxypin/ui/mobile/request/search.dart';
import 'package:proxypin/ui/mobile/widgets/pip.dart';
import 'package:proxypin/ui/mobile/widgets/remote_device.dart';
import 'package:proxypin/utils/ip.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/listenable_list.dart';
import 'package:proxypin/utils/navigator.dart';

import '../app_update/app_update_repository.dart';

///移动端首页
///@author wanghongen
class MobileHomePage extends StatefulWidget {
  final Configuration configuration;
  final AppConfiguration appConfiguration;

  const MobileHomePage(this.configuration, this.appConfiguration, {super.key});

  @override
  State<StatefulWidget> createState() {
    return MobileHomeState();
  }
}

class MobileApp {
  ///请求列表key
  static final GlobalKey<RequestListState> requestStateKey = GlobalKey<RequestListState>();

  ///搜索key
  static final GlobalKey<MobileSearchState> searchStateKey = GlobalKey<MobileSearchState>();

  ///请求列表容器
  static final container = ListenableList<HttpRequest>();
}

class MobileHomeState extends State<MobileHomePage> implements EventListener, LifecycleListener {
  /// 选择索引
  final ValueNotifier<int> _selectIndex = ValueNotifier(0);

  late ProxyServer proxyServer;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void onRequest(Channel channel, HttpRequest request) {
    MobileApp.requestStateKey.currentState!.add(channel, request);
    PictureInPicture.addData(request.requestUrl);

    //监控内存 到达阈值清理
    MemoryCleanupMonitor.onMonitor(onCleanup: () {
      MobileApp.requestStateKey.currentState?.cleanupEarlyData(32);
    });
  }

  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) {
    MobileApp.requestStateKey.currentState!.addResponse(channelContext, response);
  }

  @override
  void onMessage(Channel channel, HttpMessage message, WebSocketFrame frame) {
    var panel = NetworkTabController.current;
    if (panel?.request.get() == message || panel?.response.get() == message) {
      panel?.changeState();
    }
  }

  @override
  void initState() {
    super.initState();

    AppLifecycleBinding.instance.addListener(this);
    proxyServer = ProxyServer(widget.configuration);
    proxyServer.addListener(this);
    proxyServer.start();

    if (widget.appConfiguration.upgradeNoticeV21) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showUpgradeNotice();
      });
    } else if (Platform.isAndroid) {
      AppUpdateRepository.checkUpdate(context);
    }
  }

  @override
  void dispose() {
    AppLifecycleBinding.instance.removeListener(this);
    super.dispose();
  }

  int exitTime = 0;

  var requestPageNavigatorKey = GlobalKey<NavigatorState>();
  var toolboxNavigatorKey = GlobalKey<NavigatorState>();
  var configNavigatorKey = GlobalKey<NavigatorState>();
  var settingNavigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    var navigationView = [
      NavigatorPage(
          navigatorKey: requestPageNavigatorKey,
          child: RequestPage(proxyServer: proxyServer, appConfiguration: widget.appConfiguration)),
      NavigatorPage(
          navigatorKey: toolboxNavigatorKey,
          child: Scaffold(
              appBar: PreferredSize(
                  preferredSize: const Size.fromHeight(42),
                  child: AppBar(
                      title: Text(localizations.toolbox,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
                      centerTitle: true)),
              body: Toolbox(proxyServer: proxyServer))),
      NavigatorPage(navigatorKey: configNavigatorKey, child: ConfigPage(proxyServer: proxyServer)),
      NavigatorPage(
          navigatorKey: settingNavigatorKey,
          child: SettingPage(proxyServer: proxyServer, appConfiguration: widget.appConfiguration)),
    ];

    if (!widget.appConfiguration.bottomNavigation) _selectIndex.value = 0;

    return PopScope(
        canPop: false,
        onPopInvoked: (didPop) async {
          if (didPop) {
            return;
          }

          if (navigationView[_selectIndex.value].onPopInvoked()) {
            return;
          }

          if (await enterPictureInPicture()) {
            return;
          }

          if (DateTime.now().millisecondsSinceEpoch - exitTime > 1500) {
            exitTime = DateTime.now().millisecondsSinceEpoch;
            if (mounted) {
              FlutterToastr.show(localizations.appExitTips, this.context,
                  rootNavigator: true, duration: FlutterToastr.lengthLong);
            }
            return;
          }
          //退出程序
          SystemNavigator.pop();
        },
        child: ValueListenableBuilder<int>(
            valueListenable: _selectIndex,
            builder: (context, index, child) => Scaffold(
                body: IndexedStack(index: index, children: navigationView),
                bottomNavigationBar: widget.appConfiguration.bottomNavigation
                    ? Container(
                        constraints: const BoxConstraints(maxHeight: 85),
                        child: Theme(
                          data: Theme.of(context).copyWith(splashColor: Colors.transparent),
                          child: BottomNavigationBar(
                            type: BottomNavigationBarType.fixed,
                            selectedIconTheme: const IconThemeData(size: 26),
                            unselectedIconTheme: const IconThemeData(size: 26),
                            selectedFontSize: 0,
                            elevation: 0,
                            items: [
                              BottomNavigationBarItem(
                                  tooltip: localizations.requests,
                                  icon: const Icon(Icons.workspaces_outlined),
                                  label: localizations.requests),
                              BottomNavigationBarItem(
                                  tooltip: localizations.toolbox,
                                  icon: const Icon(Icons.hardware_outlined),
                                  label: localizations.toolbox),
                              BottomNavigationBarItem(
                                  tooltip: localizations.config,
                                  icon: const Icon(Icons.description_outlined),
                                  label: localizations.config),
                              BottomNavigationBarItem(
                                  tooltip: localizations.setting,
                                  icon: const Icon(Icons.settings_outlined),
                                  label: localizations.setting),
                            ],
                            currentIndex: _selectIndex.value,
                            onTap: (index) => _selectIndex.value = index,
                          ),
                        ))
                    : null)));
  }

  @override
  void onUserLeaveHint() {
    enterPictureInPicture();
  }

  Future<bool> enterPictureInPicture() async {
    if (Vpn.isVpnStarted) {
      if (!Platform.isAndroid || !(await (AppConfiguration.instance)).pipEnabled.value) {
        return false;
      }

      List<String>? appList =
          proxyServer.configuration.appWhitelistEnabled ? proxyServer.configuration.appWhitelist : [];
      List<String>? disallowApps;
      if (appList.isEmpty) {
        disallowApps = proxyServer.configuration.appBlacklist ?? [];
      }

      return PictureInPicture.enterPictureInPictureMode(
          Platform.isAndroid ? await localIp() : "127.0.0.1", proxyServer.port,
          appList: appList, disallowApps: disallowApps);
    }
    return false;
  }

  @override
  onPictureInPictureModeChanged(bool isInPictureInPictureMode) async {
    if (isInPictureInPictureMode) {
      Navigator.push(
          context,
          PageRouteBuilder(
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (context, animation, secondaryAnimation) {
                return PictureInPictureWindow(MobileApp.container);
              }));
      return;
    }

    if (!isInPictureInPictureMode) {
      Navigator.maybePop(context);
      Vpn.isRunning().then((value) {
        Vpn.isVpnStarted = value;
        SocketLaunch.startStatus.value = ValueWrap.of(value);
      });
    }
  }

  void showUpgradeNotice() {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    String content = isCN
        ? '提示：默认不会开启HTTPS抓包，请安装证书后再开启HTTPS抓包。\n\n'
            '1. 消息体增加搜索高亮；\n'
            '2. WebSocket 消息体增加预览；\n'
            '3. 安卓ROOT系统支持自动安装系统证书；\n'
            '4. Socket自动清理，防止退出时资源占用问题；\n'
            '5. 调整UI菜单；\n'
            '6. 修复脚本fetch API部分请求bug；\n'
            '7. 修复HTTP2包大小不正确；\n'
            '8. 修复请求映射Bug；\n'
            '9. 修复手机端历史未自动保存bug；\n'
            '10. 修复安卓部分闪退情况；\n'
        : 'Tips: HTTPS packet capture is disabled by default. Please install the certificate before enabling HTTPS packet capture.\n\n'
            '1. Add search highlight for message body;\n'
            '2. Add preview for WebSocket message body;\n'
            '3. Android ROOT system supports automatic installation of system certificates;\n'
            '4. Socket auto cleanup to prevent resource occupation when exiting;\n'
            '5. Adjust UI menu;\n'
            '5. Fix script fetch API part request bug;\n'
            '7. Fix incorrect HTTP2 packet size;\n'
            '8. Fix request map bug;\n'
            '9. Fix the bug that the history on the mobile side is not saved automatically;\n'
            '10. Fix some Android crash issues;\n';
    showAlertDialog(isCN ? '更新内容V${AppConfiguration.version}' : "Update content V${AppConfiguration.version}", content,
        () {
      widget.appConfiguration.upgradeNoticeV21 = false;
      widget.appConfiguration.flushConfig();
    });
  }

  void showAlertDialog(String title, String content, Function onClose) {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
              scrollable: true,
              actions: [
                TextButton(
                    onPressed: () {
                      onClose.call();
                      Navigator.pop(context);
                    },
                    child: Text(localizations.cancel))
              ],
              title: Text(title, style: const TextStyle(fontSize: 18)),
              content: SelectableText(content));
        });
  }
}

class RequestPage extends StatefulWidget {
  final ProxyServer proxyServer;
  final AppConfiguration appConfiguration;

  const RequestPage({super.key, required this.proxyServer, required this.appConfiguration});

  @override
  State<RequestPage> createState() => RequestPageState();
}

class RequestPageState extends State<RequestPage> {
  /// 远程连接
  final ValueNotifier<RemoteModel> remoteDevice = ValueNotifier(RemoteModel(connect: false));

  late ProxyServer proxyServer;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    proxyServer = widget.proxyServer;

    //远程连接
    remoteDevice.addListener(() {
      if (remoteDevice.value.connect) {
        proxyServer.configuration.remoteHost = "http://${remoteDevice.value.host}:${remoteDevice.value.port}";
        checkConnectTask(context);
      } else {
        proxyServer.configuration.remoteHost = null;
      }
    });
  }

  @override
  void dispose() {
    remoteDevice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Scaffold(
        appBar: _MobileAppBar(widget.appConfiguration, proxyServer, remoteDevice: remoteDevice),
        drawer: widget.appConfiguration.bottomNavigation
            ? null
            : DrawerWidget(proxyServer: proxyServer, container: MobileApp.container),
        floatingActionButton: _launchActionButton(),
        body: ValueListenableBuilder(
            valueListenable: remoteDevice,
            builder: (context, value, _) {
              return Column(children: [
                value.connect ? remoteConnect(value) : const SizedBox(),
                Expanded(
                    child: RequestListWidget(
                        key: MobileApp.requestStateKey, proxyServer: proxyServer, list: MobileApp.container))
              ]);
            }),
      ),
      PictureInPictureIcon(proxyServer),
    ]);
  }

  Widget _launchActionButton() {
    var theme = Theme.of(context);
    return Theme(
        data: ThemeData.from(colorScheme: theme.colorScheme, textTheme: theme.textTheme, useMaterial3: true),
        child: FloatingActionButton(
          onPressed: null,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: SocketLaunch(
              proxyServer: proxyServer,
              size: 36,
              startup: proxyServer.configuration.startup,
              serverLaunch: false,
              onStart: () async {
                String host = Platform.isAndroid ? await localIp(readCache: false) : "127.0.0.1";
                int port = proxyServer.port;
                if (Platform.isIOS) {
                  await proxyServer.retryBind();
                }

                if (remoteDevice.value.ipProxy == true) {
                  host = remoteDevice.value.host!;
                  port = remoteDevice.value.port!;
                }

                Vpn.startVpn(host, port, proxyServer.configuration, ipProxy: remoteDevice.value.ipProxy);
              },
              onStop: () => Vpn.stopVpn()),
        ));
  }

  /// 远程连接
  Widget remoteConnect(RemoteModel value) {
    return Container(
        margin: const EdgeInsets.only(top: 5, bottom: 5),
        height: 56,
        width: double.infinity,
        child: ElevatedButton(
          style: ButtonStyle(
              shape: MaterialStateProperty.all<RoundedRectangleBorder>(
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (BuildContext context) {
            return RemoteDevicePage(remoteDevice: remoteDevice, proxyServer: proxyServer);
          })),
          child: Text(localizations.remoteConnected(remoteDevice.value.os ?? ', ${remoteDevice.value.hostname}'),
              style: Theme.of(context).textTheme.titleMedium),
        ));
  }

  /// 检查远程连接
  checkConnectTask(BuildContext context) async {
    int retry = 0;
    Timer.periodic(const Duration(milliseconds: 15000), (timer) async {
      if (remoteDevice.value.connect == false) {
        timer.cancel();
        return;
      }

      try {
        var response = await HttpClients.get("http://${remoteDevice.value.host}:${remoteDevice.value.port}/ping")
            .timeout(const Duration(seconds: 3));
        if (response.bodyAsString == "pong") {
          retry = 0;
          return;
        }
      } catch (e) {
        retry++;
      }

      if (retry > 3) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();

          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(localizations.remoteConnectDisconnect),
              action: SnackBarAction(
                  label: localizations.disconnect,
                  onPressed: () {
                    timer.cancel();
                    remoteDevice.value = RemoteModel(connect: false);
                  })));
        }
      }
    });
  }
}

/// 移动端AppBar
class _MobileAppBar extends StatelessWidget implements PreferredSizeWidget {
  final AppConfiguration appConfiguration;
  final ProxyServer proxyServer;
  final ValueNotifier<RemoteModel> remoteDevice;

  const _MobileAppBar(this.appConfiguration, this.proxyServer, {required this.remoteDevice});

  @override
  Size get preferredSize => const Size.fromHeight(42);

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    var bottomNavigation = appConfiguration.bottomNavigation;

    return AppBar(
        leading: bottomNavigation ? const SizedBox() : null,
        title: MobileSearch(
            key: MobileApp.searchStateKey, onSearch: (val) => MobileApp.requestStateKey.currentState?.search(val)),
        actions: [
          IconButton(
              tooltip: localizations.clear,
              icon: const Icon(Icons.cleaning_services_outlined),
              onPressed: () => MobileApp.requestStateKey.currentState?.clean()),
          const SizedBox(width: 2),
          MoreMenu(proxyServer: proxyServer, remoteDevice: remoteDevice),
          const SizedBox(width: 10),
        ]);
  }
}
