import 'package:proxypin/network/http/http.dart';

/// A Interceptor that can intercept and modify the request and response.
/// @author Hongen Wang
abstract class Interceptor {

  /// Called before the request is sent to the server.
  HttpRequest? onRequest(HttpRequest request);

  /// Called after the response is received from the server.
  HttpResponse? onResponse(HttpRequest request, HttpResponse response);
}
