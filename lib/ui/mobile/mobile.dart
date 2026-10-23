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
import 'package:proxypin/mcp/mcp_service.dart';
import 'package:proxypin/storage/histories.dart';
import 'package:proxypin/ui/component/memory_cleanup.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';
import 'package:proxypin/ui/component/svg_icon.dart';
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
    NetworkTabController.current?.updateResponse(response);
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
    // 启动历史记录任务（单例；原由 ConfigPage 触发，配置页移除后在这里保证初始化）
    HistoryTask.ensureInstance(widget.configuration, MobileApp.container);
    _remoteHistorySubscription = HistoryStorage.onRemoteImported.listen((item) => _openHistoryPage(item));

    // MCP 局域网服务：启用时随抓包一起启动，clear_session 同步清空界面列表
    McpService.instance.clearUiSession = () async {
      MobileApp.requestStateKey.currentState?.clean();
    };
    if (widget.appConfiguration.mcpEnabled) {
      McpService.instance.attach(proxyServer, existing: MobileApp.container.source);
      unawaited(McpService.instance.start(widget.appConfiguration).catchError((e) {
        // 启动失败（如端口/绑定被拒）时持久化关闭，避免每次启动都重复失败
        widget.appConfiguration.mcpEnabled = false;
        widget.appConfiguration.flushConfig();
      }));
    }

    if (widget.appConfiguration.upgradeNoticeV40) {
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
    _selectIndex.value = 0;
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
  var configNavigatorKey = GlobalKey<NavigatorState>();
  var toolboxNavigatorKey = GlobalKey<NavigatorState>();
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
        onPopInvokedWithResult: (didPop, result) async {
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
            builder: (context, index, child) {
              var theme = Theme.of(context);
              return Scaffold(
                  body: IndexedStack(index: index, children: navigationView),
                  // 实心底导航（放弃毛玻璃：真机上模糊效果不明显，且 extendBody 会引入一系列页尾遮挡问题）
                  bottomNavigationBar: widget.appConfiguration.bottomNavigation
                      ? Container(
                          decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              border: Border(
                                  top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6), width: 0.5))),
                          child: SafeArea(
                              top: false,
                              child: Theme(
                                data: theme.copyWith(splashColor: Colors.transparent),
                                child: BottomNavigationBar(
                                  type: BottomNavigationBarType.fixed,
                                  backgroundColor: Colors.transparent,
                                  iconSize: 20,
                                  // 设计稿 .p-bn：图标 19 + 9px 文字标签
                                  showSelectedLabels: true,
                                  showUnselectedLabels: true,
                                  selectedFontSize: 10,
                                  unselectedFontSize: 10,
                                  elevation: 0,
                                  items: [
                                    // 设计稿线条 SVG 图标：list / wrench / sliders / gear（工具箱第 2、配置第 3）
                                    // 与桌面 rail 首项同款标签（设计稿底导航「请求」）
                                    _navItem(context, 'list', localizations.navRequests, index == 0),
                                    _navItem(context, 'wrench', localizations.toolbox, index == 1),
                                    _navItem(context, 'sliders', localizations.config, index == 2),
                                    _navItem(context, 'gear', localizations.setting, index == 3),
                                  ],
                                  currentIndex: _selectIndex.value,
                                  onTap: (index) => _selectIndex.value = index,
                                ),
                              )))
                      : null);
            }));
  }

  /// 底导航项：设计稿线条 SVG 图标，选中主色 / 未选中灰
  BottomNavigationBarItem _navItem(BuildContext context, String icon, String label, bool selected) {
    var theme = Theme.of(context);
    return BottomNavigationBarItem(
        tooltip: label,
        icon: SvgIcon(icon,
            size: 20, color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
        label: label);
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
            '1. 界面全新改版：桌面端左侧导航、可固定快捷工具栏与流量控制页、全新深色模式与 SVG 图标；移动端导航页与工具箱同步改版；\n'
            '2. 支持导入 mTLS 客户端证书 (#680)；\n'
            '3. 新增重放任务管理，支持批量保存与重放请求；\n'
            '4. 支持抓取 MQTT over TLS 流量，按报文流展示并显示来源应用 (#949)；\n'
            '5. form-data / form-urlencoded 请求体支持表单方式编辑，选中文本可直接发送到 Decoder 或 AES 工具；\n'
            '6. 复制为 Python requests 与 curl 导入解析增强；\n'
            '7. 修复压缩及非标准 SSE 响应体显示、close-delimited 响应体处理 (#956)、应用过滤加载失败等问题；iOS 最低支持提升至 iOS 15。\n'
        : 'Note: HTTPS capture is disabled by default — please install the certificate before enabling HTTPS capture.\n\n'
            '1. Brand-new UI: desktop left-side navigation, pinnable quick toolbar with a traffic control page, redesigned dark mode and SVG icons; mobile navigation pages and toolbox revamped as well;\n'
            '2. Support importing mTLS client certificates (#680);\n'
            '3. Added replay task management to save and replay requests in batches;\n'
            '4. Capture MQTT over TLS traffic, displayed as a packet stream with originating app attribution (#949);\n'
            '5. Form-based editing for form-data and form-urlencoded bodies; selected text can be sent directly to the Decoder or AES tools;\n'
            '6. Enhanced copy-as-Python-requests and curl import parsing;\n'
            '7. Fixed display of compressed and non-standard SSE bodies, close-delimited response body handling (#956), app filter loading failures, and other issues; minimum iOS version raised to iOS 15.\n';
    showAlertDialog(isCN ? '更新内容V${AppConfiguration.version}' : "What's new in V${AppConfiguration.version}", content,
        () {
      widget.appConfiguration.upgradeNoticeV40 = false;
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
      // FAB 用 Stack 定位在右下（内层 Scaffold 的 floatingActionButton 会与底导航布局冲突）
      Positioned(right: 16, bottom: 12, child: _launchActionButton()),
    ]);
  }

  /// 设计稿：运行中 = 绿底白 ⏹，已停止 = 灰底白 ▶（图标白色由 SocketLaunch 移动端分支绘制）
  Widget _launchActionButton() {
    return ValueListenableBuilder<ValueWrap<bool>>(
        valueListenable: SocketLaunch.startStatus,
        builder: (context, status, _) {
          var running = status.get() == true;
          var theme = Theme.of(context);
          // 46px 正圆右下悬浮（设计稿 .p-fab）；配色用户拍板：运行=绿 #1F8B4C / 停止=主题主色，图标恒白
          return SizedBox(
            width: 46,
            height: 46,
            child: FloatingActionButton(
              onPressed: null,
              shape: const CircleBorder(),
              backgroundColor: running ? okColor(theme) : theme.colorScheme.primary,
              child: SocketLaunch(
                proxyServer: proxyServer,
                size: 22,
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
            ),
          );
        });
  }

  /// 远程连接
  Widget remoteConnect(RemoteModel value) {
    return Container(
        margin: const EdgeInsets.only(top: 5, bottom: 5),
        height: 56,
        width: double.infinity,
        child: ElevatedButton(
          style: ButtonStyle(
              shape: WidgetStateProperty.all<RoundedRectangleBorder>(
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
        systemOverlayStyle: Platform.isAndroid
            ? SystemUiOverlayStyle(
                systemNavigationBarColor: ColorScheme.of(context).surface,
                statusBarColor: ColorScheme.of(context).surface)
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
