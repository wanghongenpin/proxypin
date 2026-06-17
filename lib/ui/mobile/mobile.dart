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
import 'dart:convert';
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
import 'package:proxypin/storage/histories.dart';
import 'package:proxypin/ui/component/memory_cleanup.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/toolbox/toolbox.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/content/panel.dart';
import 'package:proxypin/ui/launch/launch.dart';
import 'package:proxypin/ui/mobile/menu/drawer.dart';
import 'package:proxypin/ui/mobile/menu/bottom_navigation.dart';
import 'package:proxypin/ui/mobile/menu/menu.dart';
import 'package:proxypin/ui/mobile/request/history.dart';
import 'package:proxypin/ui/mobile/request/list.dart';
import 'package:proxypin/ui/mobile/request/search.dart';
import 'package:proxypin/ui/mobile/widgets/pip.dart';
import 'package:proxypin/ui/mobile/widgets/remote_device.dart';
import 'package:proxypin/utils/ip.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/listenable_list.dart';
import 'package:proxypin/utils/navigator.dart';

import '../app_update/app_update_repository.dart';
import 'package:proxypin/ui/component/multi_window.dart';
import 'package:proxypin/ui/mobile/debug/breakpoint_executor.dart';

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

  static final multiSelectController = MultiSelectController();
}

class MobileHomeState extends State<MobileHomePage> implements EventListener, LifecycleListener {
  /// 选择索引
  final ValueNotifier<int> _selectIndex = ValueNotifier(0);

  StreamSubscription<HistoryItem>? _remoteHistorySubscription;

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
    _remoteHistorySubscription = HistoryStorage.onRemoteImported.listen((item) => _openHistoryPage(item));

    if (widget.appConfiguration.upgradeNoticeV29) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showUpgradeNotice();
      });
    } else if (Platform.isAndroid) {
      AppUpdateRepository.checkUpdate(context);
    }

    // Handle breakpoint window on mobile
    MultiWindow.onOpenWindow = (widgetName, args) async {
      if (widgetName == 'BreakpointExecutor' && args != null) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BreakpointExecutor(
              requestId: args['requestId'],
              request: HttpRequest.fromJson(jsonDecode(jsonEncode(args['request']))),
              response:
                  args['response'] == null ? null : HttpResponse.fromJson(jsonDecode(jsonEncode(args['response']))),
              isResponse: args['type'] == 'response',
            ),
          ),
        );
      }
    };
  }

  @override
  void dispose() {
    AppLifecycleBinding.instance.removeListener(this);
    _remoteHistorySubscription?.cancel();
    super.dispose();
  }

  void toRequestsView(HistoryItem item, HistoryStorage storage) {}

  void _openHistoryPage(HistoryItem item) {
    _selectIndex.value = 2;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      Navigator.of(context)
          .push(MaterialPageRoute(
              builder: (BuildContext context) => HistoryRecord(history: item, proxyServer: proxyServer)))
          .then((value) async {
        Future.delayed(const Duration(seconds: 60), () => item.requests = null);
      });
    });
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
                        // padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                        child: ClipRRect(
                            // borderRadius: BorderRadius.circular(16),
                            child: Theme(
                          data: Theme.of(context).copyWith(splashColor: Colors.transparent),
                          child: BottomNavigationBar(
                            type: BottomNavigationBarType.fixed,
                            iconSize: 23,
                            showSelectedLabels: false,
                            showUnselectedLabels: false,
                            selectedFontSize: 2,
                            unselectedFontSize: 2,
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
                        )))
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
            '1. 新增文本对比工具，支持逐行高亮与差异摘要；\n'
            '2. 新增文本编辑器，支持语法高亮与文件读写；\n'
            '3. 新增 JSON / XML 查看器，支持解析与格式化；\n'
            '4. 增强请求体编辑器，内容类型识别、格式化美化、大文本编辑等；\n'
            '5. 搜索能力升级：支持正则搜索，并优化匹配索引与缓存；\n'
            '6. 导出能力增强：支持导出请求/响应文本与 HAR，HAR 图片支持 Base64 编码；\n'
            '7. 优化：新增清空抓包前确认弹窗，清空默认系统代理忽略域名； \n'
            '8. 其他：HTML、JSON、CSS 代码格式化使用独立线程减少ui卡顿，修复 iPadOS 窗口模式返回按钮遮挡。\n'
        : 'Note: HTTPS capture is disabled by default — please install the certificate before enabling HTTPS capture.\n\n'
            '1. Added a text diff tool with line-by-line highlighting and a diff summary;\n'
            '2. Added a text editor with syntax highlighting and file read/write support;\n'
            '3. Added JSON/XML viewers with parsing and formatting support;\n'
            '4. Enhanced the request body editor with content-type detection, beautification, and large-text editing support;\n'
            '5. Upgraded search capabilities: added regex search and optimized match indexing and caching;\n'
            '6. Improved export capabilities: supports request/response text export and HAR export, with Base64 image support in HAR;\n'
            '7. Optimizations: added a confirmation dialog before clearing captured records, cleared default system proxy bypass domains;\n'
            '8. Other: moved HTML/JSON/CSS formatting to isolates to reduce UI jank, and fixed the back-button overlap issue in iPadOS window mode.\n';
    showAlertDialog(isCN ? '更新内容V${AppConfiguration.version}' : "What's new in V${AppConfiguration.version}", content,
        () {
      widget.appConfiguration.upgradeNoticeV29 = false;
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
                    child: Text(localizations.close))
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
                        key: MobileApp.requestStateKey,
                        proxyServer: proxyServer,
                        list: MobileApp.container,
                        selectionController: MobileApp.multiSelectController))
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
  Future<void> checkConnectTask(BuildContext context) async {
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

  Future<void> _onClear(BuildContext context, AppLocalizations localizations) async {
    if (!appConfiguration.clearConfirm) {
      MobileApp.requestStateKey.currentState?.clean();
      return;
    }

    showConfirmDialog(context, title: localizations.clearConfirm, onConfirm: () {
      MobileApp.requestStateKey.currentState?.clean();
    });
  }

  @override
  Size get preferredSize => const Size.fromHeight(42);

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    var bottomNavigation = appConfiguration.bottomNavigation;

    return AppBar(
        leading: bottomNavigation ? const SizedBox() : null,
        systemOverlayStyle:
            // older SDKs may not have ColorScheme.of, use Theme.of(context).colorScheme for compatibility
            Platform.isAndroid
                ? SystemUiOverlayStyle(systemNavigationBarColor: Theme.of(context).colorScheme.surface,
                statusBarColor: Theme.of(context).colorScheme.surface)
             : null,
        title: MobileSearch(
            key: MobileApp.searchStateKey, onSearch: (val) => MobileApp.requestStateKey.currentState?.search(val)),
        actions: [
          IconButton(
              tooltip: localizations.clear,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _onClear(context, localizations)),
          const SizedBox(width: 2),
          MoreMenu(proxyServer: proxyServer, remoteDevice: remoteDevice),
          const SizedBox(width: 10),
        ]);
  }
}
