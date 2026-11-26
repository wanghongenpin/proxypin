// Root 模式停止 / 变更规则后，已经被重定向的长连接需被断开，客户端才会按新规则重连
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:device_info_plus/src/device_info_plus_linux.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/native/vpn.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';

void main() {
  test('closeConnections drops kept-alive proxied connections, server keeps listening', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    DeviceInfoPlusLinuxPlugin.registerWith();
    final dir = await Directory.systemTemp.createTemp('close_e2e');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (call) async => dir.path);

    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((r) => r.response
      ..headers.contentLength = 2
      ..write('ok')
      ..close());

    const port = 19097;
    final proxy = ProxyServer(Configuration.fromJson({'port': port, 'enableSystemProxy': false}));
    await proxy.start();
    Vpn.onRootRulesChanged = () => proxy.server?.closeConnections();
    try {
      final socket = await Socket.connect('127.0.0.1', port);
      final closed = Completer<void>();
      final received = StringBuffer();
      socket.listen((d) => received.write(utf8.decode(d, allowMalformed: true)),
          onDone: () => closed.complete(), onError: (_) => closed.complete());
      final url = 'http://127.0.0.1:${upstream.port}/a';
      socket.write('GET $url HTTP/1.1\r\nHost: 127.0.0.1:${upstream.port}\r\nConnection: keep-alive\r\n\r\n');
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        return !received.toString().endsWith('ok');
      }).timeout(const Duration(seconds: 5));
      expect(closed.isCompleted, isFalse, reason: 'keep-alive connection stays open');

      Vpn.onRootRulesChanged!();
      await closed.future.timeout(const Duration(seconds: 3));

      // 监听仍在，新连接可用
      final again = await Socket.connect('127.0.0.1', port);
      again.destroy();
    } finally {
      Vpn.onRootRulesChanged = null;
      await proxy.stop();
      await upstream.close(force: true);
      await dir.delete(recursive: true);
    }
  });
}
