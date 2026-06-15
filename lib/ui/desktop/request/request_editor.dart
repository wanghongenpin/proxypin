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

import 'package:code_forge/code_forge.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/search/finder.dart';
import 'package:proxypin/ui/component/split_view.dart';
import 'package:proxypin/ui/component/state_component.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/content/body.dart';
import 'package:proxypin/utils/curl.dart';
import 'package:proxypin/utils/highlight_languages.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/xml_formatter.dart';

import '../../component/http_method_popup.dart';

enum RequestEditorSource {
  editor,
  breakpointRequest,
  breakpointResponse,
}

/// @author wanghongen
class RequestEditor extends StatefulWidget {
  final WindowController? windowController;
  final HttpRequest? request;
  final RequestEditorSource source;
  final Function(HttpRequest? request)? onExecuteRequest;
  final Function(HttpResponse? response)? onExecuteResponse;
  final HttpResponse? response;

  const RequestEditor({
    super.key,
    this.request,
    this.response,
    this.windowController,
    this.source = RequestEditorSource.editor,
    this.onExecuteRequest,
    this.onExecuteResponse,
  });

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

  ValueNotifier<int> responseChange = ValueNotifier<int>(-1);
  HttpRequest? request;
  HttpResponse? response;

  bool showCURLDialog = false;
  bool executed = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    request = widget.request;
    response = widget.response;
    if (response != null) {
      responseChange.value = 1;
    }
    HardwareKeyboard.instance.addHandler(onKeyEvent);
    if (widget.request == null) {
      curlParse();
    }
  }

  bool onKeyEvent(KeyEvent event) {
    if ((HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isAltPressed) &&
        event.logicalKey == LogicalKeyboardKey.enter) {
      sendRequest();
      return true;
    }

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
    if ((widget.source == RequestEditorSource.breakpointRequest ||
            widget.source == RequestEditorSource.breakpointResponse) &&
        !executed) {
      if (widget.source == RequestEditorSource.breakpointRequest) {
        widget.onExecuteRequest?.call(null);
      } else {
        widget.onExecuteResponse?.call(null);
      }
    }

    HardwareKeyboard.instance.removeHandler(onKeyEvent);
    responseChange.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var title = localizations.httpRequest;
    var buttonText = localizations.send;
    IconData icon = Icons.send;

    if (widget.source == RequestEditorSource.breakpointRequest) {
      title = "Breakpoint Request";
      buttonText = localizations.execute;
      icon = Icons.play_arrow;
    } else if (widget.source == RequestEditorSource.breakpointResponse) {
      title = "Breakpoint Response";
      buttonText = localizations.execute;
      icon = Icons.play_arrow;
    }

    return Scaffold(
        appBar: AppBar(
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          toolbarHeight: Platform.isWindows ? 36 : null,
          centerTitle: true,
          actions: [
            TextButton.icon(
                onPressed: () async {
                  if (widget.source == RequestEditorSource.editor) {
                    sendRequest();
                  } else {
                    executeBreakpoint();
                  }
                },
                icon: Icon(icon),
                label: Text(buttonText)),
            if (widget.source == RequestEditorSource.breakpointRequest ||
                widget.source == RequestEditorSource.breakpointResponse)
              TextButton.icon(
                  onPressed: () {
                    // ignore breakpoint
                    if (widget.source == RequestEditorSource.breakpointRequest) {
                      widget.onExecuteRequest?.call(null);
                    } else {
                      widget.onExecuteResponse?.call(null);
                    }
                    widget.windowController?.close();
                  },
                  icon: const Icon(Icons.cancel),
                  label: Text(localizations.cancel)),
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
              readOnly: widget.source == RequestEditorSource.breakpointResponse,
            ),
            right: ValueListenableBuilder(
                valueListenable: responseChange,
                builder: (_, value, __) {
                  return Stack(
                    children: [
                      Offstage(offstage: value != 0, child: const Center(child: CircularProgressIndicator())),
                      Offstage(
                          offstage: value == 0,
                          child: _HttpWidget(
                              key: responseKey,
                              title: Row(children: [
                                const Text("Response", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                const Spacer(),
                                Text.rich(TextSpan(children: [
                                  TextSpan(
                                      text: response?.protocolVersion,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          decorationColor: Colors.green,
                                          color: Colors.green)),
                                  WidgetSpan(child: SizedBox(width: 12)),
                                  TextSpan(
                                      text: response?.status.code.toString() ?? '',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                          color: response?.status.isSuccessful() == true ? Colors.green : Colors.red))
                                ]))
                              ]),
                              message: response,
                              readOnly: widget.source != RequestEditorSource.breakpointResponse))
                    ],
                  );
                }),
          )),
        ]));
  }

  ///发送请求
  Future<void> sendRequest() async {
    var currentState = requestLineKey.currentState!;
    var headers = requestKey.currentState?.getHeaders();
    var requestBody = requestKey.currentState?.getBody();
    String url = currentState.requestUrl.text;
    HttpRequest request = HttpRequest(currentState.requestMethod, Uri.parse(url).toString(),
        protocolVersion: this.request?.protocolVersion ?? "HTTP/1.1");
    request.headers.addAll(headers);
    request.body = requestBody == null ? null : utf8.encode(requestBody);

    responseKey.currentState?.change(null);
    responseChange.value = 0;

    Map? proxyResult = await DesktopMultiWindow.invokeMethod(0, 'getProxyInfo');
    ProxyInfo? proxyInfo = proxyResult == null ? null : ProxyInfo.of(proxyResult['host'], proxyResult['port']);

    HttpClients.proxyRequest(request, proxyInfo: proxyInfo, timeout: Duration(seconds: 30)).then((response) {
      this.response = response;
      responseKey.currentState?.change(response);
      responseChange.value = 1;
      // if (mounted) FlutterToastr.show(localizations.requestSuccess, context);
    }).catchError((e, stackTrace) {
      logger.e("Request failed", error: e, stackTrace: stackTrace);
      responseChange.value = -1;
      if (mounted) FlutterToastr.show('${localizations.fail}$e', context);
    });
  }

  void executeBreakpoint() {
    executed = true;
    if (widget.source == RequestEditorSource.breakpointRequest) {
      var currentState = requestLineKey.currentState!;
      var headers = requestKey.currentState?.getHeaders();
      var requestBody = requestKey.currentState?.getBody();
      String url = currentState.requestUrl.text;

      if (request == null) return;
      HttpRequest newRequest = request!.copy(uri: url);
      newRequest.method = currentState.requestMethod;
      newRequest.headers.clear();
      newRequest.headers.addAll(headers);
      newRequest.body = requestBody == null ? null : utf8.encode(requestBody);
      widget.onExecuteRequest?.call(newRequest);
    } else if (widget.source == RequestEditorSource.breakpointResponse) {
      var headers = responseKey.currentState?.getHeaders();
      var responseBody = responseKey.currentState?.getBody();

      if (response == null) return;
      HttpResponse newResponse = response!.copy();
      newResponse.headers.clear();
      newResponse.headers.addAll(headers);
      newResponse.body = responseBody == null ? null : utf8.encode(responseBody);
      widget.onExecuteResponse?.call(newResponse);
    }
  }

  Future<void> curlParse() async {
    var data = await Clipboard.getData('text/plain');
    if (data == null || data.text == null) {
      return;
    }

    var text = data.text;
    if (text?.startsWith("http://") == true || text?.startsWith("https://") == true) {
      requestLineKey.currentState?.requestUrl.text = text!;
      return;
    }

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
                          request = Curl.parse(text!);
                          requestKey.currentState?.change(request!);
                          requestLineKey.currentState?.change(request?.requestUrl, request?.method);
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

  ParamCallback urlListener(ParamCallback listener) => _urlNotifier = listener;

  ParamCallback paramListener(ParamCallback listener) => _paramNotifier = listener;

  void onUrlChange(String url) => _urlNotifier?.call(url);

  void onParamChange(String param) => _paramNotifier?.call(param);
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

/// 请求 Body 编辑器的数据类型选项。
/// - NONE 表示请求不带 body（编辑器隐藏，发送时 body=null，并删除 Content-Type 头）。
/// - RAW 表示无高亮且不修改 Content-Type；
/// - 其余项对应一个 [ContentType]，用户手动切换时会写入 Content-Type 请求头。
enum _BodyLanguage {
  none,
  raw,
  text,
  json,
  xml,
  formUrl,
  formData,
}

class _HttpState extends State<_HttpWidget> {
  /// 数据类型下拉显示的标签
  static const Map<_BodyLanguage, String> _bodyLanguageLabels = {
    _BodyLanguage.none: 'NONE',
    _BodyLanguage.raw: 'RAW',
    _BodyLanguage.text: 'TEXT',
    _BodyLanguage.json: 'JSON',
    _BodyLanguage.xml: 'XML',
    _BodyLanguage.formUrl: 'FORM-URL',
    _BodyLanguage.formData: 'FORM-DATA',
  };

  /// _BodyLanguage 与 ContentType 的对应关系；RAW 没有对应项
  static const Map<_BodyLanguage, ContentType> _bodyLanguageToContentType = {
    _BodyLanguage.text: ContentType.text,
    _BodyLanguage.json: ContentType.json,
    _BodyLanguage.xml: ContentType.xml,
    _BodyLanguage.formUrl: ContentType.formUrl,
    _BodyLanguage.formData: ContentType.formData,
  };

  /// 用户手动切换数据类型时，写入 Content-Type 请求头使用的 MIME 主类型。
  /// FORM-DATA 由于需要 boundary 参数才合法，单独处理。
  static const Map<_BodyLanguage, String> _bodyLanguageMime = {
    _BodyLanguage.text: 'text/plain',
    _BodyLanguage.json: 'application/json',
    _BodyLanguage.xml: 'application/xml',
    _BodyLanguage.formUrl: 'application/x-www-form-urlencoded',
    _BodyLanguage.formData: 'multipart/form-data',
  };

  List<String> tabs = ['Header', 'Body'];
  final headerKey = GlobalKey<KeyValState>();
  Map<String, List<String>> initHeader = {};
  HttpMessage? message;
  CodeForgeController? body;

  /// 当前编辑器使用的语言；初始化时按 Content-Type 推导
  _BodyLanguage _bodyLanguage = _BodyLanguage.none;
  bool _bodyWrap = true;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  String? getBody() {
    if (_bodyLanguage == _BodyLanguage.none) return null;
    return body?.text;
  }

  HttpHeaders? getHeaders() {
    return HttpHeaders.fromJson(headerKey.currentState?.getParams() ?? {});
  }

  @override
  void initState() {
    super.initState();
    if (widget.urlQueryNotifier != null) {
      tabs.insert(0, "Params");
    }

    message = widget.message;
    body = CodeForgeController()..text = widget.message?.bodyAsString ?? '';
    _bodyLanguage = _resolveLanguage(widget.message);
    if (widget.message?.headers == null && !widget.readOnly) {
      initHeader["User-Agent"] = ["ProxyPin/${AppConfiguration.version}"];
      initHeader["Accept"] = ["*/*"];
      return;
    }
  }

  @override
  void dispose() {
    body?.dispose();
    super.dispose();
  }

  void change(HttpMessage? message) {
    this.message = message;
    body?.text = message?.bodyAsString ?? '';
    _bodyLanguage = _resolveLanguage(message);
    headerKey.currentState?.refreshParam(message?.headers.getHeaders());
  }

  /// 根据消息推断编辑器初始语言；初始化推断不会回写 header。
  /// - body 为空且方法是 GET/HEAD/DELETE/OPTIONS 或没有 Content-Type 头 → NONE
  _BodyLanguage _resolveLanguage(HttpMessage? message) {
    if (message == null) return _BodyLanguage.none;

    final bodyEmpty = (message.bodyAsString.isEmpty);
    final hasContentType = message.headers.contentType.isNotEmpty;
    if (bodyEmpty && message is HttpRequest) {
      const noBodyMethods = {HttpMethod.get, HttpMethod.head, HttpMethod.delete, HttpMethod.options};
      if (noBodyMethods.contains(message.method) || !hasContentType) {
        return _BodyLanguage.none;
      }
    } else if (bodyEmpty && !hasContentType) {
      return _BodyLanguage.none;
    }

    final ct = message.contentType;
    for (final entry in _bodyLanguageToContentType.entries) {
      if (entry.value == ct) return entry.key;
    }
    return _BodyLanguage.json;
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
                initialIndex: tabs.length >= 3 ? 1 : 0,
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
                              readOnly: widget.readOnly,
                              suggestions: HttpHeaders.commonHeaderKeys),
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

    final isCN = localizations.localeName == 'zh';
    final isNone = _bodyLanguage == _BodyLanguage.none;
    final ct = _bodyLanguageToContentType[_bodyLanguage];
    final language = ct == null ? null : HighlightLanguages.getLanguage(ct);
    final isDark = Theme.brightnessOf(context) == Brightness.dark;
    final baseTheme = isDark ? atomOneDarkTheme : atomOneLightTheme;
    final pageBg = Theme.of(context).colorScheme.surface;
    final editorTheme = isDark
        ? {
            ...baseTheme,
            'root': const TextStyle(color: Color(0xffabb2bf)).copyWith(backgroundColor: pageBg),
          }
        : baseTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 10, bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _bodyToolbar(),
        const SizedBox(height: 3),
        Expanded(
          child: isNone
              ? Center(
                  child: Text(
                    isCN ? '此请求无消息体' : 'This request has no body',
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                )
              : Container(
                  decoration: BoxDecoration(border: Border.all(color: Colors.black12)),
                  child: CodeForge(
                    // CodeForge 把 language 当作 late final 在 initState 里固定，
                    // 切换数据类型后必须靠新的 key 重建组件才能让高亮实时生效；
                    // controller 由本 State 持有，重建不会丢文本。
                    key: ValueKey('body-editor-${_bodyLanguage.name}-$_bodyWrap'),
                    controller: body!,
                    autoFocus: true,
                    lineWrap: _bodyWrap,
                    language: language,
                    enableGuideLines: false,
                    selectionStyle: CodeSelectionStyle(cursorColor: Theme.of(context).colorScheme.primary),
                    editorTheme: editorTheme,
                    textStyle: const TextStyle(fontSize: 14.2),
                    finderBuilder: (c, controller) => FindPanelView(controller: controller),
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _bodyToolbar() {
    final localizations = AppLocalizations.of(context)!;
    final isCN = localizations.localeName == 'zh';
    final color = Theme.of(context).colorScheme.primary;

    return SizedBox(
        height: 34,
        child: Row(children: [
          Text(isCN ? '数据类型' : 'Type', style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<_BodyLanguage>(
              value: _bodyLanguage,
              isDense: true,
              icon: const Icon(Icons.arrow_drop_down, size: 18),
              items: _BodyLanguage.values
                  .map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(_bodyLanguageLabels[e] ?? e.name.toUpperCase(),
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500))))
                  .toList(),
              onChanged: (val) {
                if (val == null || val == _bodyLanguage) return;
                setState(() => _bodyLanguage = val);
                _syncContentTypeHeader(val);
              },
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: localizations.wordWrap,
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.wrap_text, color: _bodyWrap ? color : null),
            onPressed: _bodyLanguage == _BodyLanguage.none ? null : () => setState(() => _bodyWrap = !_bodyWrap),
          ),
          SizedBox(width: 3),
          IconButton(
            tooltip: localizations.format,
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.auto_fix_high),
            onPressed: _bodyLanguage == _BodyLanguage.none ? null : _beautifyBody,
          ),
          SizedBox(width: 3),
          IconButton(
            tooltip: localizations.copy,
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy),
            onPressed: _bodyLanguage == _BodyLanguage.none
                ? null
                : () {
                    final text = body?.text ?? '';
                    if (text.isEmpty) return;
                    Clipboard.setData(ClipboardData(text: text));
                    FlutterToastr.show(localizations.copied, context);
                  },
          ),
        ]));
  }

  /// 用户主动切换数据类型时，把 Content-Type 请求头改成对应 MIME。
  /// - NONE：删除 Content-Type；body 不发。
  /// - RAW：保持原 header 不动。
  /// - 其他：写入对应 MIME。
  void _syncContentTypeHeader(_BodyLanguage lang) {
    if (lang == _BodyLanguage.raw) return;
    final headerState = headerKey.currentState;
    if (headerState == null) return;

    if (lang == _BodyLanguage.none) {
      headerState.removeParam('Content-Type');
      return;
    }

    String mime = _bodyLanguageMime[lang] ?? 'text/plain';
    headerState.setParam('Content-Type', mime);
  }

  /// 根据当前数据类型对 body 文本做格式化
  void _beautifyBody() {
    final controller = body;
    if (controller == null) return;
    final text = controller.text;
    if (text.isEmpty) return;
    String formatted;
    switch (_bodyLanguage) {
      case _BodyLanguage.json:
        formatted = JSON.pretty(text);
        break;
      case _BodyLanguage.xml:
        formatted = XML.pretty(text);
        break;
      default:
        FlutterToastr.show(
            AppLocalizations.of(context)!.localeName == 'zh'
                ? '当前数据类型不支持美化'
                : 'Beautify is not supported for this type',
            context);
        return;
    }
    if (formatted != text) {
      controller.text = formatted;
    }
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
  HttpMethod requestMethod = HttpMethod.get;
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
    requestMethod = request.method;
  }

  @override
  dispose() {
    requestUrl.dispose();
    super.dispose();
  }

  void change(String? requestUrl, HttpMethod? requestMethod) {
    this.requestUrl.text = requestUrl ?? this.requestUrl.text;
    this.requestMethod = requestMethod ?? this.requestMethod;

    urlNotifier();
  }

  void urlNotifier() {
    var splitFirst = requestUrl.text.splitFirst("?".codeUnits.first);
    widget.urlQueryNotifier?.onUrlChange(splitFirst.length > 1 ? splitFirst.last : '');
  }

  void onQueryChange(String query) {
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
            prefix: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: MethodPopupMenu(
                value: requestMethod,
                showSeparator: true,
                onChanged: (val) {
                  setState(() => requestMethod = val!);
                },
              ),
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
  FocusNode? keyFocusNode;
  FocusNode? valueFocusNode;

  KeyVal(this.key, this.value);
}

///key value
class KeyValWidget extends StatefulWidget {
  final Map<String, List<String>>? params;
  final bool readOnly; //只读
  final UrlQueryNotifier? paramNotifier;
  final List<String>? suggestions;

  const KeyValWidget({super.key, this.params, this.readOnly = false, this.paramNotifier, this.suggestions});

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
  void onChange(String value) {
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

  void notifierChange() {
    if (widget.paramNotifier == null) return;
    String query = _params
        .where((e) => e.enabled && e.key.text.isNotEmpty)
        .map((e) => "${e.key.text}=${e.value.text}".replaceAll("&", "%26"))
        .join("&");
    widget.paramNotifier?.onParamChange(query);
  }

  void clear() {
    for (var element in _params) {
      element.key.dispose();
      element.value.dispose();
    }
    _params.clear();
  }

  //刷新param
  void refreshParam(Map<String, List<String>>? headers) {
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

  /// 设置或更新单条 header（不区分大小写匹配 key）。已存在则原地改 value，不存在则追加。
  void setParam(String name, String value) {
    KeyVal? matched;
    for (var kv in _params) {
      if (kv.key.text.toLowerCase() == name.toLowerCase()) {
        matched = kv;
        break;
      }
    }
    setState(() {
      if (matched != null) {
        matched.enabled = true;
        matched.value.text = value;
      } else {
        _params.add(KeyVal(TextEditingController(text: name), TextEditingController(text: value)));
      }
    });
    notifierChange();
  }

  /// 删除指定 header（不区分大小写匹配 key）。
  void removeParam(String name) {
    final removed = <KeyVal>[];
    setState(() {
      _params.removeWhere((kv) {
        if (kv.key.text.toLowerCase() == name.toLowerCase()) {
          removed.add(kv);
          return true;
        }
        return false;
      });
    });
    for (final kv in removed) {
      kv.key.dispose();
      kv.value.dispose();
    }
    if (removed.isNotEmpty) notifierChange();
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

  Widget _cell(KeyVal keyVal,
      {bool isKey = false,
      FocusNode? focusNode,
      List<String>? suggestions,
      Map<String, List<String>>? valueSuggestions}) {
    TextEditingController textController = isKey ? keyVal.key : keyVal.value;

    if (!widget.readOnly && (suggestions != null || valueSuggestions != null)) {
      return Container(
          padding: const EdgeInsets.only(right: 5),
          child: RawAutocomplete<String>(
            textEditingController: textController,
            focusNode: focusNode,
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return const Iterable<String>.empty();
              }

              var currentSuggestions = suggestions;
              if (!isKey && valueSuggestions?.containsKey(keyVal.key.text) == true) {
                currentSuggestions = valueSuggestions![keyVal.key.text];
              }

              if (currentSuggestions == null) {
                return const Iterable<String>.empty();
              }

              return currentSuggestions.where((String option) {
                return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
              });
            },
            onSelected: (String selection) {
              textController.text = selection;
              notifierChange();
            },
            fieldViewBuilder: (BuildContext context, TextEditingController textEditingController,
                FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
              return TextFormField(
                  controller: textEditingController,
                  focusNode: fieldFocusNode,
                  onFieldSubmitted: (String value) {
                    onFieldSubmitted();
                  },
                  onChanged: (val) {
                    if (isKey) setState(() {});
                    notifierChange();
                  },
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                      isDense: true,
                      hintStyle: const TextStyle(color: Colors.grey),
                      contentPadding: const EdgeInsets.fromLTRB(5, 13, 5, 13),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)),
                      border: InputBorder.none,
                      hintText: isKey ? "Key" : "Value"));
            },
            optionsViewBuilder:
                (BuildContext context, AutocompleteOnSelected<String> onSelected, Iterable<String> options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4.0,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (BuildContext context, int index) {
                        final String option = options.elementAt(index);
                        return InkWell(
                          onTap: () {
                            onSelected(option);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(10.0),
                            child: _buildHighlightText(option, textController.text),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ));
    }

    return Container(
        padding: const EdgeInsets.only(right: 5),
        child: TextFormField(
            readOnly: widget.readOnly,
            style: TextStyle(fontSize: 13, fontWeight: isKey ? FontWeight.w500 : null),
            controller: textController,
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
    if (widget.suggestions != null) {
      keyVal.keyFocusNode ??= FocusNode();
    }

    Map<String, List<String>>? valueSuggestions;
    if (widget.suggestions != null) {
      keyVal.valueFocusNode ??= FocusNode();
      valueSuggestions = HttpHeaders.commonHeaderValues;
    }

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
      Expanded(
          flex: 4, child: _cell(keyVal, isKey: true, suggestions: widget.suggestions, focusNode: keyVal.keyFocusNode)),
      const Text(":", style: TextStyle(color: Colors.deepOrangeAccent)),
      const SizedBox(width: 8),
      Expanded(flex: 6, child: _cell(keyVal, focusNode: keyVal.valueFocusNode, valueSuggestions: valueSuggestions)),
      op ?? const SizedBox()
    ]);
  }

  Widget _buildHighlightText(String text, String query) {
    if (query.isEmpty) {
      return Text(text);
    }

    int index = text.toLowerCase().indexOf(query.toLowerCase());
    if (index < 0) {
      return Text(text);
    }

    return Text.rich(TextSpan(children: [
      TextSpan(text: text.substring(0, index)),
      TextSpan(
          text: text.substring(index, index + query.length),
          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
      TextSpan(text: text.substring(index + query.length))
    ]));
  }
}
