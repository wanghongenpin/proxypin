// 端到端：真实 ProxyServer（HTTPS 解密）→ 本地 TLS 服务器，tcpdump 抓包，
// 导出带 ProxyPin 上游密钥的 pcapng，tshark 不加 keylog 参数即可解密上游明文。
// 需要：tcpdump（root）、openssl、tshark、curl；缺任一则跳过。
import 'dart:io';

// ignore: implementation_imports
import 'package:device_info_plus/src/device_info_plus_linux.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/pcap/pcapng.dart';
import 'package:proxypin/network/util/tls_keylog.dart';

bool _has(String bin) => Process.runSync('which', [bin]).exitCode == 0;

void main() {
  final ok = ['tcpdump', 'openssl', 'tshark', 'curl'].every(_has);

  test('ProxyPin upstream TLS keys decrypt upstream leg in tshark', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // flutter test 不会自动注册桌面插件，脚本拦截器需要设备 ID
    DeviceInfoPlusLinuxPlugin.registerWith();
    final dir = await Directory.systemTemp.createTemp('keylog_e2e');
    // CA 证书从 app support 目录加载：把 path_provider 指向临时目录
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (call) async => dir.path);
    const upstreamPort = 18445;
    const proxyPort = 19099;

    Process.runSync('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', '${dir.path}/k.pem', '-out', '${dir.path}/c.pem',
      '-days', '1', '-subj', '/CN=localhost'
    ]);
    // 上游：带 Content-Length 的标准 HTTPS 服务
    final server = await Process.start('python3', [
      '-c',
      '''
import http.server, ssl, sys
class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def do_GET(self):
        body = b"upstream-ok"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", $upstreamPort), H)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(sys.argv[1], sys.argv[2])
s.socket = ctx.wrap_socket(s.socket, server_side=True)
s.serve_forever()
''',
      '${dir.path}/c.pem',
      '${dir.path}/k.pem'
    ]);

    final config = Configuration.fromJson({'port': proxyPort, 'enableSsl': true, 'enableSystemProxy': false});
    final proxy = ProxyServer(config);
    await proxy.start();

    final pcap = '${dir.path}/cap.pcap';
    final dump = await Process.start('tcpdump', ['-i', 'lo', '-U', '-s', '0', '-w', pcap, 'tcp port $upstreamPort']);
    await Future.delayed(const Duration(seconds: 1));

    TlsKeyLog.instance.start();
    final curl = await Process.run('curl', [
      '-skv', '--noproxy', '', '--max-time', '10', '-x', 'http://127.0.0.1:$proxyPort', '-H', 'X-Probe: via-proxypin',
      'https://127.0.0.1:$upstreamPort/secret-through-proxy'
    ]);
    await Future.delayed(const Duration(seconds: 1));
    TlsKeyLog.instance.stop();

    dump.kill(ProcessSignal.sigint);
    await dump.exitCode;
    server.kill();
    await proxy.stop();

    // ignore: avoid_print
    print(curl.stderr.toString().split('\n').where((l) => l.startsWith('<') || l.contains('issuer') || l.contains('closed') || l.contains('rror') || l.contains('Recv')).join('\n'));
    expect(curl.stdout.toString(), contains('upstream-ok'), reason: 'curl through proxy failed: ${curl.stderr}');
    expect(TlsKeyLog.instance.length, greaterThan(0), reason: 'no upstream keys collected');

    final out = File('${dir.path}/cap.pcapng');
    await PcapngWriter.convertFile(File(pcap), out, keyLog: TlsKeyLog.instance.export());

    final noKeys = Process.runSync(
        'tshark', ['-r', pcap, '-d', 'tcp.port==$upstreamPort,tls', '-q', '-z', 'follow,tls,ascii,0']);
    expect(noKeys.stdout, isNot(contains('secret-through-proxy')));

    final withKeys = Process.runSync(
        'tshark', ['-r', out.path, '-d', 'tcp.port==$upstreamPort,tls', '-q', '-z', 'follow,tls,ascii,0']);
    // ignore: avoid_print
    print(withKeys.stdout.toString().split('\n').where((l) => l.contains('GET') || l.contains('X-Probe')).join('\n'));
    expect(withKeys.stdout, contains('GET /secret-through-proxy'));
    expect(withKeys.stdout, contains('X-Probe: via-proxypin'));
    await dir.delete(recursive: true);
  }, skip: ok ? false : 'needs tcpdump/openssl/tshark/curl', timeout: const Timeout(Duration(minutes: 1)));
}
