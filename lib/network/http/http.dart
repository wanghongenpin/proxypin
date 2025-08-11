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
import 'dart:math';

import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/util/compress.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/process_info.dart';

import 'http_headers.dart';

///定义HTTP消息的接口，为HttpRequest和HttpResponse提供公共属性。
///@author WangHongEn
abstract class HttpMessage {
  /// HTTP/1.1
  static const String http1Version = "HTTP/1.1";

  ///内容类型
  static final Map<String, ContentType> contentTypes = {
    "javascript": ContentType.js,
    "text/css": ContentType.css,
    "font-woff": ContentType.font,
    "text/html": ContentType.html,
    "text/plain": ContentType.text,
    "application/x-www-form-urlencoded": ContentType.formUrl,
    "form-data": ContentType.formData,
    "image": ContentType.image,
    "video": ContentType.video,
    "application/json": ContentType.json
  };

  String protocolVersion;

  final HttpHeaders headers = HttpHeaders();

  int get contentLength => headers.contentLength;

  //报文大小
  int? packageSize;

  List<int>? _body;
  String? _bodyString;

  String? remoteHost;
  int? remotePort;

  String requestId = (DateTime.now().millisecondsSinceEpoch + Random().nextInt(999999)).toRadixString(36);
  int? streamId; // http2 streamId
  HttpMessage(this.protocolVersion);

  //json序列化
  factory HttpMessage.fromJson(Map<String, dynamic> json) {
    if (json["_class"] == "HttpRequest") {
      return HttpRequest.fromJson(json);
    }

    return HttpResponse.fromJson(json);
  }

  Map<String, dynamic> toJson();

  /// 是否是websocket协议
  bool get isWebSocket => headers.get("Upgrade") == 'websocket';

  ContentType get contentType => contentTypes.entries
      .firstWhere((element) => headers.contentType.contains(element.key),
          orElse: () => const MapEntry("unknown", ContentType.http))
      .value;

  List<int>? get body => _body;

  set body(List<int>? body) {
    _body = body;
    _bodyString = null;
    packageSize = body?.length ?? 0;
  }

  ///获取消息体编码
  String? get charset {
    var contentType = headers.contentType;
    if (contentType.isEmpty) {
      return 'utf-8';
    }

    MediaType mediaType = MediaType.valueOf(contentType);
    return mediaType.charset ?? MediaType.defaultCharset(mediaType);
  }

  ///获取消息
  String get bodyAsString {
    return getBodyString(charset: 'utf-8');
  }

  String getBodyString({String? charset}) {
    if (body == null || body?.isEmpty == true) {
      return "";
    }

    if (_bodyString != null) {
      return _bodyString!;
    }

    charset ??= this.charset;
    try {
      List<int> rawBody = body!;
      if (headers.contentEncoding == 'br') {
        rawBody = brDecode(body!);
      }

      if (headers.isGzip && isGzip(body!)) {
        rawBody = gzipDecode(body!);
      }

      if (charset == 'utf-8' || charset == 'utf8') {
        return utf8.decode(rawBody);
      }

      return String.fromCharCodes(rawBody);
    } catch (e) {
      return String.fromCharCodes(body!);
    }
  }

  Future<String> decodeBodyString() async {
    if (body == null || body?.isEmpty == true) {
      return "";
    }

    if (_bodyString != null) {
      return _bodyString!;
    }

    List<int> rawBody = body!;
    if (headers.contentEncoding == 'zstd') {
      rawBody = await zstdDecode(body!) ?? [];
      if (charset == 'utf-8' || charset == 'utf8') {
        _bodyString = utf8.decode(rawBody);
      } else {
        _bodyString = String.fromCharCodes(rawBody);
      }
      return _bodyString!;
    }

    return getBodyString();
  }

  List<String> get cookies => headers.cookies;

  List<WebSocketFrame> messages = [];
}

///HTTP请求。
class HttpRequest extends HttpMessage {
  String _uri;
  HttpMethod method;

  HostAndPort? hostAndPort;
  DateTime requestTime = DateTime.now(); //请求时间
  HttpResponse? response;
  Map<String, dynamic> attributes = {};
  ProcessInfo? processInfo;

  String get uri => _uri;

  set uri(String uri) {
    _uri = uri;
    _requestUri = null;
  }

  HttpRequest(this.method, this._uri, {String protocolVersion = "HTTP/1.1"}) : super(protocolVersion);

  String? remoteDomain() {
    if (hostAndPort == null && HostAndPort.startsWithScheme(uri)) {
      try {
        var uri = Uri.parse(this.uri);
        return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      } catch (e) {
        return null;
      }
    }

    return hostAndPort?.domain;
  }

  String get requestUrl {
    if (HostAndPort.startsWithScheme(uri)) {
      return uri;
    }

    if (method == HttpMethod.connect) {
      return "${hostAndPort?.scheme ?? 'http://'}$uri";
    }

    return '${remoteDomain()}$uri';
  }

  /// 请求的uri
  Uri? _requestUri;

  Uri? get requestUri {
    try {
      _requestUri ??= Uri.parse(requestUrl);
      return _requestUri;
    } catch (e) {
      return null;
    }
  }

  ///域名+路径
  String get domainPath => '${remoteDomain()}$path';

  /// 请求的path
  String get path => requestUri?.path ?? '';

  /// path and query
  String get pathAndQuery => '${requestUri?.path}${requestUri?.hasQuery == true ? '?${requestUri?.query}' : ''}';

  Map<String, String> get queries => requestUri?.queryParameters ?? {};

  ///获取消息体编码
  @override
  String? get charset {
    return super.charset ?? 'utf-8';
  }

  ///复制请求
  HttpRequest copy({String? uri}) {
    var request = HttpRequest(method, uri ?? this.uri, protocolVersion: protocolVersion);
    request.headers.addAll(headers);
    if (uri != null && !uri.startsWith('/')) {
      request.hostAndPort = HostAndPort.of(uri);
    }
    request.hostAndPort ??= hostAndPort;
    request.streamId = streamId;
    request.body = body;
    return request;
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      '_class': 'HttpRequest',
      'uri': requestUrl,
      'method': method.name,
      'protocolVersion': protocolVersion,
      'packageSize': packageSize,
      'headers': headers.toJson(),
      'body': body == null ? null : String.fromCharCodes(body!),
      'requestTime': requestTime.millisecondsSinceEpoch,
    };
  }

  factory HttpRequest.fromJson(Map<String, dynamic> json) {
    var request = HttpRequest(HttpMethod.valueOf(json['method']), json['uri'],
        protocolVersion: json['protocolVersion'] ?? "HTTP/1.1");
    
    request.headers.addAll(HttpHeaders.fromJson(json['headers']));
    request.body = json['body']?.toString().codeUnits;
    if (json['requestTime'] != null) {
      request.requestTime = DateTime.fromMillisecondsSinceEpoch(json['requestTime']);
    }
    request.packageSize = json['packageSize'];
    return request;
  }

  @override
  String toString() {
    return 'HttpRequest{version: $protocolVersion, uri: $uri, method: ${method.name}, headers: $headers, contentLength: $contentLength, bodyLength: ${body?.length}}';
  }
}

///HTTP响应。
class HttpResponse extends HttpMessage {
  HttpStatus status;
  DateTime responseTime = DateTime.now();
  HttpRequest? request;

  HttpResponse(this.status, {String protocolVersion = "HTTP/1.1"}) : super(protocolVersion);

  String costTime() {
    if (request == null) {
      return '';
    }
    var cost = responseTime.difference(request!.requestTime).inMilliseconds;
    if (cost > 1000) {
      return '${(cost / 1000).toStringAsFixed(2)}s';
    }
    return '${cost}ms';
  }

  //json序列化
  factory HttpResponse.fromJson(Map<String, dynamic> json) {
    var httpResponse = HttpResponse(HttpStatus(json['status']['code'], json['status']['reasonPhrase']),
        protocolVersion: json['protocolVersion'])
      ..headers.addAll(HttpHeaders.fromJson(json['headers']))
      ..body = json['body']?.toString().codeUnits;
    if (json['responseTime'] != null) {
      httpResponse.responseTime = DateTime.fromMillisecondsSinceEpoch(json['responseTime']);
    }
    httpResponse.packageSize = json['packageSize'];
    return httpResponse;
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      '_class': 'HttpResponse',
      'protocolVersion': protocolVersion,
      'packageSize': packageSize,
      'status': {
        'code': status.code,
        'reasonPhrase': status.reasonPhrase,
      },
      'headers': headers.toJson(),
      'body': body == null ? null : String.fromCharCodes(body!),
      'responseTime': responseTime.millisecondsSinceEpoch,
    };
  }

  @override
  String toString() {
    return 'HttpResponse{status: ${status.code}, protocolVersion: $protocolVersion headers: $headers, contentLength: $contentLength, bodyLength: ${body?.length}}';
  }
}

///HTTP请求方法。
enum HttpMethod {
  get("GET"),
  post("POST"),
  put("PUT"),
  patch("PATCH"),
  delete("DELETE"),
  options("OPTIONS"),
  head("HEAD"),
  trace("TRACE"),
  connect("CONNECT"),
  propfind("PROPFIND"),
  report("REPORT"),
  ;

  final String name;

  const HttpMethod(this.name);

  static HttpMethod valueOf(String name) {
    try {
      return HttpMethod.values.firstWhere((element) => element.name == name.toUpperCase());
    } catch (error) {
      logger.e("HttpMethod error $name :$error");
      rethrow;
    }
  }

  static List<HttpMethod> methods() {
    return values.where((method) => method != HttpMethod.propfind && method != HttpMethod.report).toList();
  }
}

///HTTP响应状态。
class HttpStatus {
  /// 200 OK
  static final HttpStatus ok = newStatus(200, "OK");

  /// 400 Bad Request
  static final HttpStatus badRequest = newStatus(400, "Bad Request");

  /// 401 Unauthorized
  static final HttpStatus unauthorized = newStatus(401, "Unauthorized");

  /// 403 Forbidden
  static final HttpStatus forbidden = newStatus(403, "Forbidden");

  /// 404 Not Found
  static final HttpStatus notFound = newStatus(404, "Not Found");

  /// 500 Internal Server Error
  static final HttpStatus internalServerError = newStatus(500, "Internal Server Error");

  /// 502 Bad Gateway
  static final HttpStatus badGateway = newStatus(502, "Bad Gateway");

  /// 503 Service Unavailable
  static final HttpStatus serviceUnavailable = newStatus(503, "Service Unavailable");

  /// 504 Gateway Timeout
  static final HttpStatus gatewayTimeout = newStatus(504, "Gateway Timeout");

  static HttpStatus newStatus(int statusCode, String? reasonPhrase) {
    if (reasonPhrase == null) {
      return HttpStatus.valueOf(statusCode);
    }

    return HttpStatus(statusCode, reasonPhrase);
  }

  static HttpStatus valueOf(int code) {
    switch (code) {
      case 200:
        return ok;
      case 400:
        return badRequest;
      case 401:
        return unauthorized;
      case 403:
        return forbidden;
      case 404:
        return notFound;
      case 500:
        return internalServerError;
      case 502:
        return badGateway;
      case 503:
        return serviceUnavailable;
      case 504:
        return gatewayTimeout;
    }
    return HttpStatus(code, "");
  }

  final int code;
  String reasonPhrase;

  HttpStatus reason(String reasonPhrase) {
    this.reasonPhrase = reasonPhrase;
    return this;
  }

  HttpStatus(this.code, this.reasonPhrase);

  bool isSuccessful() {
    return code >= 200 && code < 300;
  }

  @override
  String toString() {
    return '$code  $reasonPhrase';
  }
}
