import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/histories.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/utils/har.dart';

class WsTrafficServer implements EventListener {
  final int port;
  HttpServer? _server;
  final Set<WebSocket> _clients = {};
  String? _dataDir;

  WsTrafficServer({this.port = 12080});

  bool get isRunning => _server != null;

  int get clientCount => _clients.length;

  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind('127.0.0.1', port);
    _server!.listen((req) async {
      if (WebSocketTransformer.isUpgradeRequest(req)) {
        final ws = await WebSocketTransformer.upgrade(req);
        ws.pingInterval = const Duration(seconds: 30);
        _clients.add(ws);
        logger.i('WS traffic client connected, total: ${_clients.length}');
        _sendConfig(ws);
        ws.listen(
            (data) => _handleCommand(ws, data),
            onDone: () {
              _clients.remove(ws);
              logger.i('WS traffic client disconnected, total: ${_clients.length}');
            },
            onError: (_) {
              _clients.remove(ws);
              logger.i('WS traffic client error, total: ${_clients.length}');
            });
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

  Future<String> _getDataDir() async {
    _dataDir ??= (await getApplicationSupportDirectory()).path;
    return _dataDir!;
  }

  void _sendConfig(WebSocket ws) async {
    final appConfig = AppConfiguration.current;
    final historyEnabled = appConfig?.wsHistoryEnabled ?? false;
    final config = {
      'type': 'config',
      'data': {
        'historyEnabled': historyEnabled,
        if (historyEnabled) 'historyDir': await _getDataDir(),
      },
    };
    try { ws.add(jsonEncode(config)); } catch (_) {}
  }

  Future<void> broadcastConfig() async {
    for (final ws in Set.of(_clients)) {
      _sendConfig(ws);
    }
  }

  void _handleCommand(WebSocket ws, dynamic data) async {
    Map cmd;
    try {
      cmd = jsonDecode(data as String) as Map;
    } catch (_) {
      return;
    }
    final action = cmd['action'] as String?;
    final requestId = cmd['requestId'];

    void reply(Map payload) {
      try {
        ws.add(jsonEncode({'type': 'cmd_reply', 'requestId': requestId, ...payload}));
      } catch (_) {}
    }

    if (action == 'list_histories') {
      final storage = await HistoryStorage.instance;
      final list = storage.histories.reversed.map((h) => {
        'name': h.name,
        'request_count': h.requestLength,
        'file_size_kb': h.fileSize != null ? (h.fileSize! / 1024).round() : null,
        'create_time': h.createTime.toUtc().toIso8601String(),
      }).toList();
      reply({'action': action, 'data': list});
      return;
    }

    if (action == 'get_history') {
      final name = cmd['name'] as String?;
      final offset = (cmd['offset'] as num?)?.toInt() ?? 0;
      final limit = (cmd['limit'] as num?)?.toInt() ?? 10;
      final storage = await HistoryStorage.instance;
      final item = storage.histories.where((h) => h.name == name).firstOrNull;
      if (item == null) {
        reply({'action': action, 'error': 'session "$name" not found'});
        return;
      }
      final file = File(item.path);
      if (!await file.exists()) {
        reply({'action': action, 'error': 'file not found'});
        return;
      }
      final lines = (await file.readAsString()).split('\n');
      final summaries = <Map>[];
      for (final line in lines) {
        final trimmed = line.replaceAll(RegExp(r',\s*$'), '').trim();
        if (trimmed.isEmpty) continue;
        try {
          final har = jsonDecode(trimmed) as Map;
          final req = har['request'] as Map? ?? {};
          final resp = har['response'] as Map? ?? {};
          summaries.add({
            'id': har['_id'],
            'method': req['method'],
            'url': req['url'],
            'status': resp['status'],
            'time_ms': har['time'],
            'started': har['startedDateTime'],
          });
        } catch (_) {}
      }
      final page = summaries.skip(offset).take(limit).toList();
      reply({'action': action, 'name': name, 'total': summaries.length, 'offset': offset, 'limit': limit, 'requests': page});
      return;
    }

    if (action == 'search_history') {
      final keyword = (cmd['keyword'] as String? ?? '').toLowerCase();
      final method = (cmd['method'] as String? ?? '').toUpperCase();
      final statusCode = (cmd['status_code'] as num?)?.toInt() ?? 0;
      final limit = (cmd['limit'] as num?)?.toInt() ?? 10;
      final storage = await HistoryStorage.instance;
      final results = <Map>[];
      outer:
      for (final item in storage.histories.reversed) {
        final file = File(item.path);
        if (!await file.exists()) continue;
        for (final line in (await file.readAsString()).split('\n')) {
          final trimmed = line.replaceAll(RegExp(r',\s*$'), '').trim();
          if (trimmed.isEmpty) continue;
          try {
            final har = jsonDecode(trimmed) as Map;
            final req = har['request'] as Map? ?? {};
            final resp = har['response'] as Map? ?? {};
            final url = (req['url'] as String? ?? '').toLowerCase();
            final m = (req['method'] as String? ?? '').toUpperCase();
            final s = resp['status'] as int? ?? 0;
            if (keyword.isNotEmpty && !url.contains(keyword)) continue;
            if (method.isNotEmpty && m != method) continue;
            if (statusCode != 0 && s != statusCode) continue;
            results.add({
              'session': item.name,
              'id': har['_id'],
              'method': req['method'],
              'url': req['url'],
              'status': s,
              'time_ms': har['time'],
              'started': har['startedDateTime'],
            });
            if (results.length >= limit) break outer;
          } catch (_) {}
        }
      }
      reply({'action': action, 'count': results.length, 'requests': results});
      return;
    }

    if (action == 'get_history_detail') {
      final name = cmd['name'] as String?;
      final id = cmd['id'] as String?;
      final storage = await HistoryStorage.instance;
      final sessions = name != null
          ? storage.histories.where((h) => h.name == name)
          : storage.histories;
      for (final item in sessions) {
        final file = File(item.path);
        if (!await file.exists()) continue;
        for (final line in (await file.readAsString()).split('\n')) {
          final trimmed = line.replaceAll(RegExp(r',\s*$'), '').trim();
          if (trimmed.isEmpty) continue;
          try {
            final har = jsonDecode(trimmed) as Map;
            if (har['_id'] == id) {
              reply({'action': action, 'session': item.name, 'data': har});
              return;
            }
          } catch (_) {}
        }
      }
      reply({'action': action, 'error': 'request "$id" not found'});
      return;
    }
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
