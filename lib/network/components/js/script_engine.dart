import 'dart:convert';
import 'dart:io';

import 'package:flutter_js/flutter_js.dart';
import 'package:proxypin/network/components/js/xhr.dart';

import '../../http/http.dart';
import '../../http/http.dart' as http;
import '../../http/http_headers.dart';
import '../../util/lang.dart';
import '../../util/logger.dart';
import '../../util/uri.dart';
import 'file.dart';
import 'md5.dart';

class JavaScriptEngine {
  static Future<JavascriptRuntime> getJavaScript({Function(dynamic args)? consoleLog}) async {
    final JavascriptRuntime flutterJs = getJavascriptRuntime(xhr: false);

    // register channel callback
    if (consoleLog != null) {
      final channelCallbacks = JavascriptRuntime.channelFunctionsRegistered[flutterJs.getEngineInstanceId()];
      channelCallbacks!["ConsoleLog"] = consoleLog;
    }
    Md5Bridge.registerMd5(flutterJs);
    FileBridge.registerFile(flutterJs);

    flutterJs.enableFetch2();
    return flutterJs;
  }

  /// js结果转换
  static Future<dynamic> jsResultResolve(JavascriptRuntime flutterJs, JsEvalResult jsResult) async {
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
  static Future<Map<String, dynamic>> convertJsRequest(HttpRequest request) async {
    var requestUri = request.requestUri;
    return {
      'host': requestUri?.host,
      'url': request.requestUrl,
      'path': requestUri?.path,
      'queries': requestUri?.queryParameters,
      'headers': request.headers.toMap(),
      'method': request.method.name,
      'body': await request.decodeBodyString(),
      'rawBody': request.body
    };
  }

  //转换js response
  static Future<Map<String, dynamic>> convertJsResponse(HttpResponse response) async {
    dynamic body = await response.decodeBodyString();
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
  static HttpRequest convertHttpRequest(HttpRequest request, Map<dynamic, dynamic> map) {
    request.headers.clear();
    request.method = http.HttpMethod.values.firstWhere((element) => element.name == map['method']);
    String query = UriUtils.mapToQuery(map['queries']);

    var requestUri = request.requestUri!.replace(path: map['path'], query: query);
    if (requestUri.isScheme('https')) {
      var query = requestUri.query;
      request.uri = requestUri.path + (query.isNotEmpty ? '?${requestUri.query}' : '');
    } else {
      request.uri = requestUri.toString();
    }

    map['headers'].forEach((key, value) {
      if (value is List) {
        request.headers.addValues(key, value.map((e) => e.toString()).toList());
        return;
      }
      request.headers.set(key, value);
    });

    request.headers.remove(HttpHeaders.CONTENT_ENCODING);

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
  static HttpResponse convertHttpResponse(HttpResponse response, Map<dynamic, dynamic> map) {
    response.headers.clear();
    response.status = HttpStatus.valueOf(map['statusCode']);
    map['headers'].forEach((key, value) {
      if (value is List) {
        response.headers.addValues(key, value.map((e) => e.toString()).toList());
        return;
      }

      response.headers.set(key, value);
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
