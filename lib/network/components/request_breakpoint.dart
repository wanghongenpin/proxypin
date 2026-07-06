import 'dart:async';
import 'dart:convert';

import 'package:proxypin/network/components/interceptor.dart';
import 'package:proxypin/network/components/manager/environment_manager.dart';
import 'package:proxypin/network/components/manager/request_breakpoint_manager.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/cache.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/multi_window.dart';

import '../http/http_headers.dart';

class RequestBreakpointInterceptor extends Interceptor {
  static RequestBreakpointInterceptor instance = RequestBreakpointInterceptor._();

  final manager = RequestBreakpointManager.instance;

  final ExpiringCache<String, Completer<HttpRequest?>> _pausedRequests = ExpiringCache(Duration(minutes: 10));
  final ExpiringCache<String, Completer<HttpResponse?>> _pausedResponses = ExpiringCache(Duration(minutes: 10));

  RequestBreakpointInterceptor._();

  /// 用环境变量渲染 {{name}}。若 EnvironmentManager 未加载或未启用,返回原字符串。
  static String? _renderEnv(String? input) => EnvironmentManager.tryRender(input);

  /// 渲染 headers 里所有值中的 {{var}}。多值 header(如 Set-Cookie)每个值独立渲染,不丢值。
  static void _renderHeadersInPlace(HttpHeaders headers) {
    if (EnvironmentManager.instanceOrNull?.enabled != true) return;
    // 先收集需要重写的 (name, renderedList),避免边遍历边改
    final rewrites = <String, List<String>>{};
    headers.forEach((name, values) {
      if (!values.any((v) => v.contains('{{'))) return;
      rewrites[name] = values.map((v) => _renderEnv(v) ?? v).toList();
    });
    // 用 remove + add 重建每个多值列表,保留全部值
    rewrites.forEach((name, values) {
      headers.remove(name);
      for (final v in values) {
        headers.add(name, v);
      }
    });
  }

  /// 渲染 body 里的 {{var}}。仅在 body 看起来是"较小的文本"时才尝试解码替换,
  /// 二进制/大 body/无变量占位时保持原字节不动,避免破坏和无谓的 decode 开销。
  static const int _renderBodyMaxSize = 512 * 1024; // 512KB 以上跳过

  /// 已知的二进制/非文本 MIME 前缀,遇到直接跳过 render
  static const List<String> _binaryContentTypes = [
    'image/',
    'video/',
    'audio/',
    'application/octet-stream',
    'application/zip',
    'application/x-protobuf',
    'application/x-msgpack',
    'application/pdf',
    'font/',
  ];

  static bool _looksBinary(String? contentType) {
    if (contentType == null || contentType.isEmpty) return false;
    final ct = contentType.toLowerCase();
    return _binaryContentTypes.any(ct.startsWith);
  }

  static List<int>? _renderBody(List<int>? body, String? charset, {String? contentType}) {
    if (body == null || body.isEmpty) return body;
    if (EnvironmentManager.instanceOrNull?.enabled != true) return body;
    if (body.length > _renderBodyMaxSize) return body;
    if (_looksBinary(contentType)) return body;
    try {
      final text = (charset == 'utf-8' || charset == 'utf8' || charset == null)
          ? utf8.decode(body)
          : String.fromCharCodes(body);
      if (!text.contains('{{')) return body;
      final rendered = _renderEnv(text) ?? text;
      return (charset == 'utf-8' || charset == 'utf8' || charset == null)
          ? utf8.encode(rendered)
          : rendered.codeUnits;
    } catch (_) {
      return body; // 非法文本,原样返回
    }
  }

  @override
  Future<HttpRequest?> onRequest(HttpRequest request) async {
    RequestBreakpointManager requestBreakpointManager = await manager;
    if (!requestBreakpointManager.enabled) return request;

    var url = request.requestUrl;
    for (var rule in requestBreakpointManager.list) {
      if (rule.match(url, method: request.method) && rule.interceptRequest) {
        Completer<HttpRequest?> completer = Completer();
        _pausedRequests[request.requestId] = completer;

        // Open Breakpoint Executor Window
        MultiWindow.openWindow("Breakpoint - Request", 'BreakpointExecutor',
            args: {'type': 'request', 'request': request.toJson(), 'requestId': request.requestId});

        return completer.future.then((req) {
          if (req == null) {
            logger.d('Request ${request.requestId} was resumed null, aborting request');
            return null;
          }

          request.method = req.method;
          // 先渲染 URI 中的 {{var}}(如 host / path / query 里可能用到)
          final renderedUri = _renderEnv(req.uri) ?? req.uri;
          Uri uri = Uri.parse(renderedUri);
          if (uri.isScheme('https')) {
            request.uri = uri.path + (uri.hasQuery ? "?${uri.query}" : "");
          } else {
            request.uri = uri.toString();
          }

          request.headers.clear();
          request.headers.addAll(req.headers);
          _renderHeadersInPlace(request.headers);
          request.headers.remove(HttpHeaders.CONTENT_ENCODING);

          request.body = _renderBody(req.body, request.charset, contentType: request.headers.contentType);
          logger.d('Resuming request ${request.requestId} with modified request');
          return request;
        });
      }
    }
    return request;
  }

  @override
  Future<HttpResponse?> onResponse(HttpRequest request, HttpResponse response) async {
    RequestBreakpointManager requestBreakpointManager = await manager;
    if (!requestBreakpointManager.enabled) return response;

    var url = request.requestUrl;
    for (var rule in requestBreakpointManager.list) {
      if (rule.match(url, method: request.method) && rule.interceptResponse) {
        Completer<HttpResponse?> completer = Completer();
        _pausedResponses[request.requestId] = completer;

        // Open Breakpoint Executor Window
        MultiWindow.openWindow("Breakpoint - Response", 'BreakpointExecutor', args: {
          'type': 'response',
          'request': request.toJson(),
          'response': response.toJson(),
          'requestId': request.requestId
        });

        return completer.future.then((res) {
          if (res == null) {
            return null;
          }

          response.status = res.status;
          response.headers.clear();
          response.headers.addAll(res.headers);
          _renderHeadersInPlace(response.headers);
          response.headers.remove(HttpHeaders.CONTENT_ENCODING);

          response.body = _renderBody(res.body, response.charset, contentType: response.headers.contentType);

          logger.d('Resuming response for request ${request.requestId} with modified response');
          return response;
        });
      }
    }
    return response;
  }

  void resumeRequest(String requestId, HttpRequest? request) {
    if (_pausedRequests.containsKey(requestId)) {
      _pausedRequests.remove(requestId)?.complete(request);
    }
  }

  void resumeResponse(String requestId, HttpResponse? response) {
    if (_pausedResponses.containsKey(requestId)) {
      _pausedResponses.remove(requestId)?.complete(response);
    }
  }
}
