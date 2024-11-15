/*
 * Copyright 2024 Hongen Wang All rights reserved.
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

import 'dart:collection';
import 'dart:convert';

import 'package:proxypin/network/components/interceptor.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/http/constants.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/util/file_read.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/utils/lang.dart';

import 'manager/rewrite_rule.dart';

///  RequestRewriteComponent is a component that can rewrite the request before sending it to the server.
/// @author Hongen Wang
class RequestRewriteInterceptor extends Interceptor {
  static RequestRewriteInterceptor instance = RequestRewriteInterceptor._();

  final requestRewriteManager = RequestRewriteManager.instance;

  RequestRewriteInterceptor._();

  @override
  Future<HttpRequest?> onRequest(HttpRequest request) async {
    //重写请求
    var url = request.requestUrl;
    await requestRewrite(url, request);
    return request;
  }

  @override
  Future<HttpResponse?> onResponse(HttpRequest request, HttpResponse response) async {
    //重写响应
    try {
      var url = request.requestUrl;
      await responseRewrite(url, response);
    } catch (e, t) {
      response.body = "$e".codeUnits;
      logger.e('[${request.requestId}] 响应重写异常 ', error: e, stackTrace: t);
    }
    return response;
  }

  ///获取重定向
  Future<String?> getRedirectRule(String? url) async {
    var manager = await requestRewriteManager;
    var rewriteRule = manager.getRewriteRule(url, [RuleType.redirect]);
    if (rewriteRule == null) {
      return null;
    }

    var rewriteItems = await manager.getRewriteItems(rewriteRule);
    var redirectUrl = rewriteItems?.firstWhereOrNull((element) => element.enabled)?.redirectUrl;
    if (rewriteRule.url.contains("*") && redirectUrl?.contains("*") == true) {
      String ruleUrl = rewriteRule.url.replaceAll("*", "");
      redirectUrl = redirectUrl?.replaceAll("*", url!.replaceAll(ruleUrl, ""));
    }
    return redirectUrl;
  }

  /// 重写请求
  Future<void> requestRewrite(String url, HttpRequest request) async {
    var manager = await RequestRewriteManager.instance;
    var rewriteRule = manager.getRewriteRule(url, [RuleType.requestReplace, RuleType.requestUpdate]);

    if (rewriteRule?.type == RuleType.requestReplace) {
      var rewriteItems = await manager.getRewriteItems(rewriteRule!);
      for (var item in rewriteItems!) {
        if (item.enabled) {
          await _replaceRequest(request, item);
        }
      }
    }

    if (rewriteRule?.type == RuleType.requestUpdate) {
      var rewriteItems = await manager.getRewriteItems(rewriteRule!);
      rewriteItems?.where((item) => item.enabled).forEach((item) => _updateRequest(request, item));
    }
  }

  /// 重写响应
  Future<void> responseRewrite(String? url, HttpResponse response) async {
    var manager = await RequestRewriteManager.instance;

    var rewriteRule = manager.getRewriteRule(url, [RuleType.responseReplace, RuleType.responseUpdate]);
    if (rewriteRule == null) {
      return;
    }

    if (rewriteRule.type == RuleType.responseReplace) {
      var rewriteItems = await manager.getRewriteItems(rewriteRule);
      for (var item in rewriteItems!) {
        if (item.enabled) {
          await _replaceResponse(response, item);
        }
      }
    }

    if (rewriteRule.type == RuleType.responseUpdate) {
      var rewriteItems = await manager.getRewriteItems(rewriteRule);
      rewriteItems?.where((item) => item.enabled).forEach((item) => _updateMessage(response, item));
    }
  }

  _updateRequest(HttpRequest request, RewriteItem item) {
    var paramTypes = [RewriteType.addQueryParam, RewriteType.removeQueryParam, RewriteType.updateQueryParam];

    if (paramTypes.contains(item.type)) {
      var requestUri = request.requestUri;
      Map<String, dynamic> queryParameters = LinkedHashMap.from(requestUri!.queryParameters);

      switch (item.type) {
        case RewriteType.addQueryParam:
          queryParameters[item.key!] = item.value;
          break;
        case RewriteType.removeQueryParam:
          if (item.value?.trim().isNotEmpty == true) {
            var val = queryParameters[item.key!];
            if (val == null || !RegExp(item.value!).hasMatch(val)) {
              break;
            }
          }
          queryParameters.remove(item.key!);
          break;
        case RewriteType.updateQueryParam:
          var itemKey = item.key;
          if (itemKey == null || itemKey.trim().isEmpty) return;

          var entries = Map.of(queryParameters).entries;
          var regExp = RegExp(item.key!);

          for (var entry in entries) {
            var line = "${entry.key}=${entry.value}";

            if (regExp.hasMatch(line)) {
              line = line.replaceAll(regExp, item.value ?? '');
              var pair = line.splitFirst(HttpConstants.equal);
              if (pair.first != entry.key) queryParameters.remove(entry.key);

              queryParameters[pair.first] = pair.length > 1 ? pair.last : '';
              break;
            }
          }
          break;
        default:
          break;
      }
      requestUri = requestUri.replace(queryParameters: queryParameters);

      if (requestUri.isScheme('https')) {
        request.uri = requestUri.path + (requestUri.hasQuery ? "?${requestUri.query}" : "");
      } else {
        request.uri = requestUri.toString();
      }
      return;
    }

    _updateMessage(request, item);
  }

  //修改消息
  _updateMessage(HttpMessage message, RewriteItem item) {
    if (item.type == RewriteType.updateBody && message.body != null) {
      String body = message.getBodyString().replaceAllMapped(RegExp(item.key!), (match) {
        if (match.groupCount > 0 && item.value?.contains("\$1") == true) {
          return item.value!.replaceAll("\$1", match.group(1)!);
        }
        return item.value ?? '';
      });

      message.body = message.charset == 'utf-8' || message.charset == 'utf8' ? utf8.encode(body) : body.codeUnits;

      message.headers.remove(HttpHeaders.CONTENT_ENCODING);
      message.headers.contentLength = message.body!.length;
      return;
    }

    if (item.type == RewriteType.addHeader) {
      message.headers.set(item.key!, item.value ?? '');
      return;
    }

    if (item.type == RewriteType.removeHeader) {
      if (item.value?.trim().isNotEmpty == true) {
        var val = message.headers.get(item.key!);
        if (val == null || !RegExp(item.value!).hasMatch(val)) {
          return;
        }
      }
      message.headers.remove(item.key!);
      return;
    }

    if (item.type == RewriteType.updateHeader) {
      if (item.key == null || item.key?.trim().isEmpty == true) return;

      var headers = Map.of(message.headers.getHeaders());
      var regExp = RegExp(item.key!, caseSensitive: false);

      headers.forEach((key, values) {
        var line = "$key: ${values.firstOrNull ?? ''}";
        if (regExp.hasMatch(line)) {
          line = line.replaceAll(regExp, item.value ?? '');
          var pair = line.splitFirst(HttpConstants.colon);
          if (pair.first != key) message.headers.remove(key);
          message.headers.set(pair.first, pair.length > 1 ? pair.last : '');
        }
      });
      return;
    }
  }

  //替换请求
  Future<void> _replaceRequest(HttpRequest request, RewriteItem item) async {
    if (item.type == RewriteType.replaceRequestLine) {
      request.method = item.method ?? request.method;
      Uri uri = Uri.parse(request.requestUrl).replace(path: item.path, query: item.queryParam);
      if (uri.isScheme('https')) {
        request.uri = uri.path + (uri.hasQuery ? "?${uri.query}" : "");
      } else {
        request.uri = uri.toString();
      }
      return;
    }
    await _replaceHttpMessage(request, item);
  }

  //替换相应
  Future<void> _replaceResponse(HttpResponse response, RewriteItem item) async {
    if (item.type == RewriteType.replaceResponseStatus && item.statusCode != null) {
      response.status = HttpStatus.valueOf(item.statusCode!);
      return;
    }
    await _replaceHttpMessage(response, item);
  }

  Future<void> _replaceHttpMessage(HttpMessage message, RewriteItem item) async {
    if ((item.type == RewriteType.replaceRequestHeader || item.type == RewriteType.replaceResponseHeader) &&
        item.headers != null) {
      item.headers?.forEach((key, value) => message.headers.set(key, value));
      return;
    }

    if (item.type == RewriteType.replaceResponseBody || item.type == RewriteType.replaceRequestBody) {
      if (item.bodyType == ReplaceBodyType.file.name) {
        if (item.bodyFile == null) return;

        message.body = await FileRead.readFile(item.bodyFile!);
        message.headers.contentLength = message.body!.length;
        return;
      }

      if (item.body != null) {
        message.body =
            message.charset == 'utf-8' || message.charset == 'utf8' ? utf8.encode(item.body!) : item.body?.codeUnits;
        message.headers.contentLength = message.body!.length;
      }
      return;
    }
  }
}
