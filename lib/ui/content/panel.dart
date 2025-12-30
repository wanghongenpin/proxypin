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

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/state_component.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/content/web_socket.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/platform.dart';

import 'body.dart';
import 'headers.dart';
import 'menu.dart';

///网络请求详情页
///@Author: wanghongen
class NetworkTabController extends StatefulWidget {
  static GlobalKey<NetworkTabState>? currentKey;
  final int? windowId;
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

  @override
  State<StatefulWidget> createState() {
    return NetworkTabState();
  }

  static NetworkTabController? get current => currentKey?.currentWidget as NetworkTabController?;
}

class NetworkTabState extends State<NetworkTabController> with SingleTickerProviderStateMixin {
  final tabs = [
    'General',
    'Request',
    'Response',
    'Cookies',
  ];

  final TextStyle textStyle = const TextStyle(fontSize: 14);
  late TabController _tabController;

  final GlobalKey<HttpBodyState> requestHttpBodyKey = GlobalKey<HttpBodyState>();
  final GlobalKey<HttpBodyState> responseHttpBodyKey = GlobalKey<HttpBodyState>();

  void changeState() {
    setState(() {});
  }

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: tabs.length, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index != 1) {
        requestHttpBodyKey.currentState?.hideSearchOverlay();
      }
      if (_tabController.index != 2) {
        responseHttpBodyKey.currentState?.hideSearchOverlay();
      }
    });

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
    bool isWebSocket = widget.request.get()?.isWebSocket == true;
    bool isSse = widget.response.get()?.headers.contentType.toLowerCase().startsWith('text/event-stream') == true;
    bool isStreamMessages = isWebSocket || isSse;
    if (isSse) {
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
      tabs: tabs.map((title) => Tab(child: Text(title, style: widget.tabStyle, maxLines: 1))).toList(),
    );

    Widget appBar = widget.title == null
        ? tabBar
        : AppBar(
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

    return Scaffold(
      endDrawerEnableOpenDragGesture: false,
      appBar: appBar as PreferredSizeWidget?,
      body: Padding(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 10),
          child: TabBarView(
            physics: Platforms.isDesktop() ? const NeverScrollableScrollPhysics() : null, //桌面禁止滑动
            controller: _tabController,
            children: [
              SelectionArea(child: General(widget.request, widget.response)),
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
        child:
            Column(children: [RowWidget("Path", path), ...message(widget.request.get(), "Request", scrollController)]));
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

  List<Widget> message(HttpMessage? message, String type, ScrollController scrollController) {
    Widget bodyWidgets = HttpBodyWidget(
        key: type == "Request" ? requestHttpBodyKey : responseHttpBodyKey,
        hideRequestRewrite: widget.windowId != null,
        httpMessage: message,
        scrollController: scrollController);

    return [HeadersWidget(title: type, message: message, valueTextStyle: textStyle), bodyWidgets];
  }
}

Widget expansionTile(String title, List<Widget> content) {
  return ExpansionTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
      tilePadding: const EdgeInsets.only(left: 0),
      expandedAlignment: Alignment.topLeft,
      initiallyExpanded: true,
      shape: const Border(),
      children: content);
}

class General extends StatelessWidget {
  final ValueWrap<HttpRequest> request;

  final ValueWrap<HttpResponse> response;

  const General(this.request, this.response, {super.key});

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
    var content = [
      const SizedBox(height: 10),
      RowWidget("Request URL", requestUrl),
      const SizedBox(height: 15),
      RowWidget("Request Method", request.method.name),
      const SizedBox(height: 15),
      RowWidget("Protocol", request.protocolVersion),
      const SizedBox(height: 15),
      RowWidget("Status Code", response?.status.toString()),
      const SizedBox(height: 15),
      RowWidget("Remote Address",
          '${response?.remoteHost ?? ''}${response?.remotePort == null ? '' : ':${response?.remotePort}'}'),
      const SizedBox(height: 15),
      RowWidget("Request Time", request.requestTime.formatMillisecond()),
      const SizedBox(height: 15),
      RowWidget("Duration", response?.costTime()),
      const SizedBox(height: 15),
      RowWidget("Request Content-Type", request.headers.contentType),
      const SizedBox(height: 15),
      RowWidget("Response Content-Type", response?.headers.contentType),
      const SizedBox(height: 15),
      RowWidget("Request Package", getPackage(request.packageSize)),
      const SizedBox(height: 15),
      RowWidget("Response Package", getPackage(response?.packageSize)),
      const SizedBox(height: 15),
    ];
    if (request.processInfo != null) {
      content.add(RowWidget("App", request.processInfo!.name));
      content.add(const SizedBox(height: 15));
    }

    return ListView(children: [expansionTile("General", content)]);
  }
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
