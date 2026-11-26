import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/channel/network.dart';
import 'package:proxypin/network/handle/http_proxy_handle.dart';
import 'package:proxypin/network/http/codec.dart';

/// 严格复现 issue #1014 的 server-side CLOSE_WAIT：
/// origin 主动 close（Connection: close），client 持续 keep-alive。
/// proxy->origin 那条 socket 必须被 proxy 主动 close()，否则永远 CLOSE_WAIT。
void main() {
  const int proxyPort = 19102;
  const int originPort = 18182;

  late Server proxy;
  late HttpServer originHttp;

  setUpAll(() async {
    originHttp = await HttpServer.bind(InternetAddress.loopbackIPv4, originPort);
    originHttp.listen((req) async {
      // Origin 主动 close：发完响应立刻关闭本端 socket
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

  Future<int> countCloseWait() async {
    try {
      final result = await Process.run('lsof', ['-nP', '-a', '-p', '$pid', '-iTCP', '-sTCP:CLOSE_WAIT']);
      if (result.exitCode != 0) return 0;
      final lines = const LineSplitter().convert(result.stdout as String);
      return lines.length > 1 ? lines.length - 1 : 0;
    } catch (_) {
      return -1;
    }
  }

  test('origin-initiated close must not leak proxy->origin socket (issue #1014)', () async {
    // client 持续保持连接，反复发请求，每次 origin 都主动 close。
    // 这模拟浏览器 keep-alive + 上游 Connection: close 的真实场景。
    final client = await Socket.connect(InternetAddress.loopbackIPv4, proxyPort);
    final responseBuf = <int>[];
    client.listen((d) => responseBuf.addAll(d), onError: (_) {}, cancelOnError: true);

    const attempts = 15;
    for (var i = 0; i < attempts; i++) {
      responseBuf.clear();
      client.write('GET http://127.0.0.1:$originPort/req$i HTTP/1.1\r\n'
          'Host: 127.0.0.1:$originPort\r\n'
          'Connection: keep-alive\r\n'
          '\r\n');
      await client.flush();
      // 等响应回来
      await Future.delayed(const Duration(milliseconds: 80));
    }

    // 等 proxy 处理完所有 server-side channelInactive，并把 client 也 destroy，
    // 模拟浏览器关闭页面/退出后不会再有新请求的状态。
    await Future.delayed(const Duration(milliseconds: 1500));
    client.destroy();
    await Future.delayed(const Duration(milliseconds: 500));

    final closeWait = await countCloseWait();
    // ignore: avoid_print
    print('CLOSE_WAIT after $attempts origin-closed requests: $closeWait');

    expect(closeWait, 0,
        reason: 'Proxy leaked $closeWait CLOSE_WAIT sockets (proxy->origin) after $attempts origin-initiated closes');
  });
}
