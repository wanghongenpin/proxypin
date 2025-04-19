import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter_js/javascript_runtime.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/util/file_read.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/utils/platform.dart';

/*
 * Based on bits and pieces from different OSS sources
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// ignore: non_constant_identifier_names
var _XHR_DEBUG = false;

setXhrDebug(bool value) => _XHR_DEBUG = value;

const HTTP_GET = "get";
const HTTP_POST = "post";
const HTTP_PATCH = "patch";
const HTTP_DELETE = "delete";
const HTTP_PUT = "put";
const HTTP_HEAD = "head";

enum HttpMethod { put, get, post, delete, patch, head }

String _debugSendNativeCallback() {
  if (_XHR_DEBUG) {
    return """console.log("XMLHttpRequest._send_native_callback");
      console.log("arguments");
      console.log(arguments);
      console.log(responseInfo);
      console.log(responseText);
      console.log(error);""";
  } else
    return "";
}

final String xhrJsCode = """
function XMLHttpRequest() {
  this._send_native = XMLHttpRequestExtension_send_native;
  this._httpMethod = null;
  this._url = null;
  this._requestHeaders = [];
  this._responseHeaders = [];
  this.response = null;
  this.responseText = null;
  this.responseXML = null;
  this.onreadystatechange = null;
  this.onloadstart = null;
  this.onprogress = null;
  this.onabort = null;
  this.onerror = null;
  this.onload = null;
  this.onloadend = null;
  this.ontimeout = null;
  this.readyState = 0;
  this.status = 0;
  this.statusText = "";
  this.withCredentials = null;
};
// readystate enum
XMLHttpRequest.UNSENT = 0;
XMLHttpRequest.OPENED = 1;
XMLHttpRequest.HEADERS = 2;
XMLHttpRequest.LOADING = 3;
XMLHttpRequest.DONE = 4;
XMLHttpRequest.prototype.constructor = XMLHttpRequest;
XMLHttpRequest.prototype.open = function(httpMethod, url) {
  this._httpMethod = httpMethod;
  this._url = url;
  this.readyState = XMLHttpRequest.OPENED;
  if (typeof this.onreadystatechange === "function") {
    //console.log("Calling onreadystatechange(OPENED)...");
    this.onreadystatechange();
  }
};
XMLHttpRequest.prototype.send = function(data) {
  this.readyState = XMLHttpRequest.LOADING;
  if (typeof this.onreadystatechange === "function") {
    //console.log("Calling onreadystatechange(LOADING)...");
    this.onreadystatechange();
  }
  if (typeof this.onloadstart === "function") {
    //console.log("Calling onloadstart()...");
    this.onloadstart();
  }
  var that = this;
  this._send_native(this._httpMethod, this._url, this._requestHeaders, data || null, function(responseInfo, responseText, error) {
    that._send_native_callback(responseInfo, responseText, error);
  }, this);
};
XMLHttpRequest.prototype.abort = function() {
  this.readyState = XMLHttpRequest.UNSENT;
  // Note: this.onreadystatechange() is not supposed to be called according to the XHR specs
}
// responseInfo: {statusCode, statusText, responseHeaders}
XMLHttpRequest.prototype._send_native_callback = function(responseInfo, responseText, error) {
  ${_debugSendNativeCallback()}
  if (this.readyState === XMLHttpRequest.UNSENT) {
    console.log("XHR native callback ignored because the request has been aborted");
    if (typeof this.onabort === "function") {
      //console.log("Calling onabort()...");
      this.onabort();
    }
    return;
  }
  if (this.readyState != XMLHttpRequest.LOADING) {
    // Request was not expected
    console.log("XHR native callback ignored because the current state is not LOADING");
    return;
  }
  // Response info
  // TODO: responseXML?
  this.responseURL = this._url;
  this.status = responseInfo.statusCode;
  this.statusText = responseInfo.statusText;
  this.responseBody = responseInfo.body;
  this._responseHeaders = responseInfo.responseHeaders || [];
  this.readyState = XMLHttpRequest.DONE;
  // Response
  this.response = null;
  this.responseText = null;
  this.responseXML = null;
  if (error) {
    this.responseText = error;
  } else {
    this.responseText = responseText;
    this.response = {
      body: responseInfo.body,
    }
    // console.log('RESPONSE TEXT: ' + responseText);
  }
  this.readyState = XMLHttpRequest.DONE;
  if (typeof this.onreadystatechange === "function") {
    //console.log("Calling onreadystatechange(DONE)...");
    this.onreadystatechange();
  }
  if (error === "timeout") {
    // Timeout
    console.warn("Got XHR timeout");
    if (typeof this.ontimeout === "function") {
      //console.log("Calling ontimeout()...");
      this.ontimeout();
    }
  } else if (error) {
    // Error
    console.warn("Got XHR error:", error);
    if (typeof this.onerror === "function") {
      //console.log("Calling onerror()...");
      this.onerror();
    }
  } else {
    // Success
    //console.log("XHR success: response =", this.response);
    if (typeof this.onload === "function") {
      //console.log("Calling onload()...");
      this.onload();
    }
  }
  if (typeof this.onloadend === "function") {
    //console.log("Calling onloadend()...");
    this.onloadend();
  }
};
XMLHttpRequest.prototype.setRequestHeader = function(header, value) {
  this._requestHeaders.push([header, value]);
};
XMLHttpRequest.prototype.getAllResponseHeaders = function() {
  var ret = "";
  for (var i = 0; i < this._responseHeaders.length; i++) {
    var keyValue = this._responseHeaders[i];
    ret += keyValue[0] + ": " + keyValue[1] + "\\r\\n";
  }
  return ret;
};
XMLHttpRequest.prototype.getResponseHeader = function(name) {
  var ret = "";
  for (var i = 0; i < this._responseHeaders.length; i++) {
    var keyValue = this._responseHeaders[i];
    if (keyValue[0] !== name) continue;
    if (ret === "") ret += ", ";
    ret += keyValue[1];
  }
  return ret;
};
// XMLHttpRequest.prototype.overrideMimeType = function() {
//   // TODO
// };
this.XMLHttpRequest = XMLHttpRequest;""";

RegExp regexpHeader = RegExp("^([\\w-])+:(?!\\s*\$).+\$");

class XhrPendingCall {
  int? idRequest;
  String? method;
  String? url;
  Map<String, String> headers;
  String? body;

  XhrPendingCall({
    required this.idRequest,
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
  });
}

const XHR_PENDING_CALLS_KEY = "xhrPendingCalls";

http.Client? httpClient;

xhrSetHttpClient(http.Client client) {
  httpClient = client;
}

extension JavascriptRuntimeXhrExtension on JavascriptRuntime {
  List<dynamic>? getPendingXhrCalls() {
    return dartContext[XHR_PENDING_CALLS_KEY];
  }

  bool hasPendingXhrCalls() => getPendingXhrCalls()!.isNotEmpty;

  void clearXhrPendingCalls() {
    dartContext[XHR_PENDING_CALLS_KEY] = [];
  }

  Future<void> enableFetch2({bool enabledProxy = false}) async {
    enableXhr2(enabledProxy: enabledProxy);
    final fetchPolyfill = await FileRead.readAsString('assets/js/fetch.js');
    final evalFetchResult = evaluate(fetchPolyfill);
    logger.d('Eval Fetch Result: $evalFetchResult');
  }

  Future<http.Client> createClient(enabledProxy) async {
    if (!enabledProxy) {
      return http.Client();
    }

    // ProxyServer.current.isRunning
    var httpClient = HttpClient();
    print(ProxyServer.current?.isRunning);
    String proxy;
    if (Platforms.isDesktop()) {
      Map? proxyResult = await DesktopMultiWindow.invokeMethod(0, 'getProxyInfo');
      if (proxyResult == null) {
        return http.Client();
      }
      proxy = "${proxyResult['host']}:${proxyResult['port']}";
    } else {
      if (ProxyServer.current?.isRunning == true) {
        proxy = "127.0.0.1:${ProxyServer.current!.port}";
      } else {
        return http.Client();
      }
    }

    httpClient.findProxy = (uri) {
      return "PROXY $proxy";
    };

    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;

    // 创建一个 IOClient 实例，将 HttpClient 传入
    return IOClient(httpClient);
  }

  void enableXhr2({bool enabledProxy = false}) async {
    httpClient = httpClient ?? await createClient(enabledProxy);
    dartContext[XHR_PENDING_CALLS_KEY] = [];

    Timer.periodic(Duration(milliseconds: 40), (timer) {
      // exits if there is no pending call to remote
      if (!hasPendingXhrCalls()) return;

      // collect the pending calls into a local variable making copies
      List<dynamic> pendingCalls = List<dynamic>.from(getPendingXhrCalls()!);
      // clear the global pending calls list
      clearXhrPendingCalls();

      // for each pending call, calls the remote http service
      pendingCalls.forEach((element) async {
        XhrPendingCall pendingCall = element as XhrPendingCall;
        HttpMethod eMethod = HttpMethod.values
            .firstWhere((e) => e.toString().toLowerCase() == ("HttpMethod.${pendingCall.method}".toLowerCase()));
        late http.Response response;
        switch (eMethod) {
          case HttpMethod.head:
            response = await httpClient!.head(
              Uri.parse(pendingCall.url!),
              headers: pendingCall.headers,
            );
            break;
          case HttpMethod.get:
            response = await httpClient!.get(
              Uri.parse(pendingCall.url!),
              headers: pendingCall.headers,
            );
            break;
          case HttpMethod.post:
            response = await httpClient!.post(
              Uri.parse(pendingCall.url!),
              body: (pendingCall.body is String) ? pendingCall.body : jsonEncode(pendingCall.body),
              headers: pendingCall.headers,
            );
            break;
          case HttpMethod.put:
            response = await httpClient!.put(
              Uri.parse(pendingCall.url!),
              body: (pendingCall.body is String) ? pendingCall.body : jsonEncode(pendingCall.body),
              headers: pendingCall.headers,
            );
            break;
          case HttpMethod.patch:
            response = await httpClient!.patch(
              Uri.parse(pendingCall.url!),
              body: (pendingCall.body is String) ? pendingCall.body : jsonEncode(pendingCall.body),
              headers: pendingCall.headers,
            );
            break;
          case HttpMethod.delete:
            response = await httpClient!.delete(
              Uri.parse(pendingCall.url!),
              headers: pendingCall.headers,
            );
            break;
        }
        // assuming request was successfully executed
        String? responseText;
        List<int>? body;
        try {
          responseText = utf8.decode(response.bodyBytes);
          responseText = jsonEncode(json.decode(responseText));
        } on Exception {
          // responseText = response.body;
          body = response.bodyBytes;
        }

        // logger.d('RESPONSE TEXT: $responseText');
        final xhrResult = XmlHttpRequestResponse(
          responseText: responseText,
          responseInfo: XhtmlHttpResponseInfo(statusCode: 200, statusText: "OK", body: body),
        );

        final responseInfo = jsonEncode(xhrResult.responseInfo);
        //final responseText = xhrResult.responseText; //.replaceAll("\\n", "\\\n");
        final error = xhrResult.error;
        // send back to the javascript environment the
        // response for the http pending callback
        this.evaluate(
          "globalThis.xhrRequests[${pendingCall.idRequest}].callback($responseInfo, `$responseText`, $error);",
        );
      });
    });

    this.evaluate("""
    var xhrRequests = {};
    var idRequest = -1;
    function XMLHttpRequestExtension_send_native() {
      idRequest += 1;
      var cb = arguments[4];
      var context = arguments[5];
      xhrRequests[idRequest] = {
        callback: function(responseInfo, responseText, error) {
          cb(responseInfo, responseText, error);
        }
      };
      var args = [];
      args[0] = arguments[0];
      args[1] = arguments[1];
      args[2] = arguments[2];
      args[3] = arguments[3];
      args[4] = idRequest;
      sendMessage('SendNative', JSON.stringify(args));
    }
    """);

    final evalXhrResult = this.evaluate(xhrJsCode);

    if (_XHR_DEBUG) print('RESULT evalXhrResult: $evalXhrResult');

    this.onMessage('SendNative', (arguments) {
      try {
        String? method = arguments[0];
        String? url = arguments[1];
        dynamic headersList = arguments[2];
        String? body = arguments[3];
        int? idRequest = arguments[4];

        Map<String, String> headers = {};
        headersList.forEach((header) {
          // final headerMatch = regexpHeader.allMatches(value).first;
          // String? headerName = headerMatch.group(0);
          // String? headerValue = headerMatch.group(1);
          // if (headerName != null) {
          //   headers[headerName] = headerValue ?? '';
          // }
          String headerKey = header[0];
          headers[headerKey] = header[1];
        });
        (dartContext[XHR_PENDING_CALLS_KEY] as List<dynamic>).add(
          XhrPendingCall(
            idRequest: idRequest,
            method: method,
            url: url,
            headers: headers,
            body: body,
          ),
        );
      } on Error catch (e) {
        if (_XHR_DEBUG) print('ERROR calling sendNative on Dart: >>>> $e');
      } on Exception catch (e) {
        if (_XHR_DEBUG) print('Exception calling sendNative on Dart: >>>> $e');
      }
    });
  }
}

class XhtmlHttpResponseInfo {
  final int? statusCode;
  final String? statusText;
  final List<int>? body;
  final List<List<String>> responseHeaders = [];

  XhtmlHttpResponseInfo({
    this.body,
    this.statusCode,
    this.statusText,
  });

  void addResponseHeaders(String name, String value) {
    responseHeaders.add([name, value]);
  }

  Map<String, Object?> toJson() {
    return {
      "statusCode": statusCode,
      "statusText": statusText,
      "body": body,
      "responseHeaders": jsonEncode(responseHeaders)
    };
  }
}

class XmlHttpRequestResponse {
  final String? responseText;
  final String? error; // should be timeout in case of timeout
  final XhtmlHttpResponseInfo? responseInfo;

  XmlHttpRequestResponse({this.responseText, this.responseInfo, this.error});

  Map<String, Object?> toJson() {
    return {'responseText': responseText, 'responseInfo': responseInfo!.toJson(), 'error': error};
  }
}
