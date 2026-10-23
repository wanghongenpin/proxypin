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
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/mcp/mcp_service.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/storage/histories.dart';
import 'package:proxypin/ui/component/memory_cleanup.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/content/panel.dart';
import 'package:proxypin/ui/desktop/left_menus/favorite.dart';
import 'package:proxypin/ui/desktop/left_menus/history.dart';
import 'package:proxypin/ui/desktop/left_menus/navigation.dart';
import 'package:proxypin/ui/desktop/request/list.dart';
import 'package:proxypin/ui/desktop/toolbar/toolbar.dart';
import 'package:proxypin/ui/desktop/widgets/status_bar.dart';
import 'package:proxypin/ui/desktop/widgets/windows_toolbar.dart';
import 'package:proxypin/utils/listenable_list.dart';

import '../app_update/app_update_repository.dart';
import '../component/split_view.dart';
import '../toolbox/toolbox.dart';

/// @author wanghongen
/// 2023/10/8
class DesktopHomePage extends StatefulWidget {
  final Configuration configuration;
  final AppConfiguration appConfiguration;

  const DesktopHomePage(this.configuration, this.appConfiguration, {super.key, required});

  @override
  State<DesktopHomePage> createState() => _DesktopHomePagePageState();
}

/// 供 MCP 等独立组件一次性回填当前抓包列表（同文件可访问私有 State 的静态容器）。
ListenableList<HttpRequest> get desktopCaptureContainer => _DesktopHomePagePageState.container;

class _DesktopHomePagePageState extends State<DesktopHomePage> implements EventListener {
  static final container = ListenableList<HttpRequest>();

  static final GlobalKey<DesktopRequestListState> requestListStateKey = GlobalKey<DesktopRequestListState>();

  final ValueNotifier<int> _selectIndex = ValueNotifier(0);
  StreamSubscription<HistoryItem>? _remoteHistorySubscription;

  late ProxyServer proxyServer = ProxyServer(widget.configuration);
  late NetworkTabController panel;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void onRequest(Channel channel, HttpRequest request) {
    requestListStateKey.currentState!.add(channel, request);

    if (request.attributes['quickShare'] == true) {
      _selectIndex.value = 0;
      panel.change(request, request.response);
    }

    //监控内存 到达阈值清理
    MemoryCleanupMonitor.onMonitor(onCleanup: () {
      requestListStateKey.currentState?.cleanupEarlyData(32);
    });
  }

  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) {
    requestListStateKey.currentState!.addResponse(channelContext, response);
    panel.updateResponse(response);
  }

  @override
  void onMessage(Channel channel, HttpMessage message, WebSocketFrame frame) {
    if (panel.request.get() == message || panel.response.get() == message) {
      panel.changeState();
    }
  }

  @override
  void initState() {
    super.initState();
    proxyServer.addListener(this);
    McpService.instance.clearUiSession = () async {
      container.clear();
      requestListStateKey.currentState?.clean();
    };
    if (widget.appConfiguration.mcpEnabled) {
      McpService.instance.attach(proxyServer, existing: container);
      unawaited(McpService.instance.start(widget.appConfiguration).catchError((e) {
        logger.e('MCP auto-start failed: $e');
      }));
    }
    panel = NetworkTabController(tabStyle: const TextStyle(fontSize: 12.5), proxyServer: proxyServer);
    _remoteHistorySubscription = HistoryStorage.onRemoteImported.listen((_) {
      if (mounted) {
        _selectIndex.value = 2;
      }
    });

    if (widget.appConfiguration.upgradeNoticeV40) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showUpgradeNotice();
      });
    } else {
      AppUpdateRepository.checkUpdate(context);
    }
  }

  @override
  void dispose() {
    _remoteHistorySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var navigationView = [
      DesktopRequestListWidget(key: requestListStateKey, proxyServer: proxyServer, list: container, panel: panel),
      Favorites(panel: panel),
      HistoryPageWidget(proxyServer: proxyServer, container: container, panel: panel),
      // Toolbox 与移动端共用，桌面侧在这里统一刷白底，不动共享文件。
      // 用 Material 而非 Container(color:)：给内部点击控件提供 Material 祖先（水波纹/hover 才能画上），
      // 同时 SizedBox.expand 撑满 Stack 松约束，避免底部漏灰
      Material(
          color: Theme.of(context).colorScheme.surface,
          child: const SizedBox.expand(child: Toolbox()))
    ];

    return Scaffold(
        appBar: Tab(
            height: 52, // 设计稿 .toolbar 高 52
            child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(bottom: BorderSide(color: chromeBorderColor(Theme.of(context)), width: 1))),
          child: Platform.isMacOS
              ? Toolbar(proxyServer, requestListStateKey)
              : WindowsToolbar(title: Toolbar(proxyServer, requestListStateKey)),
        )),
        bottomNavigationBar:
            DesktopStatusBar(proxyServer: proxyServer, container: container, requestListStateKey: requestListStateKey),
        body: Row(
          children: [
            LeftNavigationBar(
                selectIndex: _selectIndex, appConfiguration: widget.appConfiguration, proxyServer: proxyServer),
            Expanded(
              child: VerticalSplitView(
                  ratio: widget.appConfiguration.panelRatio,
                  minRatio: 0.15,
                  maxRatio: 0.9,
                  // 左右面板都是白底，分隔拖拽区透出的灰色 scaffold 底刷白
                  dividerBackground: Theme.of(context).colorScheme.surface,
                  onRatioChanged: (ratio) {
                    widget.appConfiguration.panelRatio = double.parse(ratio.toStringAsFixed(2));
                    widget.appConfiguration.flushConfig();
                  },
                  left: ValueListenableBuilder(
                      valueListenable: _selectIndex,
                      builder: (_, index, __) =>
                          LazyIndexedStack(index: index < 0 ? 0 : index, children: navigationView)),
                  right: panel),
            )
          ],
        ));
  }

  //更新引导
  void showUpgradeNotice() {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) {
          return AlertDialog(
              scrollable: true,
              actions: [
                TextButton(
                    onPressed: () {
                      widget.appConfiguration.upgradeNoticeV40 = false;
                      widget.appConfiguration.flushConfig();
                      Navigator.pop(context);
                    },
                    child: Text(localizations.close))
              ],
              title: Text(isCN ? '更新内容V${AppConfiguration.version}' : "What's new in V${AppConfiguration.version}",
                  style: const TextStyle(fontSize: 18)),
              content: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: SelectableText(
                      isCN
                          ? '提示：默认不会开启HTTPS抓包，请安装证书后再开启HTTPS抓包。\n'
                              '点击HTTPS抓包(加锁图标)，选择安装根证书，按照提示操作即可。\n\n'
                              '1. 界面全新改版：桌面端左侧导航、可固定快捷工具栏与流量控制页、全新深色模式与 SVG 图标；移动端导航页与工具箱同步改版；\n'
                              '2. 支持导入 mTLS 客户端证书 (#680)；\n'
                              '3. 新增重放任务管理，支持批量保存与重放请求；\n'
                              '4. 支持抓取 MQTT over TLS 流量，按报文流展示并显示来源应用 (#949)；\n'
                              '5. form-data / form-urlencoded 请求体支持表单方式编辑，选中文本可直接发送到 Decoder 或 AES 工具；\n'
                              '6. 复制为 Python requests 与 curl 导入解析增强；\n'
                              '7. 修复压缩及非标准 SSE 响应体显示、close-delimited 响应体处理 (#956)、应用过滤加载失败等问题；iOS 最低支持提升至 iOS 15。\n'
                          : 'Note: HTTPS capture is disabled by default — please install the certificate before enabling HTTPS capture.\n'
                              'Click the HTTPS capture (lock) icon, choose "Install Root Certificate", and follow the prompts to complete installation.\n\n'
                              '1. Brand-new UI: desktop left-side navigation, pinnable quick toolbar with a traffic control page, redesigned dark mode and SVG icons; mobile navigation pages and toolbox revamped as well;\n'
                              '2. Support importing mTLS client certificates (#680);\n'
                              '3. Added replay task management to save and replay requests in batches;\n'
                              '4. Capture MQTT over TLS traffic, displayed as a packet stream with originating app attribution (#949);\n'
                              '5. Form-based editing for form-data and form-urlencoded bodies; selected text can be sent directly to the Decoder or AES tools;\n'
                              '6. Enhanced copy-as-Python-requests and curl import parsing;\n'
                              '7. Fixed display of compressed and non-standard SSE bodies, close-delimited response body handling (#956), app filter loading failures, and other issues; minimum iOS version raised to iOS 15.\n',
                      style: const TextStyle(fontSize: 14))));
        });
  }
}

