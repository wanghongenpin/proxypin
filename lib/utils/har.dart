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

import 'package:proxypin/network/host_port.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/util/process_info.dart';

class Har {
  static int maxBodyLength = 1024 * 1024 * 4;

  static List<Map> _entries(List<HttpRequest> list) {
    return list.map((e) => toHar(e)).toList();
  }

  static Map toHar(HttpRequest request) {
    bool isImage = request.response?.contentType == ContentType.image;
    Map har = {
      "startedDateTime": request.requestTime.toUtc().toIso8601String(), // 请求发出的时间(ISO 8601)
      "time": request.response?.responseTime.difference(request.requestTime).inMilliseconds,
      "pageref": "ProxyPin", // 页面标识
      "_id": request.requestId, // 页面标识
      '_app': request.processInfo?.toJson(),
      "request": {
        "method": request.method.name, // 请求方法
        "url": request.requestUrl, // 请求地址
        "httpVersion": request.protocolVersion, // HTTP协议版本
        "cookies": [], // 请求携带的cookie
        "headers": _headers(request), // 请求头
        "queryString": _getQueryString(request), // 请求参数
        "postData": _getPostData(request), // 请求体
        "headersSize": -1, // 请求头大小
        "bodySize": request.body?.length ?? -1, // 请求体大小
      },
      "cache": {},
      'timings': {
        'send': 0,
        'wait': request.response?.responseTime.difference(request.requestTime).inMilliseconds,
        'receive': 0,
      },
      'serverIPAddress': request.response?.remoteHost ?? '', // 服务器IP地址
    };

    har['response'] = {
      "status": request.response?.status.code ?? 0, // 响应状态码
      "statusText": request.response?.status.reasonPhrase ?? '', // 响应状态码描述
      "httpVersion": request.response?.protocolVersion ?? 'HTTP/1.1', // HTTP协议版本
      "cookies": [], // 响应携带的cookie
      "headers": _headers(request.response), // 响应头
      "content": {
        "size": isImage ? 0 : request.response?.body?.length ?? -1, // 响应体大小
        "mimeType": _getContentType(request.response?.headers.contentType), // 响应体类型
        "text": isImage ? '' : request.response?.bodyAsString, // 响应体内容
      },
      "redirectURL": '', // 重定向地址
      "headersSize": -1, // 响应头大小
      "bodySize": isImage ? -1 : request.response?.body?.length ?? -1, // 响应体大小
    };
    return har;
  }

  static Future<String> writeJson(List<HttpRequest> list, {String title = ''}) async {
    var entries = _entries(list);
    Map har = {};
    title = title.contains("ProxyPin") ? title : "[ProxyPin]$title";
    har["log"] = {
      "version": "1.2",
      "creator": {"name": "ProxyPin", "version": "1.1.7"},
      "pages": [
        {
          "title": title,
          "id": "ProxyPin",
          "startedDateTime": list.firstOrNull?.requestTime.toUtc().toIso8601String(),
          "pageTimings": {"onContentLoad": -1, "onLoad": -1}
        }
      ],
      "entries": entries,
    };
    return jsonEncode(har);
  }

  static Future<File> writeFile(List<HttpRequest> list, File file, {String title = ''}) async {
    var json = await writeJson(list, title: title);
    return file.writeAsString(json);
  }

  //读取文件
  static Future<List<HttpRequest>> readFile(File file) async {
    var lines = await file.readAsLines();
    List<HttpRequest> list = [];

    for (var value in lines) {
      var har = jsonDecode(value.substring(0, value.length - 1));
      var request = toRequest(har);
      list.add(request);
    }
    return list;
  }

  static List<Map> _headers(HttpMessage? message) {
    var headers = <Map<String, String>>[];
    var contentEncodingName = message?.headers.getOriginalName(HttpHeaders.CONTENT_ENCODING);

    message?.headers.forEach((name, values) {
      for (var element in values) {
        //body已经解码 删除编码
        if (name == contentEncodingName && element == 'br') {
          continue;
        }
        headers.add({'name': name, 'value': element});
      }
    });
    return headers;
  }

  /// har to request
  static HttpRequest toRequest(Map har) {
    var request = har['request'];
    var method = request['method'];
    List headers = request['headers'];

    var httpRequest = HttpRequest(HttpMethod.valueOf(method), request['url'], protocolVersion: request['httpVersion']);
    if (har.containsKey("_id")) httpRequest.requestId = har['_id']; // 页面标识
    httpRequest.processInfo = har['_app'] == null ? null : ProcessInfo.fromJson(har['_app']);
    httpRequest.body = request['postData']?['text']?.toString().codeUnits;
    for (var element in headers) {
      httpRequest.headers.add(element['name'], element['value']);
    }
    var response = har['response'];
    HttpResponse? httpResponse;
    if (response != null && response['status'] != null) {
      httpResponse = HttpResponse(HttpStatus.newStatus(response['status'], response['statusText']),
          protocolVersion: response['httpVersion']);
      httpResponse.body = response['content']['text']?.toString().codeUnits;
      List responseHeaders = response['headers'];
      for (var element in responseHeaders) {
        httpResponse.headers.add(element['name'], element['value']);
      }
    }

    httpRequest.response = httpResponse;
    httpResponse?.request = httpRequest;
    httpRequest.hostAndPort = HostAndPort.of(httpRequest.requestUrl);
    httpResponse?.remoteHost = har['serverIPAddress']; // 服务器IP地址

    //请求时间
    if (har['startedDateTime'] != null) {
      httpRequest.requestTime = DateTime.parse(har['startedDateTime']).toLocal();
    }
    if (har['time'] != null) {
      httpRequest.response?.responseTime =
          httpRequest.requestTime.add(Duration(milliseconds: double.parse(har['time'].toString()).toInt()));
    }
    return httpRequest;
  }

  static List<Map<String, String>> _getQueryString(HttpRequest request) {
    final queryStringList = <Map<String, String>>[];
    final queries = request.requestUri?.queryParametersAll;
    queries?.forEach((key, valueList) {
      for (var value in valueList) {
        queryStringList.add({"name": key, "value": value});
      }
    });
    return queryStringList;
  }

  static Map<String, dynamic> _getPostData(HttpRequest request) {
    if (request.contentType == ContentType.formData || request.contentType == ContentType.formUrl) {
      return {
        "mimeType": request.headers.contentType, // 请求体类型
        "text": request.bodyAsString, // 请求体内容
        "params": [], // 请求体内容
      };
    }
    return {
      "mimeType": request.headers.contentType, // 请求体类型
      "text": request.bodyAsString, // 请求体内容
    };
  }

  //获取contentType
  static String? _getContentType(String? type) {
    if (type == null) {
      return '';
    }
    var indexOf = type.indexOf("charset=");
    if (indexOf == -1) {
      return type;
    }
    var contentType = type.substring(0, indexOf).trimRight();
    if (contentType.endsWith(";")) {
      return contentType.substring(0, contentType.length - 1);
    }
    return contentType;
  }
}
