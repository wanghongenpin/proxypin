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
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/ui/component/state_component.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/content/body.dart';
import 'package:proxypin/ui/mobile/request/request_editor_source.dart';
import 'package:proxypin/utils/curl.dart';
import 'package:proxypin/utils/flutter_compat.dart';
import 'package:proxypin/utils/highlight_languages.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/xml_formatter.dart';

import '../../component/http_method_popup.dart';

/// @author wanghongen
class MobileRequestEditor extends StatefulWidget {
  final HttpRequest? request;
  final ProxyServer? proxyServer;
  final RequestEditorSource source;
  final Function(HttpRequest? request)? onExecuteRequest;
  final Function(HttpResponse? response)? onExecuteResponse;
  final HttpResponse? response;

  const MobileRequestEditor({
    super.key,
    this.request,
    this.response,
    required this.proxyServer,
    this.source = RequestEditorSource.editor,
    this.onExecuteRequest,
    this.onExecuteResponse,
  });

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

  bool executed = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  var tabs = const [
    Tab(text: "请求"),
    Tab(text: "响应"),
  ];

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

    tabController.dispose();
    responseChange.dispose();
    _expanded.clear();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    tabController = TabController(
        length: tabs.length,
        vsync: this,
        initialIndex: widget.source == RequestEditorSource.breakpointResponse ? 1 : 0);
    request = widget.request;
    response = widget.response;
    if (widget.request == null) {
      curlParse();
    }
  }

  Future<void> curlParse() async {
    //获取剪切板内容
    var data = await Clipboard.getData('text/plain');
    if (data == null || data.text == null) {
      return;
    }
    var text = data.text;
    if (text?.startsWith("http://") == true || text?.startsWith("https://") == true) {
      requestLineKey.currentState?.requestUrl.text = text!;
      return;
    }
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
                          requestLineKey.currentState?.change(request?.requestUrl, request?.method);
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

    var buttonText = localizations.send;
    IconData icon = Icons.send;
    if (widget.source == RequestEditorSource.breakpointRequest ||
        widget.source == RequestEditorSource.breakpointResponse) {
      buttonText = localizations.execute;
      icon = Icons.play_arrow;
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
              TextButton.icon(
                  icon: Icon(icon),
                  label: Text(buttonText),
                  onPressed: () {
                    if (widget.source == RequestEditorSource.editor) {
                      sendRequest();
                    } else {
                      executeBreakpoint();
                    }
                  })
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
                  readOnly: widget.source == RequestEditorSource.breakpointResponse,
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
                            Text(response?.protocolVersion ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.blue)),
                            const SizedBox(width: 10),
                            Text("${localizations.statusCode}: ", style: const TextStyle(fontWeight: FontWeight.w500)),
                            const SizedBox(width: 10),
                            Text(response?.status.toString() ?? "",
                                style: TextStyle(
                                    color: response?.status.isSuccessful() == true ? Colors.blue : Colors.red))
                          ]),
                          readOnly: widget.source != RequestEditorSource.breakpointResponse,
                          message: response);
                    }),
              ],
            )));
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

    var proxyInfo = widget.proxyServer?.isRunning == true ? ProxyInfo.of("127.0.0.1", widget.proxyServer?.port) : null;

    responseKey.currentState?.change(null);
    responseChange.value = 0;

    HttpClients.proxyRequest(proxyInfo: proxyInfo, request, timeout: Duration(seconds: 30)).then((response) {
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

  void executeBreakpoint() {
    executed = true;
    if (widget.source == RequestEditorSource.breakpointRequest) {
      var currentState = requestLineKey.currentState!;
      var headers = requestKey.currentState?.getHeaders();
      var requestBody = requestKey.currentState?.getBody();
      String url = currentState.requestUrl.text;

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

class _HttpState extends State<_HttpWidget> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
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

  /// _BodyLanguage 与 ContentType 的对应关系；RAW/NONE 没有对应项
  static const Map<_BodyLanguage, ContentType> _bodyLanguageToContentType = {
    _BodyLanguage.text: ContentType.text,
    _BodyLanguage.json: ContentType.json,
    _BodyLanguage.xml: ContentType.xml,
    _BodyLanguage.formUrl: ContentType.formUrl,
    _BodyLanguage.formData: ContentType.formData,
  };

  /// 用户手动切换数据类型时，写入 Content-Type 请求头使用的 MIME。
  static const Map<_BodyLanguage, String> _bodyLanguageMime = {
    _BodyLanguage.text: 'text/plain',
    _BodyLanguage.json: 'application/json',
    _BodyLanguage.xml: 'application/xml',
    _BodyLanguage.formUrl: 'application/x-www-form-urlencoded',
    _BodyLanguage.formData: 'multipart/form-data',
  };

  final headerKey = GlobalKey<KeyValState>();
  Map<String, List<String>> initHeader = {};
  HttpMessage? message;
  CodeController? body;

  /// 内层 Tab 控制器：Params(请求才有) / Headers / Body
  TabController? _innerTab;

  /// 当前编辑器使用的语言；初始化时按 Content-Type 推导
  _BodyLanguage _bodyLanguage = _BodyLanguage.none;
  bool _bodyWrap = true;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  bool get wantKeepAlive => true;

  /// 是否显示 URL Params 子 tab：仅请求消息且外层传了 query notifier 时
  bool get _hasParamsTab => widget.urlQueryNotifier != null;

  String? getBody() {
    if (_bodyLanguage == _BodyLanguage.none) return null;
    return body?.text;
  }

  @override
  void initState() {
    super.initState();
    message = widget.message;
    body = CodeController()..text = widget.message?.bodyAsString ?? '';
    _bodyLanguage = _resolveLanguage(widget.message);
    _innerTab = TabController(length: _hasParamsTab ? 3 : 2, vsync: this, initialIndex: _hasParamsTab ? 1 : 0);
    if (widget.message?.headers == null && !widget.readOnly) {
      initHeader["User-Agent"] = ["ProxyPin/${AppConfiguration.version}"];
      initHeader["Accept"] = ["*/*"];
      return;
    }
  }

  @override
  void dispose() {
    body?.dispose();
    _innerTab?.dispose();
    super.dispose();
  }

  void change(HttpMessage? message) {
    this.message = message;
    body?.text = message?.bodyAsString ?? '';
    _bodyLanguage = _resolveLanguage(message);
    headerKey.currentState?.refreshParam(message?.headers.getHeaders());
    setState(() {});
  }

  HttpHeaders? getHeaders() {
    return HttpHeaders.fromJson(headerKey.currentState?.getParams() ?? {});
  }

  /// 根据消息推断编辑器初始语言；初始化推断不会回写 header。
  /// - body 为空且方法是 GET/HEAD/DELETE/OPTIONS 或没有 Content-Type 头 → NONE
  /// - 其他情况按 Content-Type 头匹配，匹配不到归 TEXT
  _BodyLanguage _resolveLanguage(HttpMessage? message) {
    if (message == null) return _BodyLanguage.none;

    final bodyEmpty = message.bodyAsString.isEmpty;
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
    super.build(context);

    if (message == null && widget.readOnly) {
      return Center(child: Text(localizations.emptyData));
    }

    final theme = Theme.of(context);

    final paramsTab = _hasParamsTab
        ? KeyValWidget(
            title: 'URL${localizations.param}',
            paramNotifier: widget.urlQueryNotifier,
            params: message is HttpRequest ? (message as HttpRequest).requestUri?.queryParametersAll : null,
            showTitle: false,
          )
        : null;

    final headersTab = KeyValWidget(
      title: "Headers",
      params: message?.headers.getHeaders() ?? initHeader,
      key: headerKey,
      suggestions: HttpHeaders.commonHeaderKeys,
      readOnly: widget.readOnly,
      showTitle: false,
    );

    return Padding(
        padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          widget.title,
          const SizedBox(height: 8),
          TabBar(
            controller: _innerTab,
            isScrollable: false,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            labelColor: theme.colorScheme.primary,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: [
              if (_hasParamsTab) Tab(text: 'Params', height: 36),
              const Tab(text: 'Headers', height: 36),
              const Tab(text: 'Body', height: 36),
            ],
          ),
          const SizedBox(height: 6),
          // 这里用 IndexedStack 而非 TabBarView：
          // TabBarView 是惰性构建的，没访问过的 tab 不会 mount，
          // 用户直接发送时 headerKey.currentState 会是 null，导致 header 全丢。
          // IndexedStack 同时挂载所有子树（只显示一个），保证 GlobalKey 始终可达。
          Expanded(
            child: AnimatedBuilder(
              animation: _innerTab!,
              builder: (_, __) => IndexedStack(
                index: _innerTab!.index,
                children: [
                  if (paramsTab != null) SingleChildScrollView(child: paramsTab),
                  SingleChildScrollView(child: headersTab),
                  _body(),
                ],
              ),
            ),
          ),
        ]));
  }

  Widget _body() {
    if (widget.readOnly) {
      return KeepAliveWrapper(child: SingleChildScrollView(child: HttpBodyWidget(httpMessage: message)));
    }

    final isCN = localizations.localeName == 'zh';
    final isNone = _bodyLanguage == _BodyLanguage.none;
    final ct = _bodyLanguageToContentType[_bodyLanguage];
    final language = ct == null ? null : HighlightLanguages.getLanguage(ct);
    final isDark = ThemeCompat.brightnessOf(context) == Brightness.dark;
    final baseTheme = isDark ? atomOneDarkTheme : atomOneLightTheme;
    final pageBg = Theme.of(context).colorScheme.surface;
    final editorTheme = isDark
        ? {
            ...baseTheme,
            'root': const TextStyle(color: Color(0xffabb2bf)).copyWith(backgroundColor: pageBg),
          }
        : baseTheme;

    // 设置语言
    if (body != null && language != null) {
      body!.language = language;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _bodyToolbar(),
      const SizedBox(height: 4),
      Expanded(
        child: isNone
            ? Center(
                child: Text(
                  isCN ? '此请求无消息体' : 'This request has no body',
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
              )
            : Container(
                decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor)),
                child: CodeTheme(
                  data: CodeThemeData(styles: editorTheme),
                  child: CodeField(
                    key: ValueKey('body-editor-${_bodyLanguage.name}-$_bodyWrap'),
                    controller: body!,
                    wrap: _bodyWrap,
                    cursorColor: Theme.of(context).colorScheme.primary,
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
      ),
    ]);
  }

  Widget _bodyToolbar() {
    final isCN = localizations.localeName == 'zh';
    final color = Theme.of(context).colorScheme.primary;

    return SizedBox(
        height: 36,
        child: Row(children: [
          Text(isCN ? '数据类型' : 'Type', style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
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
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.wrap_text, color: _bodyWrap ? color : null),
            onPressed: _bodyLanguage == _BodyLanguage.none ? null : () => setState(() => _bodyWrap = !_bodyWrap),
          ),
          IconButton(
            tooltip: localizations.format,
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.auto_fix_high),
            onPressed: _bodyLanguage == _BodyLanguage.none ? null : _beautifyBody,
          ),
          IconButton(
            tooltip: localizations.copy,
            iconSize: 18,
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
            localizations.localeName == 'zh' ? '当前数据类型不支持美化' : 'Beautify is not supported for this type', context);
        return;
    }
    if (formatted != text) {
      controller.text = formatted;
    }
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
  HttpMethod requestMethod = HttpMethod.get;

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
    TextInput;
    return TextField(
        style: const TextStyle(fontSize: 14),
        minLines: 1,
        maxLines: 3,
        autofocus: false,
        controller: requestUrl,
        decoration: InputDecoration(
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 6, right: 6),
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
  final List<String>? suggestions;

  /// 是否使用 ExpansionTile 包裹自带标题；
  /// 内层 Tab 模式下 tab 已经标了名字，传 false 直接渲染列表更干净。
  final bool showTitle;

  const KeyValWidget(
      {super.key,
      this.params,
      this.readOnly = false,
      this.paramNotifier,
      required this.title,
      this.expanded = true,
      this.suggestions,
      this.showTitle = true});

  @override
  State<StatefulWidget> createState() {
    return KeyValState();
  }
}

final Map<String, bool> _expanded = {};

class KeyValState extends State<KeyValWidget> with AutomaticKeepAliveClientMixin {
  final List<KeyVal> _params = [];

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  bool get wantKeepAlive => true;

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
  void onChange(String value) {
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

  void notifierChange() {
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

  Future<void> _copyParam(KeyVal keyVal) async {
    final text = '${keyVal.key}: ${keyVal.value}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    FlutterToastr.show(localizations.copied, context);
  }

  //刷新param
  void refreshParam(Map<String, List<String>>? headers) {
    _params.clear();
    setState(() {
      headers?.forEach((name, values) {
        for (var val in values) {
          _params.add(KeyVal(name, val));
        }
      });
    });
  }

  /// 设置或更新单条 header（不区分大小写匹配 key）。已存在则原地改 value，不存在则追加。
  void setParam(String name, String value) {
    KeyVal? matched;
    for (var kv in _params) {
      if (kv.key.toLowerCase() == name.toLowerCase()) {
        matched = kv;
        break;
      }
    }
    setState(() {
      if (matched != null) {
        matched.enabled = true;
        matched.key = name;
        matched.value = value;
      } else {
        _params.add(KeyVal(name, value));
      }
    });
    notifierChange();
  }

  /// 删除指定 header（不区分大小写匹配 key）。
  void removeParam(String name) {
    final before = _params.length;
    setState(() => _params.removeWhere((kv) => kv.key.toLowerCase() == name.toLowerCase()));
    if (_params.length != before) notifierChange();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final addBtn = widget.readOnly
        ? const SizedBox()
        : Container(
            alignment: Alignment.center,
            child: TextButton(
                onPressed: () {
                  var keyVal = KeyVal("", "");
                  _params.add(keyVal);
                  modifyParam(keyVal);
                },
                child: Text(localizations.add, textAlign: TextAlign.center))); //添加按钮

    if (!widget.showTitle) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [..._buildRows(), addBtn],
      );
    }

    return ExpansionTile(
      title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.blue)),
      tilePadding: const EdgeInsets.only(left: 0, top: 10, bottom: 10),
      initiallyExpanded: _expanded[widget.title] ?? widget.expanded,
      onExpansionChanged: (value) => _expanded[widget.title] = value,
      shape: const Border(),
      children: [..._buildRows(), addBtn],
    );
  }

  List<Widget> _buildRows() {
    List<Widget> list = [];

    for (var element in _params) {
      Widget headerWidget = Padding(padding: const EdgeInsets.only(top: 5, bottom: 5), child: row(element));
      headerWidget = InkWell(
        onTap: () => modifyParam(element),
        onLongPress: widget.readOnly ? () => _copyParam(element) : () => deleteHeader(element),
        child: headerWidget,
      );

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
  void modifyParam(KeyVal keyVal) {
    //隐藏输入框焦点
    hideKeyword(context);
    String headerName = keyVal.key;
    String val = keyVal.value;
    showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setState) {
            return AlertDialog(
              titlePadding: const EdgeInsets.only(left: 25, top: 10),
              actionsPadding: const EdgeInsets.only(right: 10, bottom: 10),
              title: Text(widget.readOnly ? localizations.responseHeader : localizations.modifyRequestHeader,
                  style: const TextStyle(fontSize: 16)),
              content: Wrap(
                children: [
                  if (widget.suggestions != null && !widget.readOnly)
                    Autocomplete<String>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return const Iterable<String>.empty();
                        }
                        return widget.suggestions!.where((String option) {
                          return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                        });
                      },
                      onSelected: (String selection) {
                        setState(() {
                          headerName = selection;
                        });
                      },
                      fieldViewBuilder: (BuildContext context, TextEditingController textEditingController,
                          FocusNode focusNode, VoidCallback onFieldSubmitted) {
                        return TextFormField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          minLines: 1,
                          maxLines: 3,
                          decoration: InputDecoration(labelText: localizations.headerName),
                          onChanged: (value) {
                            headerName = value;
                            setState(() {});
                          },
                        );
                      },
                      initialValue: TextEditingValue(text: headerName),
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
                                      child: _buildHighlightText(option, headerName),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    )
                  else
                    TextFormField(
                      minLines: 1,
                      maxLines: 3,
                      initialValue: headerName,
                      readOnly: widget.readOnly,
                      decoration: InputDecoration(labelText: localizations.headerName),
                      onChanged: (value) {
                        headerName = value;
                        setState(() {});
                      },
                    ),
                  if (HttpHeaders.commonHeaderValues.containsKey(headerName) && !widget.readOnly)
                    Autocomplete<String>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return const Iterable<String>.empty();
                        }
                        return HttpHeaders.commonHeaderValues[headerName]!.where((String option) {
                          return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                        });
                      },
                      onSelected: (String selection) {
                        val = selection;
                      },
                      fieldViewBuilder: (BuildContext context, TextEditingController textEditingController,
                          FocusNode focusNode, VoidCallback onFieldSubmitted) {
                        return TextFormField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          minLines: 1,
                          maxLines: 8,
                          decoration: InputDecoration(labelText: localizations.value),
                          onChanged: (value) => val = value,
                        );
                      },
                      initialValue: TextEditingValue(text: val),
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
                                      child: _buildHighlightText(option, val),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    )
                  else
                    TextFormField(
                      minLines: 1,
                      maxLines: 8,
                      initialValue: val,
                      readOnly: widget.readOnly,
                      decoration: InputDecoration(labelText: localizations.value),
                      onChanged: (value) => val = value,
                    )
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(widget.readOnly ? localizations.close : localizations.cancel)),
                if (!widget.readOnly)
                  TextButton(
                      onPressed: () {
                        this.setState(() {
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
        });
  }

  //删除
  void deleteHeader(KeyVal keyVal) {
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
