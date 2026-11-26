// 端到端：热点 / 局域网设备通过 http://<本机IP>:<端口>/ssl 下载 CA 证书
import 'dart:io';

// ignore: implementation_imports
import 'package:device_info_plus/src/device_info_plus_linux.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/utils/ip.dart';

void main() {
  test('GET http://<local ip>:port/ssl returns the CA certificate', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    DeviceInfoPlusLinuxPlugin.registerWith();
    final dir = await Directory.systemTemp.createTemp('ca_e2e');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (call) async => dir.path);
    const port = 19098;
    final proxy = ProxyServer(Configuration.fromJson({'port': port, 'enableSsl': true, 'enableSystemProxy': false}));
    await proxy.start();
    try {
      final ip = (await localIps()).firstWhere((e) => e != '127.0.0.1');
      final r = await Process.run('curl', ['-s', '--noproxy', '*', '-m', '5', 'http://$ip:$port/ssl']);
      expect(r.stdout, contains('-----BEGIN CERTIFICATE-----'));
    } finally {
      await proxy.stop();
      await dir.delete(recursive: true);
    }
  }, skip: Process.runSync('which', ['curl']).exitCode == 0 ? false : 'curl not installed');
}
