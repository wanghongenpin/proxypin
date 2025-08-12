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

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/ui/component/memory_cleanup.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/content/panel.dart';
import 'package:proxypin/ui/desktop/left_menus/favorite.dart';
import 'package:proxypin/ui/desktop/left_menus/history.dart';
import 'package:proxypin/ui/desktop/left_menus/navigation.dart';
import 'package:proxypin/ui/desktop/request/list.dart';
import 'package:proxypin/ui/desktop/toolbar/toolbar.dart';
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

class _DesktopHomePagePageState extends State<DesktopHomePage> implements EventListener {
  static final container = ListenableList<HttpRequest>();

  static final GlobalKey<DesktopRequestListState> requestListStateKey = GlobalKey<DesktopRequestListState>();

  final ValueNotifier<int> _selectIndex = ValueNotifier(0);

  late ProxyServer proxyServer = ProxyServer(widget.configuration);
  late NetworkTabController panel;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void onRequest(Channel channel, HttpRequest request) {
    requestListStateKey.currentState!.add(channel, request);

    //监控内存 到达阈值清理
    MemoryCleanupMonitor.onMonitor(onCleanup: () {
      requestListStateKey.currentState?.cleanupEarlyData(32);
    });
  }

  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) {
    requestListStateKey.currentState!.addResponse(channelContext, response);
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
    panel = NetworkTabController(tabStyle: const TextStyle(fontSize: 16), proxyServer: proxyServer);

    if (widget.appConfiguration.upgradeNoticeV20) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showUpgradeNotice();
      });
    } else {
      AppUpdateRepository.checkUpdate(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    var navigationView = [
      DesktopRequestListWidget(key: requestListStateKey, proxyServer: proxyServer, list: container, panel: panel),
      Favorites(panel: panel),
      HistoryPageWidget(proxyServer: proxyServer, container: container, panel: panel),
      const Toolbox()
    ];

    return Scaffold(
        appBar: Tab(child: Toolbar(proxyServer, requestListStateKey, sideNotifier: _selectIndex)),
        body: Row(
          children: [
            LeftNavigationBar(
                selectIndex: _selectIndex, appConfiguration: widget.appConfiguration, proxyServer: proxyServer),
            Expanded(
              child: VerticalSplitView(
                  ratio: widget.appConfiguration.panelRatio,
                  minRatio: 0.15,
                  maxRatio: 0.9,
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
                      widget.appConfiguration.upgradeNoticeV20 = false;
                      widget.appConfiguration.flushConfig();
                      Navigator.pop(context);
                    },
                    child: Text(localizations.cancel))
              ],
              title: Text(isCN ? '更新内容V${AppConfiguration.version}' : "Update content V${AppConfiguration.version}",
                  style: const TextStyle(fontSize: 18)),
              content: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: SelectableText(
                      isCN
                          ? '提示：默认不会开启HTTPS抓包，请安装证书后再开启HTTPS抓包。\n'
                              '点击HTTPS抓包(加锁图标)，选择安装根证书，按照提示操作即可。\n\n'
                              '1. 增加请求映射功能，无需请求远程服务即可返回结果；\n'
                              '2. 请求列表支持图片预览；\n'
                              '3. 增加复制原始请求；\n'
                              '4. 搜索增加区分大小写；\n'
                              '5. 语言本地化新增繁体中文；\n'
                              '6. 优化Android VPN性能；\n'
                              '7. 修复HTTP2 Host；\n'
                              '8. 修复复制Python requests问题；\n'
                          : 'Tips：By default, HTTPS packet capture will not be enabled. Please install the certificate before enabling HTTPS packet capture。\n'
                              'Click HTTPS Capture packets(Lock icon)，Choose to install the root certificate and follow the prompts to proceed。\n\n'
                              '1. Added request mapping feature, allowing results to be returned without requesting a remote service;\n'
                              '2. Request list supports image preview;\n'
                              '3. Added copy original request;\n'
                              '4. Search now distinguishes between uppercase and lowercase letters;\n'
                              '5. Added Traditional Chinese localization;\n'
                              '6. Optimized Android VPN performance;\n'
                              '7. Fixed HTTP2 Host issue;\n'
                              '8. Fixed Python requests copy issue.',
                      style: const TextStyle(fontSize: 14))));
        });
  }
}
