import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/network.dart';
import 'package:proxypin/network/handle/http_proxy_handle.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/network/channel/host_port.dart';

/// Regression for the in-app "repeat/replay" path: the request is sent
/// through the local proxy, so the internal client first issues a CONNECT and
/// reads the proxy's "200 Connection established" reply. That reply has no
/// Content-Length and must be parsed as a CONNECT response, not diverted to
/// close-delimited raw relay (which made the tunnel / replay fail).
///
/// Before the fix [HttpClients.connectRequest] never registered the CONNECT
/// as the context's current request, so the decoder's CONNECT exemption did
/// not match on this internal channel.
void main() {
  const int proxyPort = 19097;

  late Server proxy;

  setUpAll(() async {
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
  });

  test('internal CONNECT to local proxy parses 200 and restores context', () async {
    final channelContext = ChannelContext();
    final client = Client()
      ..initChannel((channel) =>
          channel.dispatcher.channelHandle(HttpClientCodec(), HttpProxyChannelHandler(listener: null, interceptors: [])));
    final channel = await client.connect(HostAndPort.host('127.0.0.1', proxyPort), channelContext);

    // Same shape as the replay path: a freshly created context whose
    // currentRequest is null until connectRequest registers the CONNECT.
    expect(channelContext.currentRequest, isNull);

    await HttpClients.connectRequest(
        channelContext, HostAndPort.host('example.com', 443), channel);

    // The 200 was consumed successfully (no throw) and the context must be
    // restored so subsequent in-tunnel responses are parsed normally.
    expect(channelContext.currentRequest, isNull);

    channel.close();
  });
}
