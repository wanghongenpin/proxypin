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
import 'package:proxypin/network/components/manager/environment_manager.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/http/constants.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/util/file_read.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/uri.dart';
import 'package:proxypin/utils/lang.dart';

import 'manager/rewrite_rule.dart';

///  RequestRewriteComponent is a component that can rewrite the request before sending it to the server.
/// @author Hongen Wang
class RequestRewriteInterceptor extends Interceptor {
  static RequestRewriteInterceptor instance = RequestRewriteInterceptor._();

  final requestRewriteManager = RequestRewriteManager.instance;

  RequestRewriteInterceptor._();

  /// 构造 RegExp；若未启用正则则自动转义为字面量匹配，若 pattern 不合法则回退为字面量匹配
  static RegExp _toRegExp(String pattern, {bool useRegex = true, bool caseSensitive = true}) {
    if (!useRegex) {
      return RegExp(RegExp.escape(pattern), caseSensitive: caseSensitive);
    }
    try {
      return RegExp(pattern, caseSensitive: caseSensitive);
    } catch (_) {
      return RegExp(RegExp.escape(pattern), caseSensitive: caseSensitive);
    }
  }

  /// 用环境变量渲染 {{name}}。若 EnvironmentManager 未加载或未启用,返回原字符串。
  /// 注意:只对写入请求/响应的字段渲染,key(匹配正则)不做变量替换,避免正则元字符与变量语法混淆。
  static String? _renderEnv(String? input) {
    if (input == null || input.isEmpty || !input.contains('{{')) return input;
    final mgr = EnvironmentManager.instanceOrNull;
    if (mgr == null || !mgr.enabled) return input;
    return mgr.render(input);
  }

  /// 生成一个副本,其中所有会输出到请求/响应的字段(value/redirectUrl/body/headers/path/queryParam)已做变量渲染。
  /// 原始配置不修改。
  static RewriteItem _renderItem(RewriteItem item) {
    if (EnvironmentManager.instanceOrNull?.enabled != true) return item;
    // 快速判断:所有相关字符串字段都不含 `{{` 时直接返回原对象,避免拷贝开销
    bool hasToken(dynamic v) => v is String && v.contains('{{');
    final values = item.values;
    if (!hasToken(values['value']) &&
        !hasToken(values['redirectUrl']) &&
        !hasToken(values['body']) &&
        !hasToken(values['path']) &&
        !hasToken(values['queryParam']) &&
        !(values['headers'] is Map && (values['headers'] as Map).values.any(hasToken))) {
      return item;
    }
    final copy = RewriteItem(item.type, item.enabled, values: Map.of(values));
    copy.value = _renderEnv(copy.value);
    copy.redirectUrl = _renderEnv(copy.redirectUrl);
    copy.body = _renderEnv(copy.body);
    copy.path = _renderEnv(copy.path);
    copy.queryParam = _renderEnv(copy.queryParam);
    final headers = copy.headers;
    if (headers != null) {
      copy.headers = headers.map((k, v) => MapEntry(k, _renderEnv(v) ?? v));
    }
    return copy;
  }

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
    // 先做通配符替换(基于模板中的字面 `*`),再做环境变量渲染;
    // 顺序反过来会把变量值中的 `*` 也当成通配符替换,破坏 URL。
    if (rewriteRule.url.contains("*") && redirectUrl?.contains("*") == true) {
      String ruleUrl = rewriteRule.url.replaceAll("*", "");
      redirectUrl = redirectUrl?.replaceAll("*", url!.replaceAll(ruleUrl, ""));
    }
    redirectUrl = _renderEnv(redirectUrl);
    return redirectUrl;
  }

  /// 重写请求
  Future<void> requestRewrite(String url, HttpRequest request) async {
    var manager = await RequestRewriteManager.instance;
    var rewriteRule = manager.getRewriteRule(url, [RuleType.requestReplace, RuleType.requestUpdate]);

    if (rewriteRule?.type == RuleType.requestReplace) {
      var rewriteItems = await manager.getRewriteItems(rewriteRule!);
      if (rewriteItems == null) {
        return;
      }
      for (var item in rewriteItems) {
        if (item.enabled) {
          await _replaceRequest(request, _renderItem(item));
        }
      }
    }

    if (rewriteRule?.type == RuleType.requestUpdate) {
      var rewriteItems = await manager.getRewriteItems(rewriteRule!);
      if (rewriteItems == null) {
        return;
      }
      for (var item in rewriteItems) {
        if (item.enabled) {
          await _updateRequest(request, _renderItem(item));
        }
      }
    }
  }

  /// 重写响应
  Future<bool> responseRewrite(String? url, HttpResponse response) async {
    var manager = await RequestRewriteManager.instance;

    var rewriteRule = manager.getRewriteRule(url, [RuleType.responseReplace, RuleType.responseUpdate]);
    if (rewriteRule == null) {
      return false;
    }

    if (rewriteRule.type == RuleType.responseReplace) {
      var rewriteItems = await manager.getRewriteItems(rewriteRule);
      if (rewriteItems == null) {
        return false;
      }
      for (var item in rewriteItems) {
        if (item.enabled) {
          await _replaceResponse(response, _renderItem(item));
        }
      }
      return true;
    }

    if (rewriteRule.type == RuleType.responseUpdate) {
      var rewriteItems = await manager.getRewriteItems(rewriteRule);
      if (rewriteItems == null) {
        return false;
      }

      for (var item in rewriteItems) {
        if (item.enabled) {
          await _updateMessage(response, _renderItem(item));
        }
      }
      return true;
    }

    return false;
  }

  Future<void> _updateRequest(HttpRequest request, RewriteItem item) async {
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
            if (val == null || !_toRegExp(item.value!, useRegex: item.useRegex).hasMatch(val)) {
              break;
            }
          }
          queryParameters.remove(item.key!);
          break;
        case RewriteType.updateQueryParam:
          var itemKey = item.key;
          if (itemKey == null || itemKey.trim().isEmpty) return;

          var entries = Map.of(queryParameters).entries;
          var regExp = _toRegExp(item.key!, useRegex: item.useRegex);

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
      requestUri = requestUri.replace(query: UriUtils.mapToQuery(queryParameters));
      if (requestUri.isScheme('https')) {
        request.uri = requestUri.path + (requestUri.hasQuery ? "?${requestUri.query}" : "");
      } else {
        request.uri = requestUri.toString();
      }
      return;
    }

    await _updateMessage(request, item);
  }

  //修改消息
  Future<void> _updateMessage(HttpMessage message, RewriteItem item) async {
    if (item.type == RewriteType.updateBody && message.body != null) {
      String body = (await message.decodeBodyString()).replaceAllMapped(_toRegExp(item.key!, useRegex: item.useRegex), (match) {
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
        if (val == null || !_toRegExp(item.value!, useRegex: item.useRegex).hasMatch(val)) {
          return;
        }
      }
      message.headers.remove(item.key!);
      return;
    }

    if (item.type == RewriteType.updateHeader) {
      if (item.key == null || item.key?.trim().isEmpty == true) return;

      var headers = Map.of(message.headers.getHeaders());
      var regExp = _toRegExp(item.key!, useRegex: item.useRegex, caseSensitive: false);

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
        message.headers.remove(HttpHeaders.CONTENT_ENCODING);
        return;
      }

      if (item.body != null) {
        message.body =
            message.charset == 'utf-8' || message.charset == 'utf8' ? utf8.encode(item.body!) : item.body?.codeUnits;
        message.headers.contentLength = message.body!.length;
        message.headers.remove(HttpHeaders.CONTENT_ENCODING);
      }
      return;
    }
  }
}
