import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/network.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/handle/http_proxy_handle.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/h2/hpack/hpack.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/util/file_read.dart';
import 'package:proxypin/utils/har.dart';

const _preface = 'PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n';

List<int> _frame(int type, int flags, int stream, List<int> body) => [
      body.length >> 16,
      (body.length >> 8) & 255,
      body.length & 255,
      type,
      flags,
      (stream >> 24) & 127,
      (stream >> 16) & 255,
      (stream >> 8) & 255,
      stream & 255,
      ...body,
    ];

class _FrameBuffer {
  final bytes = <int>[];

  List<(int, int, int, List<int>)> add(List<int> incoming) {
    bytes.addAll(incoming);
    final frames = <(int, int, int, List<int>)>[];
    while (bytes.length >= 9) {
      final length = (bytes[0] << 16) | (bytes[1] << 8) | bytes[2];
      if (bytes.length < length + 9) break;
      final stream = ((bytes[5] & 127) << 24) | (bytes[6] << 16) | (bytes[7] << 8) | bytes[8];
      frames.add((bytes[3], bytes[4], stream, bytes.sublist(9, length + 9)));
      bytes.removeRange(0, length + 9);
    }
    return frames;
  }
}

class _Capture extends EventListener {
  final requests = <HttpRequest>[];
  final responses = <HttpResponse>[];

  @override
  void onRequest(Channel channel, HttpRequest request) => requests.add(request);

  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) => responses.add(response);
}

class _Client {
  final io.Socket socket;
  final encoder = HPackEncoder();
  final decoder = HPackDecoder();
  final frames = _FrameBuffer();
  final responses = <int, Completer<List<int>>>{};
  final bodies = <int, List<int>>{};
  final headers = <int, Map<String, String>>{};
  final settings = Completer<void>();
  final pingAck = Completer<void>();
  bool deferSettingsAcks = false;
  int _deferredSettingsAcks = 0;

  void flushSettingsAcks() {
    deferSettingsAcks = false;
    while (_deferredSettingsAcks > 0) {
      socket.add(_frame(4, 1, 0, []));
      _deferredSettingsAcks--;
    }
  }

  _Client(this.socket) {
    socket.listen((bytes) {
      for (final (type, flags, stream, payload) in frames.add(bytes)) {
        if (type == 4 && flags == 0) {
          if (deferSettingsAcks) {
            _deferredSettingsAcks++;
          } else {
            socket.add(_frame(4, 1, 0, []));
          }
          if (!settings.isCompleted) settings.complete();
        }
        if (type == 6 && flags == 1 && !pingAck.isCompleted) pingAck.complete();
        if (type == 1) {
          headers[stream] = {for (final header in decoder.decode(payload)) header.nameString: header.valueString};
        }
        if (type == 0) bodies.putIfAbsent(stream, () => []).addAll(payload);
        if ((type == 0 || type == 1) && (flags & 1) != 0) {
          responses.putIfAbsent(stream, Completer<List<int>>.new).complete(bodies[stream] ?? []);
        }
      }
    });
  }

  List<int> request(int stream, int originPort, String path, {String? body}) {
    responses.putIfAbsent(stream, Completer<List<int>>.new);
    final payload = body == null ? <int>[] : utf8.encode(body);
    return [
      ..._frame(
          1,
          body == null ? 5 : 4,
          stream,
          encoder.encode([
            Header.ascii(':method', body == null ? 'GET' : 'POST'),
            Header.ascii(':scheme', 'http'),
            Header.ascii(':authority', '127.0.0.1:$originPort'),
            Header.ascii(':path', path),
            if (body != null) Header.ascii('content-length', '${payload.length}'),
            Header.ascii('accept-encoding', 'gzip'),
          ])),
      if (body != null) ..._frame(0, 1, stream, payload),
    ];
  }

  Future<String> response(int stream) async {
    final bytes = await responses[stream]!.future.timeout(const Duration(seconds: 8));
    expect(headers[stream]?[':status'], '200');
    return utf8.decode(io.gzip.decode(bytes));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Server proxy;
  late io.ServerSocket origin;
  late io.Directory work;
  late _Capture capture;
  late int proxyPort;
  final sockets = <io.Socket>[];
  final received = <int, Map<String, String>>{};
  final errors = <Object>[];
  var originConnections = 0;
  var originSettingsAcks = 0;
  String? previousHome;

  setUpAll(() async {
    previousHome = FileRead.userHome;
    work = await io.Directory.systemTemp.createTemp('proxypin-h2c-test-');
    FileRead.userHome = work.path;
  });

  tearDownAll(() async {
    FileRead.userHome = previousHome;
    await work.delete(recursive: true);
  });

  setUp(() async {
    originConnections = 0;
    originSettingsAcks = 0;
    received.clear();
    errors.clear();
    capture = _Capture();
    origin = await io.ServerSocket.bind(io.InternetAddress.loopbackIPv4, 0);
    origin.listen((socket) {
      sockets.add(socket);
      originConnections++;
      var awaitingPreface = true;
      final prefix = <int>[];
      final frames = _FrameBuffer();
      final decoder = HPackDecoder();
      final encoder = HPackEncoder();
      final requestBodies = <int, List<int>>{};
      var highestStream = 0;
      socket.listen((incoming) {
        try {
          List<int> bytes = incoming;
          if (awaitingPreface) {
            prefix.addAll(bytes);
            if (prefix.length < _preface.length) return;
            expect(prefix.sublist(0, _preface.length), ascii.encode(_preface));
            awaitingPreface = false;
            bytes = prefix.sublist(_preface.length);
            socket.add(_frame(4, 0, 0, []));
          }
          for (final (type, flags, stream, payload) in frames.add(bytes)) {
            if (type == 4 && flags == 0) socket.add(_frame(4, 1, 0, []));
            if (type == 4 && flags == 1) originSettingsAcks++;
            if (type == 6 && flags == 0) socket.add(_frame(6, 1, 0, payload));
            if (type == 1) {
              expect(stream, greaterThan(highestStream), reason: '新流必须按递增流号打开');
              highestStream = stream;
              received[stream] = {for (final header in decoder.decode(payload)) header.nameString: header.valueString};
            }
            if (type == 3) expect(received.containsKey(stream), isTrue, reason: '不能重置上游尚未打开的流');
            if (type == 0) requestBodies.putIfAbsent(stream, () => []).addAll(payload);
            if ((type == 0 || type == 1) && (flags & 1) != 0) {
              final request = received[stream]!;
              expect(request[':authority'], '127.0.0.1:${origin.port}');
              final reply = '${request[':path']}|${utf8.decode(requestBodies[stream] ?? [])}';
              final compressed = io.gzip.encode(utf8.encode(reply));
              socket.add([
                ..._frame(
                    1,
                    4,
                    stream,
                    encoder.encode([
                      Header.ascii(':status', '200'),
                      Header.ascii('content-type', 'text/plain; charset=utf-8'),
                      Header.ascii('content-encoding', 'gzip'),
                      Header.ascii('content-length', '${compressed.length}'),
                    ])),
                ..._frame(0, 1, stream, compressed),
              ]);
            }
          }
        } catch (error) {
          errors.add(error);
        }
      });
    });
    final config = Configuration.fromJson({
      'enableSsl': false,
      'enableSocks5': false,
      'enableSystemProxy': false,
      'enabledHttp2': true,
    });
    proxy = Server(config, listener: capture);
    proxy.initChannel((channel) {
      channel.dispatcher.channelHandle(HttpServerCodec(), HttpProxyChannelHandler(listener: capture, interceptors: []));
    });
    proxyPort = (await proxy.bind(0)).port;
  });

  tearDown(() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    sockets.clear();
    await proxy.stop();
    await origin.close();
    expect(errors, isEmpty);
  });

  Future<_Client> client() async {
    final socket = await io.Socket.connect(io.InternetAddress.loopbackIPv4, proxyPort);
    sockets.add(socket);
    return _Client(socket);
  }

  test('buffers preface and SETTINGS until authority arrives, then captures gzip response', () async {
    final peer = await client();
    // 人为拆分客户端前置帧时，不能让自动ACK抢在它的第一个SETTINGS之前。
    peer.deferSettingsAcks = true;
    peer.socket.add(ascii.encode(_preface));
    await peer.socket.flush();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    peer.socket.add(_frame(4, 0, 0, []));
    await peer.socket.flush();
    peer.flushSettingsAcks();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    peer.socket.add(peer.request(1, origin.port, '/first?q=1'));
    expect(await peer.response(1), '/first?q=1|');
    expect(originConnections, 1);
    expect(capture.requests.single.protocolVersion, 'HTTP/2');
    expect(capture.responses.single.protocolVersion, 'HTTP/2');
    expect(capture.responses.single.bodyAsString, '/first?q=1|');
    final exported = Har.toHar(capture.requests.single);
    expect(exported['request']['httpVersion'], 'HTTP/2');
    expect(exported['response']['httpVersion'], 'HTTP/2');
    expect(exported['response']['status'], 200);
    expect(exported['response']['_responseAvailable'], isTrue);
    expect(exported['response']['_originalContentEncoding'], 'gzip');
    expect(exported['response']['content']['text'], '/first?q=1|');
  });

  test('HAR missing responses do not invent HTTP/1.1 or an observed response', () {
    final request = HttpRequest(HttpMethod.get, 'http://example.test/pending', protocolVersion: 'HTTP/2');
    for (final exported in [Har.toHar(request), Har.toHarResponse(request)]) {
      expect(exported['response']['status'], 0);
      expect(exported['response']['httpVersion'], isEmpty);
      expect(exported['response']['_responseAvailable'], isFalse);
      expect(exported['response']['_originalContentEncoding'], isNull);
    }
    expect(Har.toHar(request)['request']['httpVersion'], 'HTTP/2');
  });

  test('HAR retains original Brotli evidence without changing decoded export headers', () {
    final request = HttpRequest(HttpMethod.get, 'http://example.test/compressed', protocolVersion: 'HTTP/2');
    request.response = HttpResponse(HttpStatus.ok, protocolVersion: 'HTTP/2')
      ..headers.set(HttpHeaders.CONTENT_ENCODING, 'br');
    final exported = Har.toHar(request);
    expect(exported['response']['_originalContentEncoding'], 'br');
    expect(exported['response']['_responseAvailable'], isTrue);
    expect(request.response!.headers.get(HttpHeaders.CONTENT_ENCODING), 'br');
  });

  test('completes the server preface before headers without leaking the bootstrap SETTINGS ack', () async {
    final peer = await client();
    peer.socket.add([...ascii.encode(_preface), ..._frame(4, 0, 0, [])]);
    await peer.settings.future.timeout(const Duration(seconds: 2));
    expect(originConnections, 0);
    peer.socket.add(peer.request(1, origin.port, '/after-settings'));
    expect(await peer.response(1), '/after-settings|');
    // 同一方向的PING排在两个SETTINGS确认之后，收到回包就能检查上游实际收到的确认数。
    peer.socket.add(_frame(6, 0, 0, List<int>.filled(8, 1)));
    await peer.pingAck.future.timeout(const Duration(seconds: 2));
    expect(originSettingsAcks, 1);
  });

  test('drains coalesced streams without another socket event and retains POST bytes', () async {
    final peer = await client();
    const body = '{"text":"真实测试内容"}';
    peer.socket.add([
      ...ascii.encode(_preface),
      ..._frame(4, 0, 0, []),
      ...peer.request(1, origin.port, '/one'),
      ...peer.request(3, origin.port, '/two', body: body),
      ...peer.request(5, origin.port, '/three'),
    ]);
    expect(
        await Future.wait([peer.response(1), peer.response(3), peer.response(5)]), ['/one|', '/two|$body', '/three|']);
    expect(originConnections, 1);
    expect(capture.requests, hasLength(3));
    expect(capture.responses, hasLength(3));
    expect(capture.responses.map((response) => response.request!.uri).toSet(), {'/one', '/two', '/three'});
  });

  test('concurrent socket events share the first upstream connection', () async {
    final peer = await client();
    peer.socket.add([...ascii.encode(_preface), ..._frame(4, 0, 0, []), ...peer.request(1, origin.port, '/a')]);
    await peer.socket.flush();
    await Future<void>.delayed(const Duration(milliseconds: 1));
    peer.socket.add(peer.request(3, origin.port, '/b'));
    await peer.socket.flush();
    peer.socket.add(peer.request(5, origin.port, '/c'));
    expect(await Future.wait([peer.response(1), peer.response(3), peer.response(5)]), ['/a|', '/b|', '/c|']);
    expect(originConnections, 1);
    expect(capture.requests, hasLength(3));
  });

  test('an established h2c body is not sniffed again as SOCKS5', () async {
    proxy.configuration.enableSocks5 = true;
    final peer = await client();
    peer.socket.add([...ascii.encode(_preface), ..._frame(4, 0, 0, [])]);
    await peer.settings.future.timeout(const Duration(seconds: 2));
    const body = '\u0005\u0001\u0000';
    final request = peer.request(1, origin.port, '/binary', body: body);
    peer.socket.add(request.sublist(0, request.length - 3));
    await peer.socket.flush();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    peer.socket.add(request.sublist(request.length - 3));
    expect(await peer.response(1), '/binary|$body');
    expect(capture.requests.single.body, [5, 1, 0]);
  });

  test('mixed POST bodies finishing out of order still open streams in order', () async {
    final peer = await client();
    peer.socket.add([...ascii.encode(_preface), ..._frame(4, 0, 0, [])]);
    await peer.settings.future.timeout(const Duration(seconds: 2));
    final first = peer.request(1, origin.port, '/slow-body', body: '{}');
    final third = peer.request(5, origin.port, '/later-body', body: '[]');
    peer.socket.add([
      ...first.sublist(0, first.length - 11),
      ...peer.request(3, origin.port, '/get-a'),
      ...third.sublist(0, third.length - 11),
      ...peer.request(7, origin.port, '/get-b'),
      ...third.sublist(third.length - 11),
    ]);
    await peer.socket.flush();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    peer.socket.add(first.sublist(first.length - 11));
    expect(await Future.wait([peer.response(1), peer.response(3), peer.response(5), peer.response(7)]),
        ['/slow-body|{}', '/get-a|', '/later-body|[]', '/get-b|']);
    expect(received.keys.toList(), [1, 3, 5, 7]);
    expect(originConnections, 1);
  });

  test('body frames coalesced after later GET headers cannot deadlock the drain', () async {
    final peer = await client();
    final first = peer.request(1, origin.port, '/body', body: '{}');
    peer.socket.add([
      ...ascii.encode(_preface),
      ..._frame(4, 0, 0, []),
      ...first.sublist(0, first.length - 11),
      ...peer.request(3, origin.port, '/get'),
      ...first.sublist(first.length - 11),
    ]);
    expect(await Future.wait([peer.response(1), peer.response(3)]), ['/body|{}', '/get|']);
    expect(originConnections, 1);
  });

  test('cancelling an incomplete earlier stream releases later requests without idle RST', () async {
    final peer = await client();
    final first = peer.request(1, origin.port, '/cancelled-body', body: '{}');
    peer.socket.add([
      ...ascii.encode(_preface),
      ..._frame(4, 0, 0, []),
      ...first.sublist(0, first.length - 11),
      ...peer.request(3, origin.port, '/survives'),
      ..._frame(3, 0, 1, [0, 0, 0, 8]),
      ...first.sublist(first.length - 11),
    ]);
    expect(await peer.response(3), '/survives|');
    expect(received.keys.toList(), [3]);
    expect(capture.requests.single.uri, '/survives');
  });

  test('a completed upstream connection cannot be replaced by a late cache miss', () async {
    final peer = await client();
    peer.socket.add([...ascii.encode(_preface), ..._frame(4, 0, 0, []), ...peer.request(1, origin.port, '/first')]);
    expect(await peer.response(1), '/first|');
    // 两批 TCP 事件在异步平台查询结束后仍应复用已经建立的同一上游连接。
    for (var stream = 3; stream < 13; stream += 2) {
      peer.socket.add(peer.request(stream, origin.port, '/next-$stream'));
      await peer.socket.flush();
    }
    expect(await Future.wait([for (var stream = 3; stream < 13; stream += 2) peer.response(stream)]),
        [for (var stream = 3; stream < 13; stream += 2) '/next-$stream|']);
    expect(originConnections, 1);
    for (final response in capture.responses) {
      expect(response.requestId, response.request!.requestId);
    }
  });

  test('filtered h2c connections keep protocol framing without recording traffic', () async {
    final saved = HostFilter.blacklist.toJson();
    HostFilter.blacklist.load({
      'enabled': true,
      'list': [r'^127\.0\.0\.1$']
    });
    try {
      final peer = await client();
      peer.socket
          .add([...ascii.encode(_preface), ..._frame(4, 0, 0, []), ...peer.request(1, origin.port, '/filtered-a')]);
      expect(await peer.response(1), '/filtered-a|');
      peer.socket.add(peer.request(3, origin.port, '/filtered-b'));
      expect(await peer.response(3), '/filtered-b|');
      expect(capture.requests, isEmpty);
      expect(capture.responses, isEmpty);
      expect(originConnections, 1);
    } finally {
      HostFilter.blacklist.load(saved);
    }
  });
}
