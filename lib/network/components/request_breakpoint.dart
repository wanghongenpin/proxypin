import 'package:proxypin/network/components/interceptor.dart';
import 'package:proxypin/network/components/manager/request_breakpoint_manager.dart';
import 'package:proxypin/network/http/http.dart';

class RequestBreakpointInterceptor extends Interceptor {
  static RequestBreakpointInterceptor instance = RequestBreakpointInterceptor._();

  final manager = RequestBreakpointManager.instance;

  RequestBreakpointInterceptor._();

  @override
  Future<HttpRequest?> onRequest(HttpRequest request) async {
    RequestBreakpointManager requestBreakpointManager = await manager;
    if (!requestBreakpointManager.enabled) return request;

    var url = request.requestUrl;
    for (var rule in requestBreakpointManager.list) {
      if (rule.match(url, method: request.method) && rule.interceptRequest) {
        // TODO: Breakpoint logic here (suspend request)
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
        // TODO: Breakpoint logic here (suspend response)
      }
    }
    return response;
  }
}

