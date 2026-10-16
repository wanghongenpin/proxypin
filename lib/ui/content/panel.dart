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

import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/storage/favorites.dart';
import 'package:proxypin/ui/component/state_component.dart';
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

  NetworkTabController(
      {HttpRequest? httpRequest,
      HttpResponse? httpResponse,
      this.title,
      this.tabStyle,
      this.proxyServer,
      this.windowId})
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
    _tabController = TabController(length: tabs.length, vsync: this);
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

    var tabBar = TabBar(
      padding: const EdgeInsets.only(bottom: 0),
      controller: _tabController,
      dividerColor: Theme.of(context).dividerColor.withValues(alpha: 0.15),
      labelPadding: const EdgeInsets.symmetric(horizontal: 10),
      tabs: tabs.map((title) => Tab(child: Text(tabLabel(title), style: widget.tabStyle, maxLines: 1))).toList(),
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
      appBar = PreferredSize(
          preferredSize: Size.fromHeight(kTextTabBarHeight + (request == null ? 0 : 46)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (request != null) detailTitleBar(request),
            tabBar,
          ]));
    } else {
      appBar = tabBar;
    }

    return Scaffold(
      endDrawerEnableOpenDragGesture: false,
      appBar: appBar,
      body: Padding(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 10),
          child: TabBarView(
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

  Widget request() {
    if (widget.request.get() == null) {
      return const SizedBox();
    }

    var scrollController = ScrollController(); //处理body也有滚动条问题
    var path = widget.request.get()?.path ?? '';
    try {
      path = Uri.decodeFull(path);
    } catch (_) {}

    return SingleChildScrollView(
        controller: scrollController,
        child: Column(children: [
          RowWidget("Path", path),
          RequestParams(widget.request),
          ...message(widget.request.get(), "Request", scrollController)
        ]));
  }

  Widget response() {
    if (widget.response.get() == null) {
      return const SizedBox();
    }

    var scrollController = ScrollController();
    return SingleChildScrollView(
        controller: scrollController,
        child: Column(children: [
          RowWidget("StatusCode", widget.response.get()?.status.toString()),
          ...message(widget.response.get(), "Response", scrollController)
        ]));
  }

  String tabLabel(String title) {
    if (title == 'General') {
      return localizations.overview;
    }
    return title;
  }

  Widget detailTitleBar(HttpRequest request) {
    var url = request.requestUrl;
    try {
      url = Uri.decodeFull(url);
    } catch (_) {}

    var theme = Theme.of(context);
    return Container(
        height: 46,
        padding: const EdgeInsets.only(left: 20, right: 8, top: 4, bottom: 2),
        child: Row(children: [
          Text(request.method.name.toUpperCase(),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: request.isWebSocket == true
                      ? const Color(0xFF6E3FC1)
                      : methodColor(request.method, theme))),
          const SizedBox(width: 10),
          Expanded(
              child: SelectableText(url,
                  maxLines: 1,
                  contextMenuBuilder: contextMenu,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface))),
          const SizedBox(width: 2),
          IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              tooltip: localizations.copyUrl,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: request.requestUrl)).then((_) {
                  if (mounted) FlutterToastr.show(localizations.copied, context);
                });
              },
              icon: const Icon(Icons.copy)),
          IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              tooltip: localizations.repeat,
              onPressed: () => resendRequest(request),
              icon: const Icon(Icons.replay)),
          IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              tooltip: localizations.favorite,
              onPressed: () {
                FavoriteStorage.addFavorite(request);
                FlutterToastr.show(localizations.addSuccess, context);
              },
              icon: const Icon(Icons.star_border)),
        ]));
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

    return [HeadersWidget(title: type, message: message, valueTextStyle: textStyle), bodyWidgets];
  }
}

Widget expansionTile(String title, List<Widget> content,
    {bool initiallyExpanded = true, ValueChanged<bool>? onExpansionChanged}) {
  return ExpansionTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
      tilePadding: const EdgeInsets.only(left: 0),
      expandedAlignment: Alignment.topLeft,
      initiallyExpanded: initiallyExpanded,
      onExpansionChanged: onExpansionChanged,
      shape: const Border(),
      children: content);
}

class RequestParams extends StatelessWidget {
  static bool initiallyExpanded = false;

  final ValueWrap<HttpRequest> request;

  const RequestParams(this.request, {super.key});

  @override
  Widget build(BuildContext context) {
    var request = this.request.get();
    if (request == null) {
      return const SizedBox();
    }
    var params = request.requestUri?.queryParametersAll;
    if (params == null || params.isEmpty) {
      return const SizedBox();
    }
    var content = <Widget>[];
    params.forEach((name, values) {
      for (var val in values) {
        content.add(RowWidget(name, val));
        content.add(const Divider(thickness: 0.1, height: 10));
      }
    });

    return expansionTile("Request Params", content, initiallyExpanded: initiallyExpanded,
        onExpansionChanged: (expanded) {
      //保存展开状态
      initiallyExpanded = expanded;
    });
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
    var response = this.response.get();
    String requestUrl = request.requestUrl;
    try {
      requestUrl = Uri.decodeFull(request.requestUrl);
    } catch (_) {}
    if (request.protocolVersion == 'MQTT') {
      return ListView(children: [
        overviewCard(context, [
          overviewRow(context, 'Connection', requestUrl),
          overviewRow(context, 'Protocol', 'MQTT over TLS'),
          overviewRow(context, 'Packets', request.messages.length.toString()),
          overviewRow(context, 'Start Time', request.requestTime.formatMillisecond()),
          if (request.processInfo != null) overviewRow(context, 'App', request.processInfo!.name),
        ])
      ]);
    }

    return ListView(padding: const EdgeInsets.only(top: 2), children: [
      overviewCard(context, [
        overviewRow(context, 'Status Code', response?.status.toString(),
            valueColor: statusColor(response?.status.code)),
        overviewRow(context, 'Protocol', request.protocolVersion),
        overviewRow(context, 'Duration', response?.costTime()),
        overviewRow(context, 'Size', getPackagesSize(request, response)),
        overviewRow(context, 'Remote Address',
            '${response?.remoteHost ?? ''}${response?.remotePort == null ? '' : ':${response?.remotePort}'}'),
        overviewRow(context, 'Request Time', request.requestTime.formatMillisecond()),
        overviewRow(context, 'Request Content-Type', request.headers.contentType),
        overviewRow(context, 'Response Content-Type', response?.headers.contentType),
        overviewRow(context, 'Request URL', requestUrl),
        overviewRow(context, 'Request Method', request.method.name),
        if (request.processInfo != null) overviewRow(context, 'App', request.processInfo!.name),
      ]),
      if (response != null && ((response.body?.isNotEmpty ?? false) || response.messages.isNotEmpty)) ...[
        const SizedBox(height: 12),
        Container(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
                color: Theme.of(context).colorScheme.surface),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: HttpBodyWidget(httpMessage: response))),
        const SizedBox(height: 10),
      ],
    ]);
  }
}

Color methodColor(HttpMethod method, ThemeData theme) {
  switch (method) {
    case HttpMethod.get:
      return const Color(0xFF1F8B4C);
    case HttpMethod.post:
      return const Color(0xFFB76E00);
    case HttpMethod.put:
      return const Color(0xFF0E6BB8);
    case HttpMethod.delete:
      return const Color(0xFFC4321F);
    default:
      return theme.colorScheme.onSurfaceVariant;
  }
}

Color? statusColor(int? status) {
  if (status == null) {
    return null;
  }
  if (status >= 200 && status < 300) {
    return const Color(0xFF1F8B4C);
  }
  if (status >= 300 && status < 400) {
    return const Color(0xFFB76E00);
  }
  return const Color(0xFFC4321F);
}

Widget overviewCard(BuildContext context, List<Widget> rows) {
  var theme = Theme.of(context);
  var children = <Widget>[];
  for (var i = 0; i < rows.length; i++) {
    if (i > 0) {
      children.add(Divider(height: 1, thickness: 0.5, color: theme.dividerColor.withValues(alpha: 0.4)));
    }
    children.add(rows[i]);
  }
  return Container(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
          color: theme.colorScheme.surface),
      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Column(children: children)));
}

Widget overviewRow(BuildContext context, String label, String? value, {Color? valueColor}) {
  var theme = Theme.of(context);
  return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(
            width: 132,
            child:
                Text(label, style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant))),
        Expanded(
            child: SelectableText(value ?? '',
                contextMenuBuilder: contextMenu,
                style: TextStyle(
                    fontFamily: 'Courier', fontSize: 12.5, color: valueColor ?? theme.colorScheme.onSurface))),
      ]));
}

class Cookies extends StatelessWidget {
  final ValueWrap<HttpRequest> request;

  final ValueWrap<HttpResponse> response;

  const Cookies(this.request, this.response, {super.key});

  @override
  Widget build(BuildContext context) {
    var requestCookie = request.get()?.cookies.expand((cookie) => _cookieWidget(cookie)!);

    var responseCookie = response.get()?.headers.getList("Set-Cookie")?.expand((e) => _cookieWidget(e)!);
    return ListView(children: [
      requestCookie == null ? const SizedBox() : expansionTile("Request Cookies", requestCookie.toList()),
      const SizedBox(height: 15),
      responseCookie == null ? const SizedBox() : expansionTile("Response Cookies", responseCookie.toList()),
    ]);
  }

  Iterable<Widget>? _cookieWidget(String? cookie) {
    var headers = <Widget>[];

    cookie?.split(";").map((e) => Strings.splitFirst(e, "=")).where((element) => element != null).forEach((e) {
      headers.add(RowWidget(e!.key.trim(), e.value));
      headers.add(const Divider(thickness: 0.1, height: 10));
    });

    return headers;
  }
}

class RowWidget extends StatelessWidget {
  final String name;
  final String? value;
  final TextStyle textStyle = const TextStyle(fontSize: 14);

  const RowWidget(this.name, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
          flex: 2,
          child: SelectableText(name,
              contextMenuBuilder: contextMenu,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: Colors.deepOrangeAccent))),
      Expanded(flex: 4, child: SelectableText(contextMenuBuilder: contextMenu, style: textStyle, value ?? ''))
    ]);
  }
}
