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

import '../protocol/json_rpc.dart';

/// `--mcp-stdio` 瘦转发进程：stdin/stdout 换行分隔 JSON-RPC，透传到 App 内 HTTP bridge。
///
/// 该进程与正在运行的 GUI 不共享内存，因此只做协议转发；App 未运行或未开启 MCP 时
/// 返回友好的 JSON-RPC 错误。bridge 仅绑定 127.0.0.1，本机即信任边界，不做鉴权。
///
/// @author wanghongen
class McpStdioBridge {
  static const String defaultPath = '/mcp';
  static const int defaultPort = 9127;

  final int port;

  HttpClient? _client;
  bool _closed = false;

  McpStdioBridge({required this.port});

  /// 握手文件：App 启动 MCP 服务后写入实际端口，桥进程启动时读取。
  static File handshakeFile() {
    var home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    return File('$home${Platform.pathSeparator}.proxypin${Platform.pathSeparator}mcp_handshake.json');
  }

  /// 从命令行参数、握手文件与 ui_config.json 解析端口并运行（握手文件优先）。
  static Future<void> run(List<String> args) async {
    var config = await _readUiConfig();
    int? port = await _readHandshakePort();
    port ??= int.tryParse(_flagValue(args, '--mcp-port') ?? '');
    port ??= config?['mcpPort'] is int ? config!['mcpPort'] as int : defaultPort;

    final bridge = McpStdioBridge(port: port);
    await bridge.listen();
  }

  static Future<int?> _readHandshakePort() async {
    try {
      var file = handshakeFile();
      if (!await file.exists()) return null;
      var decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded['port'] as int? : null;
    } catch (e) {
      stderr.writeln('MCP stdio read handshake failed: $e');
      return null;
    }
  }

  Future<void> listen() async {
    _client = HttpClient()..findProxy = (uri) => 'DIRECT';

    stdin.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) async {
        if (line.trim().isEmpty) return;
        await _forward(line);
      },
      onDone: () => _closed = true,
      onError: (e) => stderr.writeln('MCP stdio read error: $e'),
    );
  }

  Future<void> _forward(String line) async {
    Map<String, dynamic>? message;
    Object? id;
    try {
      var decoded = jsonDecode(line);
      if (decoded is Map<String, dynamic>) {
        message = decoded;
        id = decoded['id'];
      }
    } catch (_) {}

    if (message == null) {
      _emit(JsonRpcResponse.error(
          null, JsonRpcError(JsonRpcError.parseError, 'Parse error: expected a JSON-RPC object')));
      return;
    }

    // 通知（无 id）失败时无需回应
    try {
      var request = await _client!.postUrl(Uri.parse('http://127.0.0.1:$port$defaultPath'));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(line);
      var response = await request.close().timeout(const Duration(seconds: 60));
      var text = await response.transform(utf8.decoder).join();
      if (text.trim().isNotEmpty) {
        stdout.writeln(text);
      }
    } catch (e) {
      if (id != null) {
        _emit(JsonRpcResponse.error(
            id,
            JsonRpcError(-32000,
                'Cannot reach ProxyPin MCP bridge at 127.0.0.1:$port. Please open the desktop app and enable the MCP service. ($e)')));
      }
    }
  }

  void _emit(Map<String, dynamic> payload) {
    if (!_closed) stdout.writeln(jsonEncode(payload));
  }

  static String? _flagValue(List<String> args, String name) {
    var idx = args.indexOf(name);
    if (idx == -1 || idx + 1 >= args.length) return null;
    return args[idx + 1];
  }

  static Future<Map<String, dynamic>?> _readUiConfig() async {
    try {
      var home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home == null) return null;
      var file = File('$home${Platform.pathSeparator}.proxypin${Platform.pathSeparator}ui_config.json');
      if (!await file.exists()) return null;
      var content = await file.readAsString();
      if (content.trim().isEmpty) return null;
      var decoded = jsonDecode(content);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      stderr.writeln('MCP stdio read ui_config failed: $e');
      return null;
    }
  }
}
