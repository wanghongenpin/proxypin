import 'dart:convert';
import 'dart:io';

import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/utils/har.dart';

class WsTrafficServer implements EventListener {
  final int port;
  HttpServer? _server;
  final Set<WebSocket> _clients = {};

  WsTrafficServer({this.port = 12080});

  bool get isRunning => _server != null;

  int get clientCount => _clients.length;

  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind('127.0.0.1', port);
    _server!.listen((req) async {
      if (WebSocketTransformer.isUpgradeRequest(req)) {
        final ws = await WebSocketTransformer.upgrade(req);
        _clients.add(ws);
        logger.i('WS traffic client connected, total: ${_clients.length}');
        ws.listen(null,
            onDone: () => _clients.remove(ws),
            onError: (_) => _clients.remove(ws));
      } else {
        req.response.statusCode = 403;
        req.response.close();
      }
    });
    logger.i('WS traffic server started on port $port');
  }

  Future<void> stop() async {
    for (final ws in Set.of(_clients)) {
      try {
        await ws.close();
      } catch (_) {}
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
    logger.i('WS traffic server stopped');
  }

  void _broadcast(Map msg) {
    if (_clients.isEmpty) return;
    final data = jsonEncode(msg);
    for (final ws in Set.of(_clients)) {
      try {
        ws.add(data);
      } catch (_) {
        _clients.remove(ws);
      }
    }
  }

  @override
  void onRequest(Channel channel, HttpRequest request) {
    _broadcast({
      'type': 'request',
      'id': request.requestId,
      'data': {
        'method': request.method.name,
        'uri': request.requestUrl,
        'headers': request.headers.toJson(),
        'body': request.bodyAsString,
        'requestTime': request.requestTime.millisecondsSinceEpoch,
      },
    });
  }

  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) {
    final req = response.request;
    if (req == null) return;
    _broadcast({
      'type': 'response',
      'id': req.requestId,
      'data': Har.toHar(req),
    });
  }

  @override
  void onMessage(Channel channel, HttpMessage message, WebSocketFrame frame) {
    _broadcast({
      'type': 'ws_message',
      'id': message.requestId,
      'data': {
        'opcode': frame.opcode,
        'isFromClient': frame.isFromClient,
        'payloadLength': frame.payloadLength,
        'text': frame.payloadDataAsString,
        'time': frame.time.millisecondsSinceEpoch,
      },
    });
  }
}
