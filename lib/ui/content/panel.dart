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

import 'dart:convert';
import 'dart:io';

import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/storage/favorites.dart';
import 'package:proxypin/ui/component/json/json_text.dart';
import 'package:proxypin/ui/component/json/theme.dart';
import 'package:proxypin/ui/component/state_component.dart';
import 'package:proxypin/ui/component/svg_icon.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/content/web_socket.dart';
import 'package:proxypin/ui/content/mqtt.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/platform.dart';

import 'body.dart';
import 'headers.dart';
import 'menu.dart';

///网络请求详情页
///@Author: wanghongen
class NetworkTabController extends StatefulWidget {
  static GlobalKey<NetworkTabState>? currentKey;
  final String? windowId;
  final ProxyServer? proxyServer;
  final ValueWrap<HttpRequest> request = ValueWrap();
  final ValueWrap<HttpResponse> response = ValueWrap();
  final Widget? title;
  final TextStyle? tabStyle;

  /// 初始选中的 tab 下标（默认 0 = 概览）
  final int initialTab;

  NetworkTabController(
      {HttpRequest? httpRequest,
      HttpResponse? httpResponse,
      this.title,
      this.tabStyle,
      this.proxyServer,
      this.windowId,
      this.initialTab = 0})
      : super(key: GlobalKey<NetworkTabState>()) {
    currentKey = key as GlobalKey<NetworkTabState>;
    request.set(httpRequest);
    response.set(httpResponse);
  }

  void change(HttpRequest? request, HttpResponse? response) {
    this.request.set(request);
    this.response.set(response);
    var state = key as GlobalKey<NetworkTabState>;
    state.currentState?.changeState();
  }

  void changeState() {
    var state = key as GlobalKey<NetworkTabState>;
    state.currentState?.changeState();
  }

  ///更新当前详情请求的响应，请求在详情页打开期间完成时刷新响应内容
  void updateResponse(HttpResponse? response) {
    var currentRequest = request.get();
    if (response?.request == null || currentRequest == null) {
      return;
    }
    if (currentRequest.requestId != response!.request!.requestId) {
      return;
    }
    this.response.set(response);
    changeState();
  }

  @override
  State<StatefulWidget> createState() {
    return NetworkTabState();
  }

  static NetworkTabController? get current => currentKey?.currentWidget as NetworkTabController?;
}

class NetworkTabState extends State<NetworkTabController> with TickerProviderStateMixin {
  late List<String> tabs;
  late bool _mqttTabs;

  final TextStyle textStyle = const TextStyle(fontSize: 14);
  late TabController _tabController;

  final GlobalKey<HttpBodyState> requestHttpBodyKey = GlobalKey<HttpBodyState>();
  final GlobalKey<HttpBodyState> responseHttpBodyKey = GlobalKey<HttpBodyState>();

  /// 当前请求的手动收藏状态，按 requestId 缓存避免每次 build 查存储
  String? _favoritedId;
  bool _favorited = false;

  void _checkFavorited(HttpRequest request) {
    if (_favoritedId == request.requestId) return;
    var id = request.requestId;
    FavoriteStorage.favorites.then((favorites) {
      if (!mounted) return;
      setState(() {
        _favoritedId = id;
        _favorited = favorites.any((f) => f.request.requestId == id);
      });
    });
  }

  Future<void> _toggleFavorite(HttpRequest request) async {
    var localizations = AppLocalizations.of(context)!;
    if (_favorited) {
      var favorites = await FavoriteStorage.favorites;
      Favorite? target;
      for (final f in favorites) {
        if (f.request.requestId == request.requestId) {
          target = f;
          break;
        }
      }
      if (target != null) {
        await FavoriteStorage.removeFavorite(target);
      }
      if (!mounted) return;
      setState(() => _favorited = false);
      FlutterToastr.show(localizations.deleteSuccess, context);
    } else {
      await FavoriteStorage.addFavorite(request);
      if (!mounted) return;
      setState(() => _favorited = true);
      FlutterToastr.show(localizations.addSuccess, context);
    }
  }

  void changeState() {
    final mqtt = widget.request.get()?.protocolVersion == 'MQTT';
    if (mqtt != _mqttTabs) {
      _tabController.dispose();
      _configureTabs(mqtt);
    }
    setState(() {});
  }

  void _configureTabs(bool mqtt) {
    _mqttTabs = mqtt;
    tabs = mqtt ? ['General', 'MQTT'] : ['General', 'Request', 'Response', 'Cookies'];
    _tabController =
        TabController(length: tabs.length, vsync: this, initialIndex: widget.initialTab.clamp(0, tabs.length - 1));
    _tabController.addListener(() {
      if (_tabController.index != 1) {
        requestHttpBodyKey.currentState?.hideSearchOverlay();
      }
      if (_tabController.index != 2) {
        responseHttpBodyKey.currentState?.hideSearchOverlay();
      }
    });
  }

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _configureTabs(widget.request.get()?.protocolVersion == 'MQTT');

    if (widget.windowId != null) {
      HardwareKeyboard.instance.addHandler(onKeyEvent);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    HardwareKeyboard.instance.removeHandler(onKeyEvent);
    super.dispose();
  }

  bool onKeyEvent(KeyEvent event) {
    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      HardwareKeyboard.instance.removeHandler(onKeyEvent);
      WindowController.fromWindowId(widget.windowId!).close();
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    bool isMqtt = widget.request.get()?.protocolVersion == 'MQTT';
    bool isWebSocket = widget.request.get()?.isWebSocket == true;
    bool isSse = widget.response.get()?.headers.contentType.toLowerCase().startsWith('text/event-stream') == true;
    bool isStreamMessages = isWebSocket || isSse;
    if (isMqtt) {
      tabs[tabs.length - 1] = 'MQTT';
    } else if (isSse) {
      tabs[tabs.length - 1] = "SSE";
    } else if (isWebSocket) {
      tabs[tabs.length - 1] = "WebSocket";
    } else {
      tabs[tabs.length - 1] = 'Cookies';
    }

    var isDesktop = Platforms.isDesktop();
    var tabBar = TabBar(
      padding: const EdgeInsets.only(bottom: 0),
      controller: _tabController,
      isScrollable: isDesktop, // 桌面左对齐紧凑排列，手机均分
      tabAlignment: isDesktop ? TabAlignment.start : null,
      dividerColor: Theme.of(context).dividerColor,
      labelPadding: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 10),
      // 设计稿 .tab：12.5px，选中 primary 加粗，未选中 text-2
      labelStyle: widget.tabStyle ?? (isDesktop ? const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500) : null),
      unselectedLabelStyle:
          widget.tabStyle ?? (isDesktop ? const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400) : null),
      unselectedLabelColor: isDesktop ? Theme.of(context).colorScheme.onSurfaceVariant : null,
      tabs: tabs
          .map((title) =>
              Tab(height: isDesktop ? 34 : null, child: Text(tabLabel(title), style: widget.tabStyle, maxLines: 1)))
          .toList(),
    );

    PreferredSizeWidget appBar;
    if (widget.title != null) {
      appBar = AppBar(
        title: widget.title,
        bottom: tabBar,
        centerTitle: true,
        actions: [
          ShareWidget(
              proxyServer: widget.proxyServer, request: widget.request.get(), response: widget.response.get()),
          const SizedBox(width: 3),
          DetailMenuWidget(request: widget.request.get()),
          const SizedBox(width: 10),
        ],
      );
    } else if (widget.windowId == null && Platforms.isDesktop()) {
      var request = widget.request.get();
      if (request == null) {
        // 未选中请求：不展示标题栏和 tab 条，右侧面板留白
        appBar = const PreferredSize(preferredSize: Size.zero, child: SizedBox());
      } else {
        appBar = PreferredSize(
            preferredSize: const Size.fromHeight(kTextTabBarHeight + 44),
            child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  detailTitleBar(request),
                  tabBar,
                ])));
      }
    } else if (Platforms.isDesktop()) {
      // 桌面子窗口：同主窗口详情，URL 标题栏 + tab 条；
      // URL 栏同时把 tab 条压到 macOS 红绿灯（隐藏式标题栏，悬浮在左上约 72px）之下，
      // 标题栏自身内容也要右移避开红绿灯
      var request = widget.request.get();
      if (request == null) {
        appBar = PreferredSize(
            preferredSize: tabBar.preferredSize,
            child: Material(color: Theme.of(context).colorScheme.surface, child: tabBar));
      } else {
        appBar = PreferredSize(
            preferredSize: const Size.fromHeight(kTextTabBarHeight + 44),
            child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                      padding: EdgeInsets.only(left: Platform.isMacOS ? 72 : 0),
                      child: detailTitleBar(request)),
                  tabBar,
                ])));
      }
    } else {
      appBar = tabBar;
    }

    return Scaffold(
      endDrawerEnableOpenDragGesture: false,
      // 桌面端详情区用纯白底（用户反馈 #F5F6F8 发灰）；手机端保持主题默认
      backgroundColor: isDesktop ? Theme.of(context).colorScheme.surface : null,
      appBar: appBar,
      body: Padding(
          padding: EdgeInsets.only(
              left: isDesktop ? 16 : 20, right: isDesktop ? 16 : 20, top: isDesktop ? 14 : 10),
          child: isDesktop && widget.request.get() == null
              ? const SizedBox() // 未选中请求：空白，不渲染 tab 内容
              : TabBarView(
            physics: Platforms.isDesktop() ? const NeverScrollableScrollPhysics() : null, //桌面禁止滑动
            controller: _tabController,
            children: isMqtt
                ? [
                    SelectionArea(child: Overview(widget.request, widget.response)),
                    SelectionArea(child: MqttMessages(widget.request)),
                  ]
                : [
                    SelectionArea(child: Overview(widget.request, widget.response)),
                    KeepAliveWrapper(child: request()),
                    KeepAliveWrapper(child: response()),
                    SelectionArea(
                        child: isStreamMessages
                            ? Websocket(widget.request, widget.response)
                            : Cookies(widget.request, widget.response)),
                  ],
          )),
    );
  }

  /// 设计稿 .dp-panel：桌面端请求/响应/Cookies tab 内容包白卡片（圆角 10 + 边框）
  Widget detailCard(Widget child) {
    if (!Platforms.isDesktop()) {
      return child; // 手机端保持平铺
    }
    var theme = Theme.of(context);
    return Container(
        decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(color: cardBorderColor(theme)),
            borderRadius: BorderRadius.circular(10)),
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: child));
  }

  Widget request() {
    if (widget.request.get() == null) {
      return const SizedBox();
    }

    var scrollController = ScrollController(); //处理body也有滚动条问题
    // 路径带查询参数（pathAndQuery），下方「查询参数」分区仍提供逐项解析
    var path = widget.request.get()?.pathAndQuery ?? '';
    try {
      path = Uri.decodeFull(path);
    } catch (_) {}

    return detailCard(SingleChildScrollView(
        controller: scrollController,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          overviewRow(context, localizations.path, path),
          RequestParams(widget.request),
          ...message(widget.request.get(), "Request", scrollController)
        ])));
  }

  Widget response() {
    if (widget.response.get() == null) {
      return const SizedBox();
    }

    var scrollController = ScrollController();
    return detailCard(SingleChildScrollView(
        controller: scrollController,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 设计稿：状态码值按状态码语义色（200 绿）
          overviewRow(context, localizations.statusCode, widget.response.get()?.status.toString(),
              valueColor: statusColor(widget.response.get()?.status.code, Theme.of(context))),
          ...message(widget.response.get(), "Response", scrollController)
        ])));
  }

  String tabLabel(String title) {
    switch (title) {
      case 'General':
        return localizations.overview;
      case 'Request':
        return localizations.request;
      case 'Response':
        return localizations.response;
      default:
        return title; // Cookies / WebSocket / SSE / MQTT 保持原文
    }
  }

  Widget detailTitleBar(HttpRequest request) {
    var url = request.requestUrl;
    try {
      url = Uri.decodeFull(url);
    } catch (_) {}

    var theme = Theme.of(context);
    return Container(
        height: 44,
        padding: const EdgeInsets.only(left: 16, right: 8),
        child: Row(children: [
          Text(request.method.name.toUpperCase(),
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: request.isWebSocket == true
                      // 设计稿 --ws：浅色 #6E3FC1，暗黑 #9B72E0
                      ? (theme.brightness == Brightness.light ? const Color(0xFF6E3FC1) : DarkPalette.ws)
                      : methodColor(request.method, theme))),
          const SizedBox(width: 10),
          Expanded(
              child: SelectableText(url,
                  maxLines: 1,
                  contextMenuBuilder: contextMenu,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface))),
          const SizedBox(width: 4),
          miniAction(
              tooltip: localizations.copyUrl,
              icon: 'copy',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: request.requestUrl)).then((_) {
                  if (mounted) FlutterToastr.show(localizations.copied, context);
                });
              }),
          miniAction(
              tooltip: localizations.repeat, icon: 'refresh', onPressed: () => resendRequest(request)),
          Builder(builder: (context) {
            _checkFavorited(request);
            var favorited = _favoritedId == request.requestId && _favorited;
            // 已收藏：琥珀色实心星（Material filled）；未收藏：中性灰线条星（设计 SVG）
            var amber = Theme.of(context).brightness == Brightness.light ? const Color(0xFFB76E00) : DarkPalette.warn;
            return miniAction(
                tooltip: localizations.favorite,
                icon: 'star',
                iconWidget: favorited ? Icon(Icons.star, size: 16, color: amber) : null,
                onPressed: () => _toggleFavorite(request));
          }),
        ]));
  }

  /// 设计稿 .mini：26x26 灰色小图标按钮（iconWidget 优先于 icon，用于实心/自定义图标）
  Widget miniAction(
      {required String tooltip,
      required String icon,
      required VoidCallback onPressed,
      Color? color,
      Widget? iconWidget}) {
    return Tooltip(
        message: tooltip,
        child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onPressed,
            child: SizedBox(
                width: 26,
                height: 26,
                child: Center(
                    child: iconWidget ??
                        SvgIcon(icon, size: 15, color: color ?? Theme.of(context).colorScheme.onSurfaceVariant)))));
  }

  void resendRequest(HttpRequest httpRequest) {
    var proxyServer = widget.proxyServer;
    var proxyInfo = proxyServer != null && proxyServer.isRunning
        ? ProxyInfo.of("127.0.0.1", proxyServer.port)
        : null;
    HttpClients.proxyRequest(httpRequest.copy(uri: httpRequest.requestUrl), proxyInfo: proxyInfo);
    FlutterToastr.show(localizations.reSendRequest, context, rootNavigator: true);
  }

  List<Widget> message(HttpMessage? message, String type, ScrollController scrollController) {
    Widget bodyWidgets = HttpBodyWidget(
        key: type == "Request" ? requestHttpBodyKey : responseHttpBodyKey,
        hideRequestRewrite: widget.windowId != null,
        httpMessage: message,
        scrollController: scrollController);

    return [
      HeadersWidget(title: type, message: message, valueTextStyle: textStyle),
      // 卡片内统一 14px 水平内边距（设计稿 .kv/.d-sec padding 14）
      Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: bodyWidgets),
    ];
  }
}

/// 设计稿 --text-3：浅色 #8F959E，暗黑 #6F747D
Color text3Color(ThemeData theme) =>
    theme.brightness == Brightness.light ? const Color(0xFF8F959E) : DarkPalette.text3;

/// 设计稿 行 hover（.row:hover / .rl-row:hover）：浅色 #F7F8FA，暗黑 --hover-weak #2A2D33
Color rowHoverColor(ThemeData theme) =>
    theme.brightness == Brightness.light ? const Color(0xFFF7F8FA) : DarkPalette.hoverWeak;

/// 设计稿 .kv 行之间的 #F2F3F5 细分隔线
Widget kvDivider(BuildContext context) {
  return Divider(height: 1, thickness: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.35));
}

/// 可折叠分区小标题（Cookies/Query 参数共用）：文字 + 尾部 chevron，折叠时显示条数；整行 hover 效果
Widget collapsibleSectionLabel(BuildContext context, String label, int count, bool expanded, VoidCallback onTap) {
  var theme = Theme.of(context);
  var text3 = text3Color(theme);
  var style = TextStyle(fontSize: 14, height: 1.5, letterSpacing: 0.3, color: text3);
  return InkWell(
      onTap: onTap,
      // 整行 hover 焦点效果：设计稿行 hover #F7F8FA
      hoverColor: rowHoverColor(theme),
      child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 14, top: 10, bottom: 4),
          child: Row(children: [
            Text(label, style: style),
            const SizedBox(width: 2),
            Icon(expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16, color: text3),
            if (!expanded && count > 0) Text(' · $count', style: style),
          ])));
}

class RequestParams extends StatefulWidget {
  /// 展开状态跨请求保持（旧版行为）：默认折叠，点开一个详情的折叠/展开对后续详情生效
  static bool initiallyExpanded = false;

  final ValueWrap<HttpRequest> request;

  const RequestParams(this.request, {super.key});

  @override
  State<RequestParams> createState() => _RequestParamsState();
}

class _RequestParamsState extends State<RequestParams> {
  @override
  Widget build(BuildContext context) {
    var request = widget.request.get();
    if (request == null) {
      return const SizedBox();
    }
    var params = request.requestUri?.queryParametersAll;
    if (params == null || params.isEmpty) {
      return const SizedBox();
    }
    var content = <Widget>[];
    var count = 0;
    params.forEach((name, values) {
      for (var val in values) {
        if (content.isNotEmpty) {
          content.add(kvDivider(context));
        }
        content.add(overviewRow(context, name, val));
        count++;
      }
    });

    var expanded = RequestParams.initiallyExpanded;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 与 Cookies 同款可折叠小标题：chevron + 折叠时显示条数
      collapsibleSectionLabel(context, AppLocalizations.of(context)!.queryParams, count, expanded, () {
        setState(() => RequestParams.initiallyExpanded = !expanded);
      }),
      if (expanded) ...content,
    ]);
  }
}

class Overview extends StatelessWidget {
  final ValueWrap<HttpRequest> request;

  final ValueWrap<HttpResponse> response;

  const Overview(this.request, this.response, {super.key});

  @override
  Widget build(BuildContext context) {
    var request = this.request.get();
    if (request == null) {
      return const SizedBox();
    }
    var localizations = AppLocalizations.of(context)!;
    var response = this.response.get();
    String requestUrl = request.requestUrl;
    try {
      requestUrl = Uri.decodeFull(request.requestUrl);
    } catch (_) {}
    if (request.protocolVersion == 'MQTT') {
      return Container(
          color: Theme.of(context).colorScheme.surface,
          child: ListView(padding: const EdgeInsets.only(top: 2, bottom: 12), children: [
            overviewCard(context, [
              overviewRow(context, 'Connection', requestUrl),
              overviewRow(context, 'Protocol', 'MQTT over TLS'),
              overviewRow(context, 'Packets', request.messages.length.toString()),
              overviewRow(context, 'Start Time', request.requestTime.formatMillisecond()),
              if (request.processInfo != null) overviewRow(context, 'App', request.processInfo!.name),
            ])
          ]));
    }

    // 设计稿 Overview 卡：状态码/协议/耗时/大小/远程地址/请求时间/App 七行（桌面端严格对齐）；
    // URL/方法/双 Content-Type 仅手机端 General 保留（桌面端 URL+方法已在顶部标题栏，类型见 Body 分区标签）
    var isDesktop = Platforms.isDesktop();
    return Container(
        color: Theme.of(context).colorScheme.surface,
        child: ListView(padding: const EdgeInsets.only(top: 2, bottom: 12), children: [
          overviewCard(context, [
            overviewRow(context, localizations.statusCode, response?.status.toString(),
                valueColor: statusColor(response?.status.code, Theme.of(context))),
            overviewRow(context, localizations.protocol, request.protocolVersion),
            overviewRow(context, localizations.duration, _durationText(response)),
            overviewRow(context, localizations.size, _sizeText(context, request, response)),
            overviewRow(context, localizations.remoteAddress,
                '${response?.remoteHost ?? ''}${response?.remotePort == null ? '' : ':${response?.remotePort}'}'),
            overviewRow(context, localizations.requestTime, request.requestTime.formatMillisecond()),
            if (request.processInfo != null) overviewRow(context, localizations.app, request.processInfo!.name),
            if (!isDesktop) ...[
              overviewRow(context, localizations.requestUrl, requestUrl),
              overviewRow(context, localizations.requestMethod, request.method.name),
              overviewRow(context, localizations.requestType, request.headers.contentType),
              overviewRow(context, localizations.responseType, response?.headers.contentType),
            ],
          ]),
          if (response != null && (response.body?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 12),
            ResponsePreviewCard(response),
          ],
        ]));
  }
}

/// 设计稿 Overview 耗时长："342 ms"（数值与单位间空格；costTime 原始格式 "84ms"/"1.23s"）
String? _durationText(HttpResponse? response) {
  var cost = response?.costTime();
  if (cost == null || cost.isEmpty) {
    return cost;
  }
  return cost.replaceAllMapped(RegExp(r'(\d)(ms|s)$'), (m) => '${m[1]} ${m[2]}');
}

/// 设计稿 Overview 大小行：请求 1.2 KB · 响应 8.6 KB (gzip)
String _sizeText(BuildContext context, HttpRequest request, HttpResponse? response) {
  var localizations = AppLocalizations.of(context)!;
  var reqSize = _kbText(request.packageSize);
  var respSize = _kbText(response?.packageSize);
  if (respSize.isEmpty) {
    return '${localizations.request} $reqSize';
  }
  var text = '${localizations.request} $reqSize · ${localizations.response} $respSize';
  if (response?.headers.isGzip == true) {
    text += ' (gzip)';
  }
  return text;
}

/// 1.2 KB / 8.6 KB 风格（去除多余的 0）
String _kbText(int? size) {
  if (size == null) {
    return '';
  }
  if (size < 1025) {
    return '$size B';
  }
  if (size > 1024 * 1024) {
    var mb = size / 1024 / 1024;
    return '${mb.toStringAsFixed(mb == mb.roundToDouble() ? 0 : 1)} MB';
  }
  var kb = size / 1024;
  return '${kb.toStringAsFixed(kb == kb.roundToDouble() ? 0 : 1)} KB';
}

/// 手机端详情 AppBar 标题（设计稿 .p-ptitle）：METHOD（语义色加粗）+ host/path，单行省略
Widget mobileDetailTitle(BuildContext context, HttpRequest request) {
  var theme = Theme.of(context);
  // 收藏/历史从 JSON 恢复时 hostAndPort 不持久化（为 null），退回 remoteDomain() 解析 uri
  var host = request.hostAndPort?.toString() ?? request.remoteDomain() ?? '';
  return Text.rich(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      TextSpan(children: [
        TextSpan(
            text: '${request.method.name} ',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: methodColor(request.method, theme))),
        TextSpan(text: '$host${request.pathAndQuery}', style: const TextStyle(fontSize: 15)),
      ]));
}

/// 卡片描边色：浅色在设计稿 --border 基础上降透明度弱化；暗黑直接用设计稿 --border（深底上对比已足够低）
Color cardBorderColor(ThemeData theme) =>
    theme.brightness == Brightness.light ? theme.dividerColor.withValues(alpha: 0.6) : theme.dividerColor;

/// 方法颜色按设计稿：浅色 --get #1F8B4C / --post #B76E00 / --put #0E6BB8 / --delete #C4321F；
/// 暗黑对应 --get #3FB96A / --post #E8A33D / --put #4C9BE8 / --delete #E35B48
Color methodColor(HttpMethod method, ThemeData theme) {
  bool dark = theme.brightness == Brightness.dark;
  switch (method) {
    case HttpMethod.get:
      return dark ? DarkPalette.ok : const Color(0xFF1F8B4C);
    case HttpMethod.post:
      return dark ? DarkPalette.warn : const Color(0xFFB76E00);
    case HttpMethod.put:
      return dark ? DarkPalette.put : const Color(0xFF0E6BB8);
    case HttpMethod.delete:
      return dark ? DarkPalette.err : const Color(0xFFC4321F);
    default:
      return theme.colorScheme.onSurfaceVariant;
  }
}

/// 状态码颜色同方法色：2xx 绿 / 3xx 橙 / 其余红，暗黑用设计稿高亮版
Color? statusColor(int? status, ThemeData theme) {
  if (status == null) {
    return null;
  }
  bool dark = theme.brightness == Brightness.dark;
  if (status >= 200 && status < 300) {
    return dark ? DarkPalette.ok : const Color(0xFF1F8B4C);
  }
  if (status >= 300 && status < 400) {
    return dark ? DarkPalette.warn : const Color(0xFFB76E00);
  }
  return dark ? DarkPalette.err : const Color(0xFFC4321F);
}

Widget overviewCard(BuildContext context, List<Widget> rows) {
  var theme = Theme.of(context);
  var children = <Widget>[];
  for (var i = 0; i < rows.length; i++) {
    if (i > 0) {
      children.add(Divider(height: 1, thickness: 1, color: theme.dividerColor.withValues(alpha: 0.35)));
    }
    children.add(rows[i]);
  }
  return Container(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cardBorderColor(theme)),
          color: theme.colorScheme.surface),
      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Column(children: children)));
}

Widget overviewRow(BuildContext context, String label, String? value, {Color? valueColor}) {
  var theme = Theme.of(context);
  return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(
            width: 130,
            child: Text(label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(fontSize: 13, height: 1.5, color: text3Color(theme)))),
        Expanded(
            child: SelectableText(value ?? '',
                contextMenuBuilder: contextMenu,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.5,
                    color: valueColor ?? theme.colorScheme.onSurface))),
      ]));
}

/// Overview 响应体预览卡（设计稿 .code-card）：卡头 Response Body + JSON/Raw/Preview 分段，限高内部滚动
class ResponsePreviewCard extends StatefulWidget {
  final HttpResponse response;

  const ResponsePreviewCard(this.response, {super.key});

  @override
  State<ResponsePreviewCard> createState() => _ResponsePreviewCardState();
}

class _ResponsePreviewCardState extends State<ResponsePreviewCard> {
  static const double _maxHeight = 320;
  late final List<String> views;
  int viewIndex = 0;

  @override
  void initState() {
    super.initState();
    views = [
      if (_isImage()) 'Preview',
      if (_isJson()) 'JSON',
      if (!_isImage()) 'Raw',
    ];
  }

  bool _isImage() => widget.response.contentType == ContentType.image;

  bool _isJson() {
    if (widget.response.contentType == ContentType.json) return true;
    var body = widget.response.getBodyString();
    var trimmed = body.trim();
    return (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'));
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return Container(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cardBorderColor(theme)),
            color: theme.colorScheme.surface),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                  height: 36,
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(children: [
                        Text(AppLocalizations.of(context)!.responseBody,
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                        const Spacer(),
                        for (var i = 0; i < views.length; i++) fmtButton(i),
                      ]))),
              Divider(height: 1, thickness: 1, color: theme.dividerColor.withValues(alpha: 0.35)),
              ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _maxHeight),
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: SizedBox(width: double.infinity, child: bodyView()))),
            ])));
  }

  /// 设计稿 .fmt 分段小胶囊（选中底色由 Material 绘制，hover/水波纹可见）
  Widget fmtButton(int index) {
    var theme = Theme.of(context);
    var selected = index == viewIndex;
    return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Material(
            color: selected ? primarySoftBg(theme, lightAlpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            child: InkWell(
                borderRadius: BorderRadius.circular(5),
                // 设计稿小控件 hover：浅色 #F0F1F3，暗黑 --hover #31343B
                hoverColor: theme.brightness == Brightness.light ? const Color(0xFFF0F1F3) : DarkPalette.hover,
                onTap: () => setState(() => viewIndex = index),
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(views[index],
                        style: TextStyle(
                            fontSize: 11,
                            color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant))))));
  }

  Widget bodyView() {
    var view = views[viewIndex];
    if (view == 'Preview' && _isImage()) {
      return Center(
          child: Image.memory(Uint8List.fromList(widget.response.body ?? []), fit: BoxFit.scaleDown));
    }
    return futureWidget(widget.response.decodeBodyString(), (body) {
      if (view == 'JSON') {
        try {
          return JsonText(
              json: json.decode(body),
              indent: '  ',
              colorTheme: ColorTheme.of(context),
              contextMenuBuilder: contextMenu);
        } catch (_) {
          // 解析失败回退 Raw
        }
      }
      return SelectableText(body,
          contextMenuBuilder: contextMenu,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5));
    }, initialData: widget.response.getBodyString());
  }
}

class Cookies extends StatefulWidget {
  final ValueWrap<HttpRequest> request;

  final ValueWrap<HttpResponse> response;

  const Cookies(this.request, this.response, {super.key});

  @override
  State<Cookies> createState() => _CookiesState();
}

class _CookiesState extends State<Cookies> {
  /// 请求/响应 Cookies 分区默认展开，点击小标题折叠；
  /// 展开状态跨请求保持（同 RequestParams.initiallyExpanded / HeadersWidget._lastExpanded 手法）
  static bool _requestExpanded = true;
  static bool _responseExpanded = true;

  /// 请求 Cookie 个数：headers.cookies 是原始 Cookie 头行（通常 1 行含全部 cookie），
  /// 需按 ';' 拆开数键值对，否则折叠条数恒为行数（与展开后的行数对不上）
  int _requestCookieCount(List<String>? headerLines) {
    if (headerLines == null) return 0;
    var count = 0;
    for (final line in headerLines) {
      count += line.split(';').where((e) => e.contains('=')).length;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    var requestCookies = widget.request.get()?.cookies;
    var responseCookies = widget.response.get()?.headers.getList("Set-Cookie");

    var requestRows = requestCookies?.expand((cookie) => _cookieWidget(context, cookie)!).toList();
    var responseRows = responseCookies?.expand((e) => _cookieWidget(context, e)!).toList();

    var localizations = AppLocalizations.of(context)!;
    var content = ListView(children: [
      if (requestRows != null) ...[
        collapsibleSectionLabel(context, localizations.requestCookies, _requestCookieCount(requestCookies),
            _requestExpanded, () => setState(() => _requestExpanded = !_requestExpanded)),
        if (_requestExpanded) ...requestRows,
      ],
      if (responseRows != null) ...[
        collapsibleSectionLabel(context, localizations.responseCookies, responseCookies?.length ?? 0,
            _responseExpanded, () => setState(() => _responseExpanded = !_responseExpanded)),
        if (_responseExpanded) ...responseRows,
      ],
    ]);

    if (!Platforms.isDesktop()) {
      return content;
    }
    var theme = Theme.of(context);
    return Container(
        decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(color: cardBorderColor(theme)),
            borderRadius: BorderRadius.circular(10)),
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: content));
  }

  Iterable<Widget>? _cookieWidget(BuildContext context, String? cookie) {
    var headers = <Widget>[];

    cookie?.split(";").map((e) => Strings.splitFirst(e, "=")).where((element) => element != null).forEach((e) {
      if (headers.isNotEmpty) {
        headers.add(kvDivider(context));
      }
      headers.add(overviewRow(context, e!.key.trim(), e.value));
    });

    return headers;
  }
}
