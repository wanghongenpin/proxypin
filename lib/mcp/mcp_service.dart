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

import 'dart:convert';
import 'dart:io';

import 'package:proxypin/mcp/capture/cert_status.dart';
import 'package:proxypin/mcp/capture/flow_store.dart';
import 'package:proxypin/mcp/protocol/mcp_actions.dart';
import 'package:proxypin/mcp/protocol/mcp_server.dart';
import 'package:proxypin/mcp/transport/mcp_http_server.dart';
import 'package:proxypin/mcp/transport/mcp_stdio_bridge.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/configuration.dart';

/// MCP 服务编排：挂载抓包索引、启停本地 HTTP 传输。
///
/// 作为 [EventListener] 挂到 [ProxyServer.listeners]，与 UI 同源接收流量，
/// 因而平台无关且不依赖具体列表容器。仅绑定 127.0.0.1，本机即信任边界，不做鉴权。
///
/// @author wanghongen
class McpService {
  static final McpService instance = McpService._();

  McpService._();

  FlowStore? _store;
  McpServer? _mcp;
  McpHttpServer? _http;
  ProxyServer? _attachedServer;

  /// 由 UI 层注册：清空界面抓包列表（MCP clear_session 时一并触发）
  Future<void> Function()? clearUiSession;

  bool get isRunning => _http?.isRunning ?? false;

  int? get port => _http?.port;

  /// 注册抓包索引到代理服务（幂等）。[existing] 用于启用时一次性回填已抓到的请求。
  void attach(ProxyServer server, {Iterable<HttpRequest>? existing}) {
    _store ??= FlowStore();
    _attachedServer = server;
    if (!server.listeners.contains(_store)) {
      server.addListener(_store!);
    }
    if (existing != null && existing.isNotEmpty) {
      _store!.backfill(existing);
    }
  }

  /// 按当前配置启动（必要时先挂到已存在的代理服务）。
  Future<void> start(AppConfiguration cfg) async {
    if (isRunning) return;

    var proxyServer = _attachedServer ?? ProxyServer.current;
    if (proxyServer != null) {
      attach(proxyServer);
    }
    _store ??= FlowStore();

    var actions = McpActions(
      store: _store!,
      onClearSession: () async => clearUiSession?.call(),
      certStatusProvider: Platform.isMacOS || Platform.isWindows || Platform.isLinux ? CertStatus.query : null,
    );
    _mcp = McpServer(
      store: _store!,
      redactEnabled: () => cfg.mcpRedactEnabled,
      extraTools: actions.tools(),
    );
    _http = McpHttpServer(mcp: _mcp!);

    try {
      // 自动分配空闲端口，避免与其它服务冲突；实际端口写入握手文件供 stdio 桥发现。
      await _http!.start(0);
      await _writeHandshake();
      logger.i('MCP service started on 127.0.0.1:${_http!.port}');
    } catch (e) {
      logger.e('MCP service start failed: $e');
      _http = null;
      rethrow;
    }
  }

  Future<void> stop() async {
    await _removeHandshake();
    await _http?.stop();
    _http = null;
    _mcp = null;
  }

  /// 握手文件：stdio 桥进程不共享内存，通过该文件发现当前端口。
  Future<void> _writeHandshake() async {
    var file = McpStdioBridge.handshakeFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'port': _http!.port}));
  }

  Future<void> _removeHandshake() async {
    try {
      var file = McpStdioBridge.handshakeFile();
      if (await file.exists()) await file.delete();
    } catch (e) {
      logger.e('MCP handshake cleanup failed: $e');
    }
  }
}
