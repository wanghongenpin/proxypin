/*
 * Copyright 2023 Hongen Wang
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

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/http_client.dart';
import 'package:proxypin/ui/component/split_view.dart';
import 'package:proxypin/ui/component/state_component.dart';
import 'package:proxypin/ui/content/body.dart';
import 'package:proxypin/utils/curl.dart';
import 'package:proxypin/utils/lang.dart';

/// @author wanghongen
class RequestEditor extends StatefulWidget {
  final WindowController? windowController;
  final HttpRequest? request;

  const RequestEditor({super.key, this.request, this.windowController});

  @override
  State<StatefulWidget> createState() {
    return RequestEditorState();
  }
}

class RequestEditorState extends State<RequestEditor> {
  final UrlQueryNotifier _queryNotifier = UrlQueryNotifier();
  final requestLineKey = GlobalKey<_RequestLineState>();
  final requestKey = GlobalKey<_HttpState>();
  final responseKey = GlobalKey<_HttpState>();

  ValueNotifier responseChange = ValueNotifier<bool>(false);
  HttpRequest? request;
  HttpResponse? response;

  bool showCURLDialog = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    request = widget.request;
    HardwareKeyboard.instance.addHandler(onKeyEvent);
    if (widget.request == null) {
      curlParse();
    }
  }

  bool onKeyEvent(KeyEvent event) {
    //cmd+w 关闭窗口
    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      HardwareKeyboard.instance.removeHandler(onKeyEvent);
      responseChange.dispose();
      widget.windowController?.close();
      return true;
    }

    //粘贴
    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyV) {
      curlParse();
      return true;
    }

    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(onKeyEvent);
    responseChange.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(localizations.httpRequest, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          toolbarHeight: Platform.isWindows ? 36 : null,
          centerTitle: true,
          actions: [
            TextButton.icon(
                onPressed: () async => sendRequest(), icon: const Icon(Icons.send), label: Text(localizations.send)),
            const SizedBox(width: 10)
          ],
        ),
        body: Column(children: [
          _RequestLine(key: requestLineKey, request: request, urlQueryNotifier: _queryNotifier),
          Expanded(
              child: VerticalSplitView(
            ratio: 0.53,
            left: _HttpWidget(
              key: requestKey,
              title: const Text("Request", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              message: request,
              urlQueryNotifier: _queryNotifier,
            ),
            right: ValueListenableBuilder(
                valueListenable: responseChange,
                builder: (_, value, __) => _HttpWidget(
                    key: responseKey,
                    title: Row(children: [
                      const Text("Response", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      const Spacer(),
                      Text(response?.status.toString() ?? '', style: const TextStyle(fontSize: 14))
                    ]),
                    message: response,
                    readOnly: true)),
          )),
        ]));
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

    responseKey.currentState?.change(null);
    responseChange.value = !responseChange.value;

    Map? proxyResult = await DesktopMultiWindow.invokeMethod(0, 'getProxyInfo');
    ProxyInfo? proxyInfo = proxyResult == null ? null : ProxyInfo.of(proxyResult['host'], proxyResult['port']);

    HttpClients.proxyRequest(request, proxyInfo: proxyInfo, timeout: Duration(seconds: 15)).then((response) {
      FlutterToastr.show(localizations.requestSuccess, context);
      this.response = response;
      responseKey.currentState?.change(response);
      responseChange.value = !responseChange.value;
    }).catchError((e) {
      FlutterToastr.show('${localizations.fail}$e', context);
    });
  }

  curlParse() async {
    var data = await Clipboard.getData('text/plain');
    if (data == null || data.text == null) {
      return;
    }

    var text = data.text;
    if (text?.trimLeft().startsWith('curl') == true && mounted && !showCURLDialog) {
      showCURLDialog = true;
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
                          request = parseCurl(text!);
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
      ).then((value) => showCURLDialog = false);
    }
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

class _HttpState extends State<_HttpWidget> {
  List<String> tabs = ['Header', 'Body'];
  final headerKey = GlobalKey<KeyValState>();
  Map<String, List<String>> initHeader = {};
  HttpMessage? message;
  TextEditingController? body;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  String? getBody() {
    return body?.text;
  }

  HttpHeaders? getHeaders() {
    return HttpHeaders.fromJson(headerKey.currentState?.getParams() ?? {});
  }

  @override
  void initState() {
    super.initState();
    if (widget.urlQueryNotifier != null) {
      tabs.insert(0, "URL Params");
    }

    message = widget.message;
    body = TextEditingController(text: widget.message?.bodyAsString);
    if (widget.message?.headers == null && !widget.readOnly) {
      initHeader["User-Agent"] = ["ProxyPin/1.1.6"];
      initHeader["Accept"] = ["*/*"];
      return;
    }
  }

  change(HttpMessage? message) {
    this.message = message;
    body?.text = message?.bodyAsString ?? '';
    headerKey.currentState?.refreshParam(message?.headers.getHeaders());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message == null && widget.readOnly) {
      return Scaffold(appBar: AppBar(title: widget.title), body: Center(child: Text(localizations.emptyData)));
    }

    return SingleChildScrollView(
        child: SizedBox(
            height: MediaQuery.of(context).size.height - 120,
            child: DefaultTabController(
                length: tabs.length,
                child: Scaffold(
                  primary: false,
                  appBar: PreferredSize(
                      preferredSize: const Size.fromHeight(70),
                      child: AppBar(
                        title: widget.title,
                        bottom: TabBar(tabs: tabs.map((e) => Tab(text: e, height: 35)).toList()),
                      )),
                  body: Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: TabBarView(
                        children: [
                          if (tabs.length == 3)
                            KeyValWidget(
                                paramNotifier: widget.urlQueryNotifier,
                                params: message is HttpRequest
                                    ? (message as HttpRequest).requestUri?.queryParametersAll
                                    : null),
                          KeyValWidget(
                              key: headerKey,
                              params: message?.headers.getHeaders() ?? initHeader,
                              readOnly: widget.readOnly),
                          _body()
                        ],
                      )),
                ))));
  }

  Widget _body() {
    if (widget.readOnly) {
      return KeepAliveWrapper(
          child: SingleChildScrollView(child: HttpBodyWidget(httpMessage: message, hideRequestRewrite: true)));
    }

    return TextFormField(autofocus: true, controller: body, readOnly: widget.readOnly, minLines: 20, maxLines: 20);
  }
}

///请求行
class _RequestLine extends StatefulWidget {
  final HttpRequest? request;
  final UrlQueryNotifier? urlQueryNotifier;

  const _RequestLine({super.key, this.request, this.urlQueryNotifier});

  @override
  State<StatefulWidget> createState() {
    return _RequestLineState();
  }
}

class _RequestLineState extends State<_RequestLine> {
  String requestMethod = HttpMethod.get.name;
  TextEditingController requestUrl = TextEditingController(text: "");

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
    return TextField(
        controller: requestUrl,
        decoration: InputDecoration(
            prefix: DropdownButton(
              padding: const EdgeInsets.only(right: 10),
              underline: const SizedBox(),
              isDense: true,
              focusColor: Colors.transparent,
              value: requestMethod,
              items: HttpMethod.methods().map((it) => DropdownMenuItem(value: it.name, child: Text(it.name))).toList(),
              onChanged: (String? value) {
                setState(() {
                  requestMethod = value!;
                });
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
  TextEditingController key;
  TextEditingController value;

  KeyVal(this.key, this.value);
}

///key value
class KeyValWidget extends StatefulWidget {
  final Map<String, List<String>>? params;
  final bool readOnly; //只读
  final UrlQueryNotifier? paramNotifier;

  const KeyValWidget({super.key, this.params, this.readOnly = false, this.paramNotifier});

  @override
  State<StatefulWidget> createState() => KeyValState();
}

class KeyValState extends State<KeyValWidget> with AutomaticKeepAliveClientMixin {
  final List<KeyVal> _params = [];

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.paramNotifier?.urlListener((url) => onChange(url));
    if (widget.params == null) {
      var keyVal = KeyVal(TextEditingController(), TextEditingController());
      _params.add(keyVal);
      return;
    }

    widget.params?.forEach((name, values) {
      for (var val in values) {
        var keyVal = KeyVal(TextEditingController(text: name), TextEditingController(text: val));
        _params.add(keyVal);
      }
    });
  }

  @override
  dispose() {
    clear();
    super.dispose();
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
        _params.add(KeyVal(TextEditingController(text: key), TextEditingController(text: val)));
        continue;
      }

      var keyVal = _params[index++];
      keyVal.key.text = key;
      keyVal.value.text = val ?? '';
    }

    _params.length = index;
    setState(() {});
  }

  notifierChange() {
    if (widget.paramNotifier == null) return;
    String query = _params
        .where((e) => e.enabled && e.key.text.isNotEmpty)
        .map((e) => "${e.key.text}=${e.value.text}".replaceAll("&", "%26"))
        .join("&");
    widget.paramNotifier?.onParamChange(query);
  }

  clear() {
    for (var element in _params) {
      element.key.dispose();
      element.value.dispose();
    }
    _params.clear();
  }

  //刷新param
  refreshParam(Map<String, List<String>>? headers) {
    clear();
    setState(() {
      headers?.forEach((name, values) {
        for (var val in values) {
          var keyVal = KeyVal(TextEditingController(text: name), TextEditingController(text: val));
          _params.add(keyVal);
        }
      });
    });
  }

  ///获取所有请求头
  Map<String, List<String>> getParams() {
    Map<String, List<String>> map = {};
    for (var keVal in _params) {
      if (keVal.key.text.isEmpty || !keVal.enabled) {
        continue;
      }
      map[keVal.key.text] ??= [];
      map[keVal.key.text]!.add(keVal.value.text);
    }

    return map;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    var list = [
      const Row(children: [
        SizedBox(width: 38),
        Expanded(flex: 4, child: Text('Key')),
        Expanded(flex: 5, child: Text('Value'))
      ]),
      ..._buildRows(),
    ];

    if (!widget.readOnly) {
      list.add(TextButton(
        child: Text(localizations.add, textAlign: TextAlign.center),
        onPressed: () {
          setState(() {
            _params.add(KeyVal(TextEditingController(), TextEditingController()));
          });
        },
      ));
    }
    return Scaffold(
        body: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ListView.separated(
                separatorBuilder: (context, index) =>
                    index == list.length ? const SizedBox() : const Divider(thickness: 0.2),
                itemBuilder: (context, index) => list[index],
                itemCount: list.length)));
  }

  List<Widget> _buildRows() {
    List<Widget> list = [];
    for (var keyVal in _params) {
      list.add(_row(
          keyVal,
          widget.readOnly
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 15),
                  child: InkWell(
                      onTap: () {
                        setState(() {
                          _params.remove(keyVal);
                          keyVal.key.dispose();
                          keyVal.value.dispose();
                        });
                        notifierChange();
                      },
                      child: const Icon(Icons.remove_circle, size: 16)))));
    }

    return list;
  }

  Widget _cell(TextEditingController val, {bool isKey = false}) {
    return Container(
        padding: const EdgeInsets.only(right: 5),
        child: TextFormField(
            readOnly: widget.readOnly,
            style: TextStyle(fontSize: 13, fontWeight: isKey ? FontWeight.w500 : null),
            controller: val,
            onChanged: (val) => notifierChange(),
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
                isDense: true,
                hintStyle: const TextStyle(color: Colors.grey),
                contentPadding: const EdgeInsets.fromLTRB(5, 13, 5, 13),
                focusedBorder: widget.readOnly
                    ? null
                    : OutlineInputBorder(
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)),
                border: InputBorder.none,
                hintText: isKey ? "Key" : "Value")));
  }

  Widget _row(KeyVal keyVal, Widget? op) {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      if (op != null)
        Checkbox(
            value: keyVal.enabled,
            onChanged: (val) {
              setState(() {
                keyVal.enabled = val!;
              });
              notifierChange();
            }),
      Container(width: 5),
      Expanded(flex: 4, child: _cell(keyVal.key, isKey: true)),
      const Text(":", style: TextStyle(color: Colors.deepOrangeAccent)),
      const SizedBox(width: 8),
      Expanded(flex: 6, child: _cell(keyVal.value)),
      op ?? const SizedBox()
    ]);
  }
}
