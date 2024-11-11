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

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:proxypin/network/components/js/file.dart';
import 'package:proxypin/network/components/js/md5.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/util/lang.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/random.dart';
import 'package:proxypin/network/util/uri.dart';
import 'package:proxypin/ui/component/device.dart';
import 'package:path_provider/path_provider.dart';

/// @author wanghongen
/// 2023/10/06
/// js脚本
class ScriptManager {
  static String template = """
// 在请求到达服务器之前,调用此函数,您可以在此处修改请求数据
// e.g. Add/Update/Remove：Queries、Headers、Body
async function onRequest(context, request) {
  console.log(request.url);
  //URL queries
  //request.queries["name"] = "value";
  //Update or add Header
  //request.headers["X-New-Headers"] = "My-Value";
  
  // Update Body use fetch API request，具体文档可网上搜索fetch API
  //request.body = await fetch('https://www.baidu.com/').then(response => response.text());
  return request;
}

//You can modify the Response Data here before it goes to the client
async function onResponse(context, request, response) {
   //Update or add Header
  // response.headers["Name"] = "Value";
  // response.statusCode = 200;

  //var body = JSON.parse(response.body);
  //body['key'] = "value";
  //response.body = JSON.stringify(body);
  return response;
}
  """;

  static String separator = Platform.pathSeparator;
  static ScriptManager? _instance;
  bool enabled = true;
  List<ScriptItem> list = [];

  final Map<ScriptItem, String> _scriptMap = {};

  static JavascriptRuntime flutterJs = getJavascriptRuntime();

  static String? deviceId;

  static final List<LogHandler> _logHandlers = [];

  ScriptManager._();

  ///单例
  static Future<ScriptManager> get instance async {
    if (_instance == null) {
      _instance = ScriptManager._();
      await _instance?.reloadScript();

      // register channel callback
      final channelCallbacks = JavascriptRuntime.channelFunctionsRegistered[flutterJs.getEngineInstanceId()];
      channelCallbacks!["ConsoleLog"] = _instance!.consoleLog;
      deviceId = await DeviceUtils.deviceId();
      Md5Bridge.registerMd5(flutterJs);
      FileBridge.registerFile(flutterJs);
      logger.d('init script manager $deviceId');
    }
    return _instance!;
  }

  static void registerConsoleLog(int fromWindowId) {
    LogHandler logHandler = LogHandler(
        channelId: fromWindowId,
        handle: (logInfo) {
          DesktopMultiWindow.invokeMethod(fromWindowId, "consoleLog", logInfo.toJson()).onError((e, t) {
            logger.e("consoleLog error: $e");
            removeLogHandler(fromWindowId);
          });
        });
    registerLogHandler(logHandler);
  }

  static void registerLogHandler(LogHandler logHandler) {
    if (!_logHandlers.any((it) => it.channelId == logHandler.channelId)) _logHandlers.add(logHandler);
  }

  static void removeLogHandler(int channelId) {
    _logHandlers.removeWhere((element) => channelId == element.channelId);
  }

  dynamic consoleLog(dynamic args) async {
    if (_logHandlers.isEmpty) {
      return;
    }

    var level = args.removeAt(0);
    String output = args.join(' ');
    if (level == 'info') level = 'warn';
    LogInfo logInfo = LogInfo(level, output);
    for (int i = 0; i < _logHandlers.length; i++) {
      _logHandlers[i].handle.call(logInfo);
    }
  }

  ///重新加载脚本
  Future<void> reloadScript() async {
    List<ScriptItem> scripts = [];
    var file = await _path;
    logger.d("reloadScript ${file.path}");

    if (await file.exists()) {
      var content = await file.readAsString();
      if (content.isEmpty) {
        return;
      }
      var config = jsonDecode(content);
      enabled = config['enabled'] == true;
      for (var entry in config['list']) {
        scripts.add(ScriptItem.fromJson(entry));
      }
    }
    list = scripts;
    _scriptMap.clear();
  }

  static String? _homePath;

  static Future<String> homePath() async {
    if (_homePath != null) {
      return _homePath!;
    }

    if (Platform.isMacOS) {
      _homePath = await DesktopMultiWindow.invokeMethod(0, "getApplicationSupportDirectory");
    } else {
      _homePath = await getApplicationSupportDirectory().then((it) => it.path);
    }
    return _homePath!;
  }

  static Future<File> get _path async {
    final path = await homePath();
    var file = File('$path${separator}script.json');
    if (!await file.exists()) {
      await file.create();
    }
    return file;
  }

  Future<String> getScript(ScriptItem item) async {
    if (_scriptMap.containsKey(item)) {
      return _scriptMap[item]!;
    }
    final home = await homePath();
    var script = await File(home + item.scriptPath!).readAsString();
    _scriptMap[item] = script;
    return script;
  }

  ///添加脚本
  Future<void> addScript(ScriptItem item, String script) async {
    final path = await homePath();
    String scriptPath = "${separator}scripts$separator${RandomUtil.randomString(16)}.js";
    var file = File(path + scriptPath);
    await file.create(recursive: true);
    file.writeAsString(script);
    item.scriptPath = scriptPath;
    list.add(item);
    _scriptMap[item] = script;
  }

  ///更新脚本
  Future<void> updateScript(ScriptItem item, String script) async {
    if (_scriptMap[item] == script) {
      return;
    }
    final home = await homePath();
    File(home + item.scriptPath!).writeAsString(script);
    _scriptMap[item] = script;
  }

  ///删除脚本
  Future<void> removeScript(int index) async {
    var item = list.removeAt(index);
    final home = await homePath();
    File(home + item.scriptPath!).delete();
  }

  Future<void> clean() async {
    while (list.isNotEmpty) {
      var item = list.removeLast();
      final home = await homePath();
      File(home + item.scriptPath!).delete();
    }
    await flushConfig();
  }

  ///刷新配置
  Future<void> flushConfig() async {
    _path.then((value) => value.writeAsString(jsonEncode({'enabled': enabled, 'list': list})));
  }

  Map<dynamic, dynamic> scriptSession = {};

  ///脚本上下文
  Map<String, dynamic> scriptContext(ScriptItem item) {
    return {'scriptName': item.name, 'os': Platform.operatingSystem, 'session': scriptSession, "deviceId": deviceId};
  }

  ///运行脚本
  Future<HttpRequest?> runScript(HttpRequest request) async {
    if (!enabled) {
      return request;
    }
    var url = request.domainPath;
    for (var item in list) {
      if (item.enabled && item.match(url)) {
        var context = jsonEncode(scriptContext(item));
        var jsRequest = jsonEncode(convertJsRequest(request));
        String script = await getScript(item);
        var jsResult = await flutterJs.evaluateAsync(
            """var request = $jsRequest, context = $context;  request['scriptContext'] = context; $script\n  onRequest(context, request)""");
        var result = await jsResultResolve(jsResult);
        if (result == null) {
          return null;
        }
        request.attributes['scriptContext'] = result['scriptContext'];
        scriptSession = result['scriptContext']['session'] ?? {};
        var httpRequest = convertHttpRequest(request, result);

        return httpRequest;
      }
    }
    return request;
  }

  ///运行脚本
  Future<HttpResponse?> runResponseScript(HttpResponse response) async {
    if (!enabled || response.request == null) {
      return response;
    }

    var request = response.request!;
    var url = request.domainPath;
    for (var item in list) {
      if (item.enabled && item.match(url)) {
        var context = jsonEncode(request.attributes['scriptContext'] ?? scriptContext(item));
        var jsRequest = jsonEncode(convertJsRequest(request));
        var jsResponse = jsonEncode(convertJsResponse(response));
        String script = await getScript(item);
        var jsResult = await flutterJs.evaluateAsync(
            """var response = $jsResponse, context = $context;  response['scriptContext'] = context; $script
            \n  onResponse(context, $jsRequest, response);""");
        // print("response: ${jsResult.isPromise} ${jsResult.isError} ${jsResult.rawResult}");
        var result = await jsResultResolve(jsResult);
        if (result == null) {
          return null;
        }
        scriptSession = result['scriptContext']['session'] ?? {};
        return convertHttpResponse(response, result);
      }
    }
    return response;
  }

  /// js结果转换
  static Future<dynamic> jsResultResolve(JsEvalResult jsResult) async {
    try {
      if (jsResult.isPromise || jsResult.rawResult is Future) {
        jsResult = await flutterJs.handlePromise(jsResult);
      }

      if (jsResult.isPromise || jsResult.rawResult is Future) {
        jsResult = await flutterJs.handlePromise(jsResult);
      }
    } catch (e) {
      throw SignalException(jsResult.stringResult);
    }

    var result = jsResult.rawResult;
    if (Platform.isMacOS || Platform.isIOS) {
      result = flutterJs.convertValue(jsResult);
    }
    if (result is String) {
      result = jsonDecode(result);
    }
    if (jsResult.isError) {
      logger.e('jsResultResolve error: ${jsResult.stringResult}');
      throw SignalException(jsResult.stringResult);
    }
    return result;
  }

  //转换js request
  Map<String, dynamic> convertJsRequest(HttpRequest request) {
    var requestUri = request.requestUri;
    return {
      'host': requestUri?.host,
      'url': request.requestUrl,
      'path': requestUri?.path,
      'queries': requestUri?.queryParameters,
      'headers': request.headers.toMap(),
      'method': request.method.name,
      'body': request.getBodyString(),
      'rawBody': request.body
    };
  }

  //转换js response
  Map<String, dynamic> convertJsResponse(HttpResponse response) {
    dynamic body = response.getBodyString();
    if (response.contentType.isBinary) {
      body = response.body;
    }
    return {
      'headers': response.headers.toMap(),
      'statusCode': response.status.code,
      'body': body,
      'rawBody': response.body
    };
  }

  //http request
  HttpRequest convertHttpRequest(HttpRequest request, Map<dynamic, dynamic> map) {
    request.headers.clear();
    request.method = HttpMethod.values.firstWhere((element) => element.name == map['method']);
    String query = UriUtils.mapToQuery(map['queries']);

    var requestUri = request.requestUri!.replace(path: map['path'], query: query);
    if (requestUri.isScheme('https')) {
      request.uri = requestUri.path + (requestUri.hasQuery ? '?${requestUri.query}' : '');
    } else {
      request.uri = requestUri.toString();
    }

    map['headers'].forEach((key, value) {
      if (value is List) {
        request.headers.addValues(key, value.map((e) => e.toString()).toList());
        return;
      }
      request.headers.add(key, value);
    });

    //判断是否是二进制
    if (Lists.getElementType(map['body']) == int) {
      request.body = Lists.convertList<int>(map['body']);
      return request;
    }

    request.body = map['body']?.toString().codeUnits;

    if (request.body != null && (request.charset == 'utf-8' || request.charset == 'utf8')) {
      request.body = utf8.encode(map['body'].toString());
    }
    return request;
  }

  //http response
  HttpResponse convertHttpResponse(HttpResponse response, Map<dynamic, dynamic> map) {
    response.headers.clear();
    response.status = HttpStatus.valueOf(map['statusCode']);
    map['headers'].forEach((key, value) {
      if (value is List) {
        response.headers.addValues(key, value.map((e) => e.toString()).toList());
        return;
      }

      response.headers.add(key, value);
    });

    response.headers.remove(HttpHeaders.CONTENT_ENCODING);

    //判断是否是二进制
    if (Lists.getElementType(map['body']) == int) {
      response.body = Lists.convertList<int>(map['body']);
      return response;
    }

    response.body = map['body']?.toString().codeUnits;
    if (response.body != null && (response.charset == 'utf-8' || response.charset == 'utf8')) {
      response.body = utf8.encode(map['body'].toString());
    }

    return response;
  }
}

class LogHandler {
  final int channelId;
  final Function(LogInfo logInfo) handle;

  LogHandler({required this.channelId, required this.handle});
}

class LogInfo {
  final DateTime time;
  final String level;
  final String output;

  LogInfo(this.level, this.output, {DateTime? time}) : time = time ?? DateTime.now();

  factory LogInfo.fromJson(Map<String, dynamic> json) {
    return LogInfo(json['level'], json['output'], time: DateTime.fromMillisecondsSinceEpoch(json['time']));
  }

  Map<String, dynamic> toJson() {
    return {'time': time.millisecondsSinceEpoch, 'level': level, 'output': output};
  }

  @override
  String toString() {
    return '{time: $time, level: $level, output: $output}';
  }
}

class ScriptItem {
  bool enabled = true;
  String? name;
  String url;
  String? scriptPath;
  RegExp? urlReg;

  ScriptItem(this.enabled, this.name, this.url, {this.scriptPath});

  //匹配url
  bool match(String url) {
    urlReg ??= RegExp(this.url.replaceAll("*", ".*"));
    return urlReg!.hasMatch(url);
  }

  factory ScriptItem.fromJson(Map<dynamic, dynamic> json) {
    return ScriptItem(json['enabled'], json['name'], json['url'], scriptPath: json['scriptPath']);
  }

  Map<String, dynamic> toJson() {
    return {'enabled': enabled, 'name': name, 'url': url, 'scriptPath': scriptPath};
  }

  @override
  String toString() {
    return 'ScriptItem{enabled: $enabled, name: $name, url: $url, scriptPath: $scriptPath}';
  }
}
