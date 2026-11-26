import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/channel/network.dart';
import 'package:proxypin/network/handle/http_proxy_handle.dart';
import 'package:proxypin/network/http/codec.dart';

/// Regression for issue #1014 / #674.
///
/// Original bug: ChannelDispatcher.channelInactive set `channel.isOpen = false`
/// BEFORE calling the handler. HttpProxyChannelHandler.channelInactive (the
/// client-side path) only closed the remote channel, never the local one, so
/// once the client sent FIN the proxy-side socket for the *client* connection
/// was marked closed but never actually `close()`d. It sat in CLOSE_WAIT.
///
/// This test reproduces the scenario:
///   1. Open a real HTTP proxy connection through Server.
///   2. Make one successful request so the remote channel exists.
///   3. Client half-closes (sends FIN) by destroying its socket.
///   4. Wait for the proxy to observe FIN (channelInactive fires).
///   5. Count CLOSE_WAIT sockets owned by this Dart process via lsof.
void main() {
  const int proxyPort = 19101;
  const int originPort = 18181;

  late Server proxy;
  late HttpServer originHttp;

  setUpAll(() async {
    originHttp = await HttpServer.bind(InternetAddress.loopbackIPv4, originPort);
    originHttp.listen((req) async {
      req.response.headers.set('Connection', 'close');
      req.response.write('ok');
      await req.response.close();
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
        HttpProxyChannelHandler(listener: null, interceptors: const []),
      );
    });
    await proxy.bind(proxyPort);
  });

  tearDownAll(() async {
    await proxy.stop();
    await originHttp.close(force: true);
  });

  Future<void> doRequest() async {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, proxyPort);
    final done = Completer<void>();
    socket.listen((_) {}, onError: (_) {}, onDone: () {
      if (!done.isCompleted) done.complete();
    }, cancelOnError: true);
    socket.write('GET http://127.0.0.1:$originPort/ HTTP/1.1\r\n'
        'Host: 127.0.0.1:$originPort\r\n'
        '\r\n');
    await socket.flush();
    await done.future.timeout(const Duration(seconds: 5));
    // Simulate the client going away: kernel sends FIN (or RST) and the proxy
    // side observes onDone. We do NOT wait for the proxy to close its side;
    // we want to inspect that the proxy DID close its side on its own.
    socket.destroy();
  }

  /// Count CLOSE_WAIT sockets owned by the current process via lsof.
  /// macOS / Linux only; returns -1 if lsof is unavailable.
  Future<int> countCloseWait() async {
    try {
      final result = await Process.run('lsof', ['-nP', '-a', '-p', '$pid', '-iTCP', '-sTCP:CLOSE_WAIT']);
      if (result.exitCode != 0) return 0;
      final lines = const LineSplitter().convert(result.stdout as String);
      // First line is the header.
      return lines.length > 1 ? lines.length - 1 : 0;
    } catch (_) {
      return -1;
    }
  }

  test('client FIN must not leave CLOSE_WAIT sockets in the proxy (issue #1014)', () async {
    // Warm up: ensure any setUpAll noise is gone.
    await Future.delayed(const Duration(milliseconds: 200));
    final baseline = await countCloseWait();

    const attempts = 15;
    for (var i = 0; i < attempts; i++) {
      await doRequest();
    }

    // Give the proxy time to observe FINs and (correctly) close its side.
    // If the bug exists, the sockets stay in CLOSE_WAIT forever; if fixed,
    // they disappear within a few hundred ms.
    await Future.delayed(const Duration(milliseconds: 1500));

    final after = await countCloseWait();
    // ignore: avoid_print
    print('CLOSE_WAIT baseline=$baseline after=$after (attempts=$attempts)');

    if (baseline < 0 || after < 0) {
      // ignore: avoid_print
      print('lsof unavailable, skipping assertion');
      return;
    }

    expect(after - baseline, 0,
        reason: 'Proxy leaked ${after - baseline} CLOSE_WAIT sockets after $attempts client disconnects');
  });

  test('Server.stop() closes every accepted channel', () async {
    final config = Configuration.fromJson({
      'enableSsl': false,
      'enableSocks5': false,
      'enableSystemProxy': false,
      'enabledHttp2': false,
    });
    config.port = 0;
    final server = Server(config);
    server.initChannel((channel) {
      channel.dispatcher.handle(
        HttpRequestCodec(),
        HttpResponseCodec(),
        HttpProxyChannelHandler(listener: null, interceptors: const []),
      );
    });
    final bound = await server.bind(0);

    // Open idle client connections that never send anything.
    final clients = <Socket>[];
    for (var i = 0; i < 8; i++) {
      clients.add(await Socket.connect(InternetAddress.loopbackIPv4, bound.port));
    }
    await Future.delayed(const Duration(milliseconds: 100));

    await server.stop();

    // After stop(), every client socket must observe a FIN from the proxy.
    for (final c in clients) {
      final closed = Completer<void>();
      c.listen((_) {}, onError: (_) {}, onDone: () {
        if (!closed.isCompleted) closed.complete();
      }, cancelOnError: true);
      await closed.future.timeout(const Duration(seconds: 2));
      c.destroy();
    }

    final probe = await ServerSocket.bind(InternetAddress.anyIPv4, bound.port);
    await probe.close();
  });
}
