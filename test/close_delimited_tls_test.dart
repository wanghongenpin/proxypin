import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:device_info_plus/src/device_info_plus_linux.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';

/// 回归：HTTPS 解密（CONNECT + enableSsl）路径下，上游返回 close 定界的
/// HTTP/1.0 响应（无 Content-Length / 无 Transfer-Encoding，靠关闭连接结束 body），
/// 代理必须在上游关闭后把完整响应转发给客户端，而不是让客户端挂起到超时。
void main() {
  const int proxyPort = 19097;
  const String body = '<html>hello-close-delimited-over-tls-0123456789</html>';

  late Directory dir;
  late ProxyServer proxy;
  late SecureServerSocket origin;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // flutter test 不会自动注册桌面插件，脚本拦截器需要设备 ID
    DeviceInfoPlusLinuxPlugin.registerWith();
    dir = await Directory.systemTemp.createTemp('close_delimited_tls');
    // CA 证书从 app support 目录加载：把 path_provider 指向临时目录
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => dir.path);

    var gen = Process.runSync('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', '${dir.path}/k.pem', '-out', '${dir.path}/c.pem', //
      '-days', '1', '-subj', '/CN=localhost'
    ]);
    expect(gen.exitCode, 0, reason: gen.stderr.toString());

    final ctx = SecurityContext()
      ..useCertificateChain('${dir.path}/c.pem')
      ..usePrivateKey('${dir.path}/k.pem');
    // 上游：与 `openssl s_server -www` 相同形态的 HTTP/1.0 close 定界响应
    origin = await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, ctx);
    origin.listen((socket) {
      var received = <int>[];
      var responded = false;
      socket.listen((data) async {
        received.addAll(data);
        if (responded || !latin1.decode(received).contains('\r\n\r\n')) return;
        responded = true;
        try {
          // 只发送响应，不主动关闭 TCP：模拟 `openssl s_server -www` 发送 close_notify 后
          // 等待对端回应（双向 shutdown）的行为——Dart 的 SecureSocket 本身不会把
          // close_notify 上报为 onDone，因此代理侧看到的就是“数据发完但连接未关闭”。
          socket.add(utf8.encode('HTTP/1.0 200 ok\r\nContent-type: text/html\r\n\r\n$body'));
          await socket.flush();
        } catch (_) {}
      }, onError: (_) {}, onDone: () {
        // 对端（代理）半关闭后再关闭连接，结束 close 定界的 body
        socket.close().catchError((_) => socket);
      }, cancelOnError: true);
    }, onError: (_) {});

    final config = Configuration.fromJson({'port': proxyPort, 'enableSsl': true, 'enableSystemProxy': false});
    proxy = ProxyServer(config);
    await proxy.start();
  });

  tearDownAll(() async {
    await proxy.stop();
    await origin.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('close-delimited HTTP/1.0 response over HTTPS MITM reaches the client', () async {
    final port = origin.port;
    // TestWidgetsFlutterBinding 会把 HttpClient 替换成恒返回 400 的假实现，这里显式使用真实实现
    final client = HttpOverrides.runWithHttpOverrides(() => HttpClient(), _RealHttpOverrides())
      ..findProxy = ((_) => 'PROXY 127.0.0.1:$proxyPort')
      ..badCertificateCallback = ((_, __, ___) => true);
    try {
      final request = await client.getUrl(Uri.parse('https://localhost:$port/x'));
      final response = await request.close().timeout(const Duration(seconds: 5));
      final text = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 5));
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/html');
      expect(text, body);
    } finally {
      client.close(force: true);
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  // 与 issue 复现一致：openssl s_server -www（HTTP/1.0、无 Content-Length、发完即关闭）+ curl
  test('openssl s_server -www through proxy returns promptly (curl)', () async {
    final server = await Process.start('openssl', [
      's_server', '-accept', '0', '-cert', '${dir.path}/c.pem', '-key', '${dir.path}/k.pem', '-www', //
    ]);
    try {
      // s_server 会打印 "ACCEPT 0.0.0.0:<port>"
      final port = await server.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((l) => RegExp(r'ACCEPT .*:(\d+)').firstMatch(l)?.group(1))
          .firstWhere((p) => p != null)
          .timeout(const Duration(seconds: 5));
      final sw = Stopwatch()..start();
      final curl = await Process.run('curl', [
        '-sk', '--noproxy', '', '--max-time', '8', '-x', 'http://127.0.0.1:$proxyPort', '-D', '-', //
        'https://localhost:$port/x'
      ]);
      sw.stop();
      expect(curl.exitCode, 0, reason: 'curl exit ${curl.exitCode} after ${sw.elapsed}: ${curl.stderr}');
      expect(curl.stdout.toString(), contains('HTTP/1.0 200 ok'));
      expect(curl.stdout.toString().toLowerCase(), contains('content-type: text/html'));
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    } finally {
      server.kill();
    }
  }, skip: _has('curl') ? false : 'needs curl', timeout: const Timeout(Duration(seconds: 30)));
}

class _RealHttpOverrides extends HttpOverrides {}

bool _has(String bin) => Process.runSync('which', [bin]).exitCode == 0;
