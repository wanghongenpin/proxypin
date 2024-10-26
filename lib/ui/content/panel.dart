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
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/storage/favorites.dart';
import 'package:proxypin/ui/component/share.dart';
import 'package:proxypin/ui/component/state_component.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/mobile/request/request_editor.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:proxypin/utils/python.dart';

import 'body.dart';

///网络请求详情页
///@Author: wanghongen
class NetworkTabController extends StatefulWidget {
  static GlobalKey<NetworkTabState>? currentKey;

  final ProxyServer proxyServer;
  final ValueWrap<HttpRequest> request = ValueWrap();
  final ValueWrap<HttpResponse> response = ValueWrap();
  final Widget? title;
  final TextStyle? tabStyle;

  NetworkTabController(
      {HttpRequest? httpRequest, HttpResponse? httpResponse, this.title, this.tabStyle, required this.proxyServer})
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

  void changeState() {
    setState(() {});
  }

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isWebSocket = widget.request.get()?.isWebSocket == true;
    tabs[tabs.length - 1] = isWebSocket ? "WebSocket" : 'Cookies';

    var tabBar = TabBar(
      padding: const EdgeInsets.only(bottom: 0),
      controller: _tabController,
      labelPadding: const EdgeInsets.symmetric(horizontal: 10),
      tabs: tabs.map((title) => Tab(child: Text(title, style: widget.tabStyle, maxLines: 1))).toList(),
    );

    Widget appBar = widget.title == null
        ? tabBar
        : AppBar(
            title: widget.title,
            bottom: tabBar,
            actions: [
              ShareWidget(
                  proxyServer: widget.proxyServer, request: widget.request.get(), response: widget.response.get()),
              const SizedBox(width: 3),
              PopupMenuButton(
                  offset: const Offset(0, 30),
                  padding: const EdgeInsets.all(0),
                  itemBuilder: (context) => [
                        PopupMenuItem(
                            child: Text(localizations.favorite),
                            onTap: () {
                              var request = widget.request.get();
                              if (request == null) return;

                              FavoriteStorage.addFavorite(request);
                              FlutterToastr.show(localizations.addSuccess, context);
                            }),
                        PopupMenuItem(
                            child: Text(localizations.requestEdit),
                            onTap: () {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                Navigator.of(context).push(MaterialPageRoute(
                                    builder: (context) => MobileRequestEditor(
                                        request: widget.request.get(), proxyServer: widget.proxyServer)));
                              });
                            }),
                        CustomPopupMenuItem(
                            padding: const EdgeInsets.only(left: 10),
                            child: Text(localizations.copyAsPythonRequests),
                            onTap: () {
                              var request = widget.request.get();
                              if (request == null) return;

                              var text = copyAsPythonRequests(request);
                              Clipboard.setData(ClipboardData(text: text));
                              FlutterToastr.show(localizations.copied, context);
                            })
                      ],
                  child: const SizedBox(height: 38, width: 38, child: Icon(Icons.more_vert, size: 28))),
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
              SelectionArea(child: general()),
              KeepAliveWrapper(child: request()),
              KeepAliveWrapper(child: response()),
              SelectionArea(child: isWebSocket ? websocket() : cookies()),
            ],
          )),
    );
  }

  ///以聊天对话框样式展示websocket消息
  Widget websocket() {
    var request = widget.request.get();
    if (request == null) {
      return const SizedBox();
    }
    List<WebSocketFrame> messages = List.from(request.messages);
    var response = widget.response.get();
    if (response != null) {
      messages.addAll(response.messages);
    }
    messages.sort((a, b) => a.time.compareTo(b.time));

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 15),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        var message = messages[index];
        var avatar = SelectionContainer.disabled(
            child: CircleAvatar(
                backgroundColor: message.isFromClient ? Colors.green : Colors.blue,
                child:
                    Text(message.isFromClient ? 'C' : 'S', style: const TextStyle(fontSize: 18, color: Colors.white))));

        return Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              mainAxisAlignment: message.isFromClient ? MainAxisAlignment.start : MainAxisAlignment.end,
              children: [
                if (message.isFromClient) avatar,
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                      crossAxisAlignment: message.isFromClient ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                      children: [
                        SelectionContainer.disabled(
                            child:
                                Text(message.time.format(), style: const TextStyle(fontSize: 12, color: Colors.grey))),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: message.isFromClient ? Colors.green.withOpacity(0.26) : Colors.blue.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(message.payloadDataAsString),
                        )
                      ]),
                ),
                const SizedBox(width: 8),
                if (!message.isFromClient) avatar,
              ],
            ));
      },
    );
  }

  Widget general() {
    var request = widget.request.get();
    if (request == null) {
      return const SizedBox();
    }
    var response = widget.response.get();
    String requestUrl = request.requestUrl;
    try {
      requestUrl = Uri.decodeFull(request.requestUrl);
    } catch (_) {}
    var content = [
      const SizedBox(height: 10),
      rowWidget("Request URL", requestUrl),
      const SizedBox(height: 20),
      rowWidget("Request Method", request.method.name),
      const SizedBox(height: 20),
      rowWidget("Protocol", request.protocolVersion),
      const SizedBox(height: 20),
      rowWidget("Status Code", response?.status.toString()),
      const SizedBox(height: 20),
      rowWidget("Remote Address",
          '${response?.remoteHost ?? ''}${response?.remotePort == null ? '' : ':${response?.remotePort}'}'),
      const SizedBox(height: 20),
      rowWidget("Request Time", request.requestTime.formatMillisecond()),
      const SizedBox(height: 20),
      rowWidget("Duration", response?.costTime()),
      const SizedBox(height: 20),
      rowWidget("Request Content-Type", request.headers.contentType),
      const SizedBox(height: 20),
      rowWidget("Response Content-Type", response?.headers.contentType),
      const SizedBox(height: 20),
      rowWidget("Request Package", getPackage(request)),
      const SizedBox(height: 20),
      rowWidget("Response Package", getPackage(response)),
      const SizedBox(height: 20),
    ];
    if (request.processInfo != null) {
      content.add(rowWidget("App", request.processInfo!.name));
      content.add(const SizedBox(height: 20));
    }

    return ListView(children: [expansionTile("General", content)]);
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

    return ListView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [rowWidget("Path", path), ...message(widget.request.get(), "Request", scrollController)]);
  }

  Widget response() {
    if (widget.response.get() == null) {
      return const SizedBox();
    }

    var scrollController = ScrollController();
    return ListView(controller: scrollController, physics: const AlwaysScrollableScrollPhysics(), children: [
      rowWidget("StatusCode", widget.response.get()?.status.toString()),
      ...message(widget.response.get(), "Response", scrollController)
    ]);
  }

  Widget cookies() {
    var requestCookie = _cookieWidget(widget.request.get()?.cookie);

    var responseCookie = widget.response.get()?.headers.getList("Set-Cookie")?.expand((e) => _cookieWidget(e)!);
    return ListView(children: [
      requestCookie == null ? const SizedBox() : expansionTile("Request Cookies", requestCookie.toList()),
      const SizedBox(height: 20),
      responseCookie == null ? const SizedBox() : expansionTile("Response Cookies", responseCookie.toList()),
    ]);
  }

  List<Widget> message(HttpMessage? message, String type, ScrollController scrollController) {
    var headers = <Widget>[];
    message?.headers.forEach((name, values) {
      for (var v in values) {
        const nameStyle = TextStyle(fontWeight: FontWeight.w500, color: Colors.deepOrangeAccent, fontSize: 14);
        headers.add(Row(children: [
          SelectableText(name, contextMenuBuilder: contextMenu, style: nameStyle),
          const Text(": ", style: nameStyle),
          if (Platforms.isDesktop()) SizedBox(width: 5),
          Expanded(
              child: SelectableText(v, style: textStyle, contextMenuBuilder: contextMenu, maxLines: 8, minLines: 1)),
        ]));
        headers.add(const Divider(thickness: 0.1));
      }
    });

    Widget bodyWidgets = HttpBodyWidget(httpMessage: message, scrollController: scrollController);

    Widget headerWidget = ExpansionTile(
        tilePadding: const EdgeInsets.only(left: 0),
        title: Text("$type Headers", style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        initiallyExpanded: AppConfiguration.current?.headerExpanded ?? true,
        shape: const Border(),
        children: headers);

    return [headerWidget, bodyWidgets];
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

  Iterable<Widget>? _cookieWidget(String? cookie) {
    var headers = <Widget>[];

    cookie?.split(";").map((e) => Strings.splitFirst(e, "=")).where((element) => element != null).forEach((e) {
      headers.add(rowWidget(e!.key.trim(), e.value));
      headers.add(const Divider(thickness: 0.1));
    });

    return headers;
  }

  Widget rowWidget(final String name, String? value) {
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
