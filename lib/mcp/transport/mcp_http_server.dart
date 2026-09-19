/*
 * Copyright 2026 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:proxypin/network/util/logger.dart';

import '../protocol/json_rpc.dart';
import '../protocol/mcp_server.dart';

/// 仅绑定 loopback 的 MCP Streamable HTTP 传输（一期无状态，单 JSON 响应）。
///
/// @author wanghongen
class McpHttpServer {
  static const String path = '/mcp';

  final McpServer mcp;

  HttpServer? _server;

  McpHttpServer({required this.mcp});

  bool get isRunning => _server != null;

  int? get port => _server?.port;

  Future<void> start(int preferredPort) async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, preferredPort, shared: false);
    _server!.listen(_handle, onError: (e) => logger.e('MCP http server error: $e'));
    logger.i('MCP http server listening on 127.0.0.1:${_server!.port}');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  void _handle(HttpRequest req) async {
    try {
      if (req.method == 'GET' && req.uri.path == '/' ) {
        req.response.headers.contentType = ContentType.json;
        req.response.statusCode = HttpStatus.ok;
        req.response.write(jsonEncode({'service': 'proxypin-mcp', 'status': 'running'}));
        await req.response.close();
        return;
      }

      if (req.method != 'POST' || req.uri.path != path) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }

      var body = await req.cast<List<int>>().transform(utf8.decoder).join();
      Map<String, dynamic> message;
      try {
        var decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('expected JSON object');
        }
        message = decoded;
      } catch (e) {
        await _writeJson(req, JsonRpcResponse.error(null,
            JsonRpcError(JsonRpcError.parseError, 'Parse error: $e')), HttpStatus.badRequest);
        return;
      }

      var response = await mcp.handle(message);
      if (response == null) {
        // 通知：202 无响应体
        req.response.statusCode = HttpStatus.accepted;
        await req.response.close();
        return;
      }

      var accept = req.headers.value(HttpHeaders.acceptHeader) ?? '';
      if (accept.contains('text/event-stream') && !accept.contains('application/json')) {
        await _writeSse(req, response);
      } else {
        await _writeJson(req, response, HttpStatus.ok);
      }
    } catch (e, st) {
      logger.e('MCP request error', error: e, stackTrace: st);
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _writeJson(HttpRequest req, Map<String, dynamic> payload, int status) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.headers.set('MCP-Protocol-Version', McpServer.protocolVersion);
    req.response.write(jsonEncode(payload));
    await req.response.close();
  }

  Future<void> _writeSse(HttpRequest req, Map<String, dynamic> payload) async {
    req.response.statusCode = HttpStatus.ok;
    req.response.headers.contentType = ContentType.parse('text/event-stream');
    req.response.headers.set('Cache-Control', 'no-cache');
    req.response.write('event: message\ndata: ${jsonEncode(payload)}\n\n');
    await req.response.close();
  }
}
