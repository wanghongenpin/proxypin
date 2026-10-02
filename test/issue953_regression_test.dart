import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/byte_buf.dart';

void main() {
  // issue #953: 模拟 iOS MITM。先解码 CONNECT（currentRequest 残留为
  // CONNECT），隧道建立后在同一 context 上解码真正的 POST，body 不能丢。
  test('request codec: stale CONNECT must not drop following POST body', () {
    final codec = HttpRequestCodec();
    final ctx = ChannelContext();

    // 模拟 dispatcher 已处理 CONNECT，currentRequest 残留为 CONNECT
    ctx.currentRequest = HttpRequest(HttpMethod.connect, 'a:443');
    expect(ctx.currentRequest?.method.name, 'CONNECT');

    const body = '{"login":1}';
    final r = codec.decode(
        ctx,
        ByteBuf(utf8.encode(
            'POST /login HTTP/1.1\r\nHost: a\r\nContent-Type: application/json\r\nContent-Length: ${body.length}\r\n\r\n$body')));

    expect(r.isDone, isTrue);
    expect(r.data?.bodyAsString, body, reason: 'POST body must be captured despite stale CONNECT');
  });

  // 响应侧保护不能丢：串联上游代理解码 "200 Connection established"。
  test('response codec: CONNECT 200 still skips body resolution', () {
    final codec = HttpResponseCodec();
    final ctx = ChannelContext()
      ..currentRequest = HttpRequest(HttpMethod.connect, 'a:443');
    final r = codec.decode(ctx, ByteBuf(utf8.encode('HTTP/1.1 200 Connection established\r\n\r\n')));
    expect(r.isDone, isTrue);
    expect(r.data?.status.code, 200);
  });

  // pendingConnectResponse（本端发出 CONNECT）响应解码仍生效。
  test('response codec: pendingConnectResponse still skips body', () {
    final codec = HttpClientCodec();
    codec.responseCodec.pendingConnectResponse = true;
    final ctx = ChannelContext();
    final r = codec.decode(ctx, ByteBuf(utf8.encode('HTTP/1.1 200 Connection established\r\n\r\n')));
    expect(r.isDone, isTrue);
    expect(r.data?.status.code, 200);
  });
}
