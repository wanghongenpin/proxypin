import 'dart:async';

import 'package:proxypin/network/components/interceptor.dart';
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
          Uri uri = req.requestUri!;
          if (uri.isScheme('https')) {
            request.uri = uri.path + (uri.hasQuery ? "?${uri.query}" : "");
          } else {
            request.uri = uri.toString();
          }

          request.headers.clear();
          request.headers.addAll(req.headers);
          request.headers.remove(HttpHeaders.CONTENT_ENCODING);

          request.body = req.body;
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
          response.headers.remove(HttpHeaders.CONTENT_ENCODING);

          response.body = res.body;

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
