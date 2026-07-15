import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/channel/network.dart';
import 'package:proxypin/network/components/interceptor.dart';
import 'package:proxypin/network/handle/http_proxy_handle.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/http.dart';

/// Mimics the real app's async response processing (UI listener + the 6
/// built-in interceptors each `await`ing) that sits between receiving the
/// server response and writing it back to the client. Without this delay the
/// race window is too small to observe on loopback; the real app always has it.
class _DelayInterceptor extends Interceptor {
  @override
  Future<HttpResponse?> onResponse(HttpRequest request, HttpResponse response) async {
    await Future.delayed(const Duration(milliseconds: 3));
    return response;
  }
}

/// Reproduction for issue #838: plain HTTP requests get "socket hang up" /
/// empty reply when the origin server closes the connection right after
/// responding. The proxy's channelInactive must not close the client
/// connection before the in-flight response has been written back.
void main() {
  const int proxyPort = 19099;
  const int originPort = 18080;
  const String body = '{"ok":true,"data":"hangup-test-payload-0123456789"}';

  late Server proxy;
  late ServerSocket origin;

  setUpAll(() async {
    // Origin server: responds then IMMEDIATELY closes (server-initiated FIN),
    // with a tiny gap between headers and body to widen the race window.
    origin = await ServerSocket.bind(InternetAddress.loopbackIPv4, originPort);
    origin.listen((socket) {
      final headers = 'HTTP/1.1 200 OK\r\n'
          'Content-Type: application/json\r\n'
          'Content-Length: ${body.length}\r\n'
          'Connection: close\r\n'
          '\r\n';
      socket.listen((_) {}, onError: (_) {}, cancelOnError: true);
      () async {
        try {
          socket.add(utf8.encode(headers));
          await Future.delayed(const Duration(milliseconds: 1));
          socket.add(utf8.encode(body));
          await socket.close(); // flush + FIN right after the response
        } catch (_) {}
      }();
    });

    // The proxy core (no GUI, no interceptors, no SSL).
    final config = Configuration.fromJson({
      'enableSsl': false,
      'enableSocks5': false,
      'enableSystemProxy': false,
      'enabledHttp2': false,
    });
    config.port = proxyPort;
    proxy = Server(config);
    proxy.initChannel((channel) {
      channel.dispatcher.handle(
        HttpRequestCodec(),
        HttpResponseCodec(),
        HttpProxyChannelHandler(listener: null, interceptors: [_DelayInterceptor()]),
      );
    });
    await proxy.bind(proxyPort);
  });

  tearDownAll(() async {
    await proxy.stop();
    await origin.close();
  });

  /// Sends one plain-HTTP request through the proxy using a raw socket
  /// (absolute-form request line, as an HTTP proxy client does).
  /// Returns the full raw response text, or throws on hang-up/empty reply.
  Future<String> requestThroughProxy() async {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, proxyPort);
    final completer = Completer<List<int>>();
    final buf = <int>[];
    socket.listen(
      buf.addAll,
      onError: completer.completeError,
      onDone: () => completer.isCompleted ? null : completer.complete(buf),
      cancelOnError: true,
    );

    socket.write('GET http://127.0.0.1:$originPort/test HTTP/1.1\r\n'
        'Host: 127.0.0.1:$originPort\r\n'
        'Accept: */*\r\n'
        '\r\n');
    await socket.flush();

    final data = await completer.future.timeout(const Duration(seconds: 8));
    socket.destroy();
    return utf8.decode(data, allowMalformed: true);
  }

  test('plain HTTP through proxy survives origin immediate-close (issue #838)', () async {
    const attempts = 40;
    int hangups = 0;
    final failures = <String>[];

    for (var i = 0; i < attempts; i++) {
      try {
        final resp = await requestThroughProxy();
        if (!resp.contains('200') || !resp.contains(body)) {
          hangups++;
          failures.add('req$i: incomplete/empty -> ${resp.isEmpty ? "<empty>" : resp.substring(0, resp.length.clamp(0, 60))}');
        }
      } catch (e) {
        hangups++;
        failures.add('req$i: $e');
      }
    }

    // ignore: avoid_print
    print('hangups: $hangups / $attempts');
    for (final f in failures.take(5)) {
      // ignore: avoid_print
      print(f);
    }

    expect(hangups, 0, reason: 'Client saw socket hang up / empty reply on $hangups of $attempts requests');
  });

  test('concurrent requests all complete (pause/resume must not deadlock or drop)', () async {
    const parallel = 30;
    final results = await Future.wait(
      List.generate(parallel, (_) async {
        try {
          final resp = await requestThroughProxy();
          return resp.contains('200') && resp.contains(body);
        } catch (_) {
          return false;
        }
      }),
    );
    final ok = results.where((e) => e).length;
    // ignore: avoid_print
    print('concurrent ok: $ok / $parallel');
    expect(ok, parallel, reason: 'Only $ok of $parallel concurrent requests completed');
  });
}
