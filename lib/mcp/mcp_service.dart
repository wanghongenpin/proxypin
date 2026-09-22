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

import 'dart:io';
import 'dart:math';

import 'package:proxypin/mcp/capture/cert_status.dart';
import 'package:proxypin/mcp/capture/flow_store.dart';
import 'package:proxypin/mcp/protocol/mcp_actions.dart';
import 'package:proxypin/mcp/protocol/mcp_server.dart';
import 'package:proxypin/mcp/transport/mcp_http_server.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/configuration.dart';

/// MCP 服务编排：挂载抓包索引、启停本地 HTTP 传输。
///
/// 作为 [EventListener] 挂到 [ProxyServer.listeners]，与 UI 同源接收流量，
/// 因而平台无关且不依赖具体列表容器。桌面端仅绑定 127.0.0.1、固定 [defaultPort]
/// （被占用时回退到系统随机端口），本机即信任边界，不做鉴权；AI 客户端直接以 HTTP 连接，
/// 无需额外桥进程。
///
/// @author wanghongen
class McpService {
  static final McpService instance = McpService._();

  McpService._();

  /// 桌面端默认监听端口；被占用时回退到系统分配的空闲端口。
  static const int defaultPort = 9127;

  FlowStore? _store;
  McpServer? _mcp;
  McpHttpServer? _http;
  ProxyServer? _attachedServer;

  /// 串行化 start/stop，避免自动启动与手动开关并发时重复 bind 端口
  Future<void>? _transitionLock;

  Future<void> _synchronized(Future<void> Function() action) {
    var previous = _transitionLock ?? Future<void>.value();
    var next = previous.then((_) => action());
    // 单次失败不能让后续操作永远拿不到锁
    _transitionLock = next.catchError((_) {});
    return next;
  }

  /// 由 UI 层注册：清空界面抓包列表（MCP clear_session 时一并触发）
  Future<void> Function()? clearUiSession;

  bool get isRunning => _http?.isRunning ?? false;

  int? get port => _http?.port;

  /// 移动端 LAN 模式的访问 token；桌面 loopback 模式为 null
  String? get token => _http?.token;

  /// 当前绑定地址：移动端 0.0.0.0（LAN），桌面 127.0.0.1
  bool get lanMode => Platform.isAndroid || Platform.isIOS;

  /// 生成 48 位十六进制随机 token
  static String generateToken() {
    var random = Random.secure();
    return List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

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

  /// 按当前配置启动（必要时先挂到已存在的代理服务）。串行执行，避免并发重复绑定。
  Future<void> start(AppConfiguration cfg) => _synchronized(() => _startLocked(cfg));

  Future<void> _startLocked(AppConfiguration cfg) async {
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
      redactEnabled: () => cfg.mcpRedactEnabled,
    );
    _mcp = McpServer(
      store: _store!,
      redactEnabled: () => cfg.mcpRedactEnabled,
      extraTools: actions.tools(),
    );
    // 移动端绑 0.0.0.0 供局域网 AI 客户端连接，并要求 Bearer token；桌面仅 loopback。
    String? token;
    InternetAddress bindAddress = InternetAddress.loopbackIPv4;
    if (lanMode) {
      bindAddress = InternetAddress.anyIPv4;
      token = (cfg.mcpToken?.isNotEmpty ?? false) ? cfg.mcpToken : generateToken();
      cfg.mcpToken = token;
    }
    _http = McpHttpServer(mcp: _mcp!, address: bindAddress, token: token);

    try {
      if (lanMode) {
        // 移动端仍由系统分配端口（配合 token 供局域网连接）。
        await _http!.start(0);
      } else {
        // 桌面优先固定端口，便于 AI 客户端直接配置 URL；被占用时回退随机端口。
        try {
          await _http!.start(defaultPort);
        } on SocketException catch (e) {
          logger.w('MCP port $defaultPort unavailable, falling back to a random port: $e');
          await _http!.start(0);
        }
      }
      logger.i('MCP service started on 127.0.0.1:${_http!.port}');
    } catch (e) {
      logger.e('MCP service start failed: $e');
      _http = null;
      rethrow;
    }
  }

  Future<void> stop() => _synchronized(_stopLocked);

  Future<void> _stopLocked() async {
    await _http?.stop();
    _http = null;
    _mcp = null;
    // 解绑抓包监听并清空索引：关闭后不再缓冲流量，避免停用期间抓到的敏感请求
    // 在下次开启时被局域网客户端读到；同时避免 start/stop 反复切换造成监听器堆积。
    if (_store != null) {
      _attachedServer?.removeListener(_store!);
      _store!.clear();
    }
  }
}
