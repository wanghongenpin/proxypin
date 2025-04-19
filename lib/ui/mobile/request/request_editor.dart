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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/content/body.dart';
import 'package:proxypin/utils/curl.dart';
import 'package:proxypin/utils/lang.dart';

/// @author wanghongen
class MobileRequestEditor extends StatefulWidget {
  final HttpRequest? request;
  final ProxyServer? proxyServer;

  const MobileRequestEditor({super.key, this.request, required this.proxyServer});

  @override
  State<StatefulWidget> createState() {
    return RequestEditorState();
  }
}

class RequestEditorState extends State<MobileRequestEditor> with SingleTickerProviderStateMixin {
  final UrlQueryNotifier _queryNotifier = UrlQueryNotifier();
  final requestLineKey = GlobalKey<_RequestLineState>();
  final requestKey = GlobalKey<_HttpState>();
  final responseKey = GlobalKey<_HttpState>();

  ValueNotifier<int> responseChange = ValueNotifier<int>(-1);

  late TabController tabController;

  HttpRequest? request;
  HttpResponse? response;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  var tabs = const [
    Tab(text: "请求"),
    Tab(text: "响应"),
  ];

  @override
  void dispose() {
    tabController.dispose();
    responseChange.dispose();
    _expanded.clear();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    tabController = TabController(length: tabs.length, vsync: this);
    request = widget.request;
    if (widget.request == null) {
      curlParse();
    }
  }

  curlParse() async {
    //获取剪切板内容
    var data = await Clipboard.getData('text/plain');
    if (data == null || data.text == null) {
      return;
    }
    var text = data.text;
    if (text?.trimLeft().startsWith('curl') == true && mounted) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
              title: Text(localizations.prompt),
              content: Text(localizations.curlSchemeRequest),
              actions: [
                TextButton(child: Text(localizations.cancel), onPressed: () => Navigator.of(context).pop()),
                TextButton(
                    child: Text(localizations.confirm),
                    onPressed: () {
                      try {
                        setState(() {
                          request = Curl.parse(text!);
                          requestKey.currentState?.change(request!);
                          requestLineKey.currentState?.change(request?.requestUrl, request?.method.name);
                        });
                      } catch (e) {
                        FlutterToastr.show(localizations.fail, context);
                      }
                      Navigator.of(context).pop();
                    }),
              ]);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');
    if (!isCN) {
      tabs = [
        Tab(text: localizations.request),
        Tab(text: localizations.response),
      ];
    }

    return Scaffold(
        appBar: AppBar(
            title: Text(localizations.httpRequest, style: const TextStyle(fontSize: 16)),
            centerTitle: true,
            leadingWidth: 72,
            leading: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(localizations.cancel, style: Theme.of(context).textTheme.bodyMedium)),
            actions: [
              TextButton.icon(icon: const Icon(Icons.send), label: Text(localizations.send), onPressed: sendRequest)
            ],
            bottom: TabBar(controller: tabController, tabs: tabs)),
        body: GestureDetector(
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: TabBarView(
              controller: tabController,
              children: [
                _HttpWidget(
                  title: _RequestLine(request: request, key: requestLineKey, urlQueryNotifier: _queryNotifier),
                  message: request,
                  key: requestKey,
                  urlQueryNotifier: _queryNotifier,
                ),
                ValueListenableBuilder(
                    valueListenable: responseChange,
                    builder: (_, value, __) {
                      if (value == 0) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      return _HttpWidget(
                          key: responseKey,
                          title: Row(children: [
                            Text("${localizations.statusCode}: ", style: const TextStyle(fontWeight: FontWeight.w500)),
                            const SizedBox(width: 10),
                            Text(response?.status.toString() ?? "", style: const TextStyle(color: Colors.blue))
                          ]),
                          readOnly: true,
                          message: response);
                    }),
              ],
            )));
  }

  ///发送请求
  sendRequest() async {
    var currentState = requestLineKey.currentState!;
    var headers = requestKey.currentState?.getHeaders();
    var requestBody = requestKey.currentState?.getBody();
    String url = currentState.requestUrl.text;

    HttpRequest request = HttpRequest(HttpMethod.valueOf(currentState.requestMethod), Uri.parse(url).toString());
    request.headers.addAll(headers);
    request.body = requestBody == null ? null : utf8.encode(requestBody);

    var proxyInfo = widget.proxyServer?.isRunning == true ? ProxyInfo.of("127.0.0.1", widget.proxyServer?.port) : null;

    responseKey.currentState?.change(null);
    responseChange.value = 0;

    HttpClients.proxyRequest(proxyInfo: proxyInfo, request, timeout: Duration(seconds: 15)).then((response) {
      this.response = response;
      this.response?.request = request;
      responseKey.currentState?.change(response);
      responseChange.value = 1;

      // FlutterToastr.show(localizations.requestSuccess, context);
    }).catchError((e) {
      responseChange.value = -1;
      FlutterToastr.show('${localizations.fail}$e', context);
    });

    tabController.animateTo(1);
  }
}

typedef ParamCallback = void Function(String param);

class UrlQueryNotifier {
  ParamCallback? _urlNotifier;
  ParamCallback? _paramNotifier;

  urlListener(ParamCallback listener) => _urlNotifier = listener;

  paramListener(ParamCallback listener) => _paramNotifier = listener;

  onUrlChange(String url) => _urlNotifier?.call(url);

  onParamChange(String param) => _paramNotifier?.call(param);
}

class _HttpWidget extends StatefulWidget {
  final HttpMessage? message;
  final bool readOnly;
  final Widget title;
  final UrlQueryNotifier? urlQueryNotifier;

  const _HttpWidget({this.message, this.readOnly = false, super.key, required this.title, this.urlQueryNotifier});

  @override
  State<StatefulWidget> createState() {
    return _HttpState();
  }
}

class _HttpState extends State<_HttpWidget> with AutomaticKeepAliveClientMixin {
  final headerKey = GlobalKey<KeyValState>();
  Map<String, List<String>> initHeader = {};
  HttpMessage? message;
  String? body;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  bool get wantKeepAlive => true;

  String? getBody() {
    return body;
  }

  @override
  void initState() {
    super.initState();
    message = widget.message;
    body = widget.message?.bodyAsString;
    if (widget.message?.headers == null && !widget.readOnly) {
      initHeader["User-Agent"] = ["ProxyPin/${AppConfiguration.version}"];
      initHeader["Accept"] = ["*/*"];
      return;
    }
  }

  change(HttpMessage? message) {
    this.message = message;
    body = message?.bodyAsString;
    headerKey.currentState?.refreshParam(message?.headers.getHeaders());
    setState(() {});
  }

  HttpHeaders? getHeaders() {
    return HttpHeaders.fromJson(headerKey.currentState?.getParams() ?? {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (message == null && widget.readOnly) {
      return Center(child: Text(localizations.emptyData));
    }

    return SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          widget.title,
          if (widget.urlQueryNotifier != null)
            KeyValWidget(
              title: 'URL${localizations.param}',
              paramNotifier: widget.urlQueryNotifier,
              params: message is HttpRequest ? (message as HttpRequest).requestUri?.queryParametersAll : null,
              expanded: false,
            ),
          KeyValWidget(
              title: "Headers",
              params: message?.headers.getHeaders() ?? initHeader,
              key: headerKey,
              readOnly: widget.readOnly),
          // 请求头
          const SizedBox(height: 10),
          const Text("Body", style: TextStyle(fontWeight: FontWeight.w500, color: Colors.blue)),
          _body(),
          const SizedBox(height: 10),
        ]));
  }

  Widget _body() {
    if (widget.readOnly) {
      return SingleChildScrollView(child: HttpBodyWidget(httpMessage: message));
    }

    return TextField(
        controller: TextEditingController(text: body),
        readOnly: widget.readOnly,
        onChanged: (value) => body = value,
        minLines: 3,
        maxLines: 15);
  }
}

class _RequestLine extends StatefulWidget {
  final HttpRequest? request;
  final UrlQueryNotifier? urlQueryNotifier;

  const _RequestLine({this.request, super.key, this.urlQueryNotifier});

  @override
  State<StatefulWidget> createState() {
    return _RequestLineState();
  }
}

class _RequestLineState extends State<_RequestLine> {
  TextEditingController requestUrl = TextEditingController(text: "");
  String requestMethod = HttpMethod.get.name;

  @override
  void initState() {
    super.initState();
    widget.urlQueryNotifier?.paramListener((param) => onQueryChange(param));
    if (widget.request == null) {
      requestUrl.text = 'https://';
      return;
    }
    var request = widget.request!;
    requestUrl.text = request.requestUrl;
    requestMethod = request.method.name;
  }

  @override
  dispose() {
    requestUrl.dispose();
    super.dispose();
  }

  change(String? requestUrl, String? requestMethod) {
    this.requestUrl.text = requestUrl ?? this.requestUrl.text;
    this.requestMethod = requestMethod ?? this.requestMethod;

    urlNotifier();
  }

  urlNotifier() {
    var splitFirst = requestUrl.text.splitFirst("?".codeUnits.first);
    widget.urlQueryNotifier?.onUrlChange(splitFirst.length > 1 ? splitFirst.last : '');
  }

  onQueryChange(String query) {
    var url = requestUrl.text;
    var indexOf = url.indexOf("?");
    if (indexOf == -1) {
      requestUrl.text = "$url?$query";
    } else {
      requestUrl.text = "${url.substring(0, indexOf)}?$query";
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    TextInput;
    return TextField(
        style: const TextStyle(fontSize: 14),
        minLines: 1,
        maxLines: 5,
        autofocus: false,
        controller: requestUrl,
        decoration: InputDecoration(
            prefix: DropdownButton(
              padding: const EdgeInsets.only(right: 10),
              underline: const SizedBox(),
              isDense: true,
              focusColor: Colors.transparent,
              value: requestMethod,
              items: HttpMethod.methods()
                  .map((it) =>
                      DropdownMenuItem(value: it.name, child: Text(it.name, style: const TextStyle(fontSize: 12))))
                  .toList(),
              onChanged: (String? value) {
                setState(() => requestMethod = value!);
              },
            ),
            isDense: true,
            border: const OutlineInputBorder(borderSide: BorderSide()),
            enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.grey, width: 0.3))),
        onChanged: (value) {
          urlNotifier();
        });
  }
}

class KeyVal {
  bool enabled = true;
  String key;
  String value;

  KeyVal(this.key, this.value);
}

///key value
class KeyValWidget extends StatefulWidget {
  final String title;
  final Map<String, List<String>>? params;
  final bool readOnly; //只读
  final UrlQueryNotifier? paramNotifier;
  final bool expanded;

  const KeyValWidget(
      {super.key, this.params, this.readOnly = false, this.paramNotifier, required this.title, this.expanded = true});

  @override
  State<StatefulWidget> createState() {
    return KeyValState();
  }
}

final Map<String, bool> _expanded = {};

class KeyValState extends State<KeyValWidget> {
  final List<KeyVal> _params = [];

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    widget.params?.forEach((name, values) {
      for (var val in values) {
        var keyVal = KeyVal(name, val);
        _params.add(keyVal);
      }
    });

    widget.paramNotifier?.urlListener((url) => onChange(url));
  }

  //监听url发生变化 更改表单
  onChange(String value) {
    var query = value.split("&");
    int index = 0;
    while (index < query.length) {
      var splitFirst = query[index].splitFirst('='.codeUnits.first);
      String key = splitFirst.first;
      String? val = splitFirst.length == 1 ? null : splitFirst.last;
      if (_params.length <= index) {
        _params.add(KeyVal(key, val ?? ''));
        continue;
      }

      var keyVal = _params[index++];
      keyVal.key = key;
      keyVal.value = val ?? '';
    }

    _params.length = index;
    setState(() {});
  }

  notifierChange() {
    if (widget.paramNotifier == null) return;
    String query = _params
        .where((e) => e.enabled && e.key.isNotEmpty)
        .map((e) => "${e.key}=${e.value}".replaceAll("&", "%26"))
        .join("&");
    widget.paramNotifier?.onParamChange(query);
  }

  ///获取所有请求头
  Map<String, List<String>> getParams() {
    Map<String, List<String>> map = {};
    for (var keVal in _params) {
      if (keVal.key.isEmpty || !keVal.enabled) {
        continue;
      }
      map[keVal.key] ??= [];
      map[keVal.key]!.add(keVal.value);
    }

    return map;
  }

  //刷新param
  refreshParam(Map<String, List<String>>? headers) {
    _params.clear();
    setState(() {
      headers?.forEach((name, values) {
        for (var val in values) {
          _params.add(KeyVal(name, val));
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.blue)),
      tilePadding: const EdgeInsets.only(left: 0, top: 10, bottom: 10),
      initiallyExpanded: _expanded[widget.title] ?? widget.expanded,
      onExpansionChanged: (value) => _expanded[widget.title] = value,
      shape: const Border(),
      children: [
        ..._buildRows(),
        widget.readOnly
            ? const SizedBox()
            : Container(
                alignment: Alignment.center,
                child: TextButton(
                    onPressed: () {
                      var keyVal = KeyVal("", "");
                      _params.add(keyVal);
                      modifyParam(keyVal);
                    },
                    child: Text(localizations.add, textAlign: TextAlign.center))) //添加按钮
      ],
    );
  }

  List<Widget> _buildRows() {
    List<Widget> list = [];

    for (var element in _params) {
      Widget headerWidget = Padding(padding: const EdgeInsets.only(top: 5, bottom: 5), child: row(element));
      if (!widget.readOnly) {
        headerWidget =
            InkWell(onTap: () => modifyParam(element), onLongPress: () => deleteHeader(element), child: headerWidget);
      }

      list.add(headerWidget);
      list.add(const Divider(thickness: 0.2));
    }

    return list;
  }

  //隐藏输入框焦点
  void hideKeyword(BuildContext context) {
    FocusScopeNode currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
      currentFocus.focusedChild?.unfocus();
    }
  }

  /// 修改请求头
  modifyParam(KeyVal keyVal) {
    //隐藏输入框焦点
    hideKeyword(context);
    String headerName = keyVal.key;
    String val = keyVal.value;
    showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            titlePadding: const EdgeInsets.only(left: 25, top: 10),
            actionsPadding: const EdgeInsets.only(right: 10, bottom: 10),
            title: Text(localizations.modifyRequestHeader, style: const TextStyle(fontSize: 18)),
            content: Wrap(
              children: [
                TextFormField(
                  minLines: 1,
                  maxLines: 3,
                  initialValue: headerName,
                  decoration: InputDecoration(labelText: localizations.headerName),
                  onChanged: (value) => headerName = value,
                ),
                TextFormField(
                  minLines: 1,
                  maxLines: 8,
                  initialValue: val,
                  decoration: InputDecoration(labelText: localizations.value),
                  onChanged: (value) => val = value,
                )
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localizations.cancel)),
              TextButton(
                  onPressed: () {
                    setState(() {
                      keyVal.key = headerName;
                      keyVal.value = val;
                    });
                    notifierChange();
                    Navigator.pop(ctx);
                  },
                  child: Text(localizations.modify)),
            ],
          );
        });
  }

  //删除
  deleteHeader(KeyVal keyVal) {
    showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(localizations.deleteHeaderConfirm, style: const TextStyle(fontSize: 18)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localizations.cancel)),
              TextButton(
                  onPressed: () {
                    setState(() => _params.remove(keyVal));
                    notifierChange();
                    Navigator.pop(ctx);
                  },
                  child: Text(localizations.delete)),
            ],
          );
        });
  }

  Widget row(KeyVal keyVal) {
    return Row(children: [
      if (!widget.readOnly)
        Checkbox(
            value: keyVal.enabled,
            onChanged: (val) {
              setState(() {
                keyVal.enabled = val!;
              });
              notifierChange();
            }),
      Expanded(flex: 4, child: Text(keyVal.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
      const Text(":", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
      const SizedBox(width: 8),
      Expanded(
        flex: 6,
        child: Text(keyVal.value, style: const TextStyle(fontSize: 13), maxLines: 5, overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}
