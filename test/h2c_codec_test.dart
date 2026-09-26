import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/h2/h2_codec.dart';
import 'package:proxypin/network/http/h2/hpack/hpack.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/byte_buf.dart';

const _preface = 'PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n';
const _settings = <int>[0, 0, 0, 4, 0, 0, 0, 0, 0];

List<int> _headers(int streamId, List<Header> headers) {
  final block = HPackEncoder().encode(headers);
  return [
    block.length >> 16,
    (block.length >> 8) & 255,
    block.length & 255,
    1,
    5,
    0,
    0,
    0,
    streamId,
    ...block,
  ];
}

List<int> _request() => [
      ...ascii.encode(_preface),
      ..._settings,
      ..._headers(1, [
        Header.ascii(':method', 'GET'),
        Header.ascii(':scheme', 'http'),
        Header.ascii(':authority', 'example.test:18080'),
        Header.ascii(':path', '/resource?q=1'),
      ]),
    ];

void main() {
  group('h2c prior knowledge', () {
    test('dispatches cleartext preface to HTTP/2 without TLS ALPN', () {
      final result = HttpRequestCodec().decode(ChannelContext(), ByteBuf(_request()));
      final request = result.data!;
      expect(result.isDone, isTrue);
      expect(request.protocolVersion, 'HTTP/2');
      expect(request.method, HttpMethod.get);
      expect(request.requestUrl, 'http://example.test:18080/resource?q=1');
      expect(request.streamId, 1);
      expect(result.forward, [...ascii.encode(_preface), ..._settings]);
    });

    test('retains incomplete preface and frames at every socket split', () {
      final wire = _request();
      for (var split = 1; split < wire.length; split++) {
        final codec = HttpRequestCodec();
        final context = ChannelContext();
        final buffer = ByteBuf(wire.sublist(0, split));
        final first = codec.decode(context, buffer);
        expect(first.data, isNull, reason: 'split=$split');
        final forwarded = <int>[...?first.forward];
        buffer.clearRead();
        buffer.add(wire.sublist(split));
        final second = codec.decode(context, buffer);
        forwarded.addAll(second.forward ?? []);
        expect(second.data?.requestUrl, 'http://example.test:18080/resource?q=1', reason: 'split=$split');
        expect(second.isDone, isTrue, reason: 'split=$split');
        expect(forwarded, [...ascii.encode(_preface), ..._settings], reason: 'split=$split');
      }
    });

    test('uses the detected protocol for cleartext server responses', () {
      final context = ChannelContext();
      final request = HttpRequestCodec().decode(context, ByteBuf(_request())).data!;
      final result = HttpResponseCodec().decode(
          context,
          ByteBuf([
            ..._settings,
            ..._headers(1, [Header.ascii(':status', '204')]),
          ]));
      expect(result.data?.protocolVersion, 'HTTP/2');
      expect(result.data?.status.code, 204);
      expect(result.data?.request, same(request));
      expect(result.forward, _settings);
    });

    test('preserves the non-default authority port when forwarding', () {
      final request = HttpRequestCodec().decode(ChannelContext(), ByteBuf(_request())).data!;
      final forwarded = Http2RequestDecoder().encodeHeaders(request);
      expect(forwarded.singleWhere((header) => header.nameString == ':authority').valueString, 'example.test:18080');
    });

    test('HTTP/2 decoder waits for a fragmented connection preface', () {
      final decoder = Http2RequestDecoder();
      final context = ChannelContext();
      final buffer = ByteBuf();
      final wire = _request();
      final forwarded = <int>[];
      HttpRequest? request;
      for (final byte in wire) {
        buffer.add([byte]);
        final result = decoder.decode(context, buffer);
        forwarded.addAll(result.forward ?? []);
        request ??= result.data;
        buffer.clearRead();
      }
      expect(request?.uri, '/resource?q=1');
      expect(forwarded, [...ascii.encode(_preface), ..._settings]);
    });
  });

  group('HTTP/1.1 detection regression', () {
    test('POST sharing the first preface byte is still HTTP/1.1', () {
      final codec = HttpRequestCodec();
      final context = ChannelContext();
      final buffer = ByteBuf(ascii.encode('P'));
      expect(codec.decode(context, buffer).data, isNull);
      buffer.add(ascii.encode('OST /form HTTP/1.1\r\nHost: example.test\r\nContent-Length: 3\r\n\r\nx=1'));
      final request = codec.decode(context, buffer).data!;
      expect(request.protocolVersion, 'HTTP/1.1');
      expect(request.method, HttpMethod.post);
      expect(request.bodyAsString, 'x=1');
    });

    test('empty socket input remains incomplete', () {
      final result = HttpRequestCodec().decode(ChannelContext(), ByteBuf());
      expect(result.isDone, isFalse);
      expect(result.data, isNull);
    });
  });
}
