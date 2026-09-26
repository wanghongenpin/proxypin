import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/network.dart';
import 'package:proxypin/network/handle/http_proxy_handle.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/byte_buf.dart';

/// Reproduction for issue #844: proxy records 200 but the client times out
/// when the origin responds WITHOUT Content-Length and WITHOUT
/// Transfer-Encoding (close-delimited body) while keeping the connection
/// alive.
void main() {
  const int proxyPort = 19098;
  const int originPort = 18081;
  const String body = 'hello-close-delimited-body-0123456789';

  late Server proxy;
  late ServerSocket origin;

  setUpAll(() async {
    // Origin: 200 with NO Content-Length, NO Transfer-Encoding.
    // Body is close-delimited: respond, then close the connection.
    origin = await ServerSocket.bind(InternetAddress.loopbackIPv4, originPort);
    origin.listen((socket) {
      final resp = 'HTTP/1.1 200 OK\r\n'
          'Content-Type: text/plain\r\n'
          '\r\n'
          '$body';
      socket.listen((_) {}, onError: (_) {}, cancelOnError: true);
      () async {
        try {
          socket.add(utf8.encode(resp));
          await socket.flush();
          await socket.close();
        } catch (_) {}
      }();
    });

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
        HttpProxyChannelHandler(listener: null, interceptors: []),
      );
    });
    await proxy.bind(proxyPort);
  });

  tearDownAll(() async {
    await proxy.stop();
    await origin.close();
  });

  test('no-CL / no-chunked response must not hang the client (issue #844)', () async {
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
        '\r\n');
    await socket.flush();

    // Client follows HTTP/1.1 semantics for a response without CL/chunked:
    // it treats the body as complete only when the connection closes. The
    // proxy must deliver the body and propagate the upstream close.
    final data = await completer.future.timeout(const Duration(seconds: 5));
    socket.destroy();
    final text = utf8.decode(data, allowMalformed: true);
    // ignore: avoid_print
    print('client received ${text.length} bytes');
    expect(text.contains('200'), isTrue);
    expect(text.contains(body), isTrue, reason: 'client must receive the close-delimited body');
  });

  test('CONNECT response is parsed, not close-delimited-relayed', () {
    // Upstream proxy replies "200 Connection established" with no
    // Content-Length. That must keep going through the existing CONNECT
    // handling (HttpResponseProxyHandler direct write) instead of being
    // diverted to raw relay, or the TLS MITM tunnel is taken over.
    final codec = HttpClientCodec();
    final ctx = ChannelContext()
      ..currentRequest = HttpRequest(HttpMethod.connect, 'example.com:443');
    final buf = ByteBuf(utf8.encode('HTTP/1.1 200 Connection established\r\n\r\n'));

    final result = codec.decode(ctx, buf);
    expect(result.supportedParse, isTrue,
        reason: 'CONNECT response must not be treated as close-delimited');
    expect(result.isDone, isTrue);
    expect(result.data?.status.code, 200);
  });
}