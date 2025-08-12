import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';

/// A Interceptor that can intercept and modify the request and response.
/// @author Hongen Wang
abstract class Interceptor {
  /// The priority of the interceptor.
  int get priority => 0;

  Future<HostAndPort> preConnect(HostAndPort hostAndPort) async {
    return hostAndPort;
  }

  /// Called before the request is sent to the server.
  Future<HttpResponse?> execute(HttpRequest request) async {
    return null;
  }

  /// Called before the request is sent to the server.
  Future<HttpRequest?> onRequest(HttpRequest request) async {
    return request;
  }

  /// Called after the response is received from the server.
  Future<HttpResponse?> onResponse(HttpRequest request, HttpResponse response) async {
    return response;
  }
}
