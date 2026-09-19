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

import 'dart:collection';

import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';

import 'flow_view.dart';

/// MCP 抓包数据索引。
///
/// 通过注册到 [ProxyServer.listeners] 以 [EventListener] 身份接收全部流量，
/// 维护 requestId -> [HttpRequest] 的有界缓存，平台无关、不依赖 UI 容器。
/// 仅保留最近 [maxEntries] 条，超出后丢弃最旧的，避免长时间运行导致内存膨胀。
///
/// @author wanghongen
class FlowStore extends EventListener {
  /// 默认保留最近的抓包条数
  static const int defaultMaxEntries = 1000;

  /// 单条流最多保留的 WebSocket/SSE 帧数，超出丢弃最旧的，防止长连接无限累积内存
  static const int defaultMaxFramesPerFlow = 5000;

  final int maxEntries;
  final int maxFramesPerFlow;

  final LinkedHashMap<String, HttpRequest> _byId = LinkedHashMap();

  /// 每流的有界帧索引：不裁剪共享的 message.messages（App UI 也在用），
  /// 而是单独维护，避免影响界面展示。
  final Map<String, List<WebSocketFrame>> _wsFrames = {};

  FlowStore({this.maxEntries = defaultMaxEntries, this.maxFramesPerFlow = defaultMaxFramesPerFlow});

  @override
  void onRequest(Channel channel, HttpRequest request) {
    _put(request);
  }

  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) {
    var request = response.request;
    if (request != null) {
      // 响应到达，回填同一请求对象（response 已挂载），保持其在缓存中的位置不变
      _byId[request.requestId] = request;
    }
  }

  @override
  void onMessage(Channel channel, HttpMessage message, WebSocketFrame frame) {
    var id = message.requestId;
    var list = _wsFrames.putIfAbsent(id, () => []);
    list.add(frame);
    if (list.length > maxFramesPerFlow) {
      list.removeRange(0, list.length - maxFramesPerFlow);
    }
  }

  /// 某条流的帧（有界，不含被淘汰的最旧帧）
  List<WebSocketFrame> frames(String id) => _wsFrames[id] ?? const [];

  void _put(HttpRequest request) {
    // 已存在则先移除，保证刷新后位于最新位置
    _byId.remove(request.requestId);
    _byId[request.requestId] = request;
    _evictIfNeeded();
  }

  void _evictIfNeeded() {
    while (_byId.length > maxEntries) {
      var evicted = _byId.remove(_byId.keys.first);
      if (evicted != null) _wsFrames.remove(evicted.requestId);
    }
  }

  /// 启用时一次性回填已抓到的请求（来自现有 UI 容器）
  void backfill(Iterable<HttpRequest> requests) {
    for (var request in requests) {
      _byId[request.requestId] = request;
    }
    _evictIfNeeded();
  }

  void clear() {
    _byId.clear();
    _wsFrames.clear();
  }

  int get count => _byId.length;

  HttpRequest? getById(String id) => _byId[id];

  /// 按条件查询抓包，按时间倒序（最新在前）返回，应用 limit/offset。
  List<HttpRequest> query({
    int limit = 20,
    int offset = 0,
    String? host,
    String? method,
    int? statusFrom,
    int? statusTo,
    String? keyword,
    int? sinceMs,
  }) {
    limit = limit.clamp(1, 100);
    offset = offset < 0 ? 0 : offset;

    var hostLower = host?.toLowerCase();
    var methodUpper = method?.toUpperCase();
    var keywordLower = keyword?.toLowerCase();
    var matched = <HttpRequest>[];

    // 倒序遍历
    var entries = _byId.values.toList(growable: false);
    for (var i = entries.length - 1; i >= 0; i--) {
      var request = entries[i];
      if (!_matches(request, hostLower, methodUpper, statusFrom, statusTo, keywordLower, sinceMs)) {
        continue;
      }
      matched.add(request);
    }

    if (offset >= matched.length) {
      return const [];
    }
    var end = (offset + limit).clamp(0, matched.length);
    return matched.sublist(offset, end);
  }

  /// 在请求/响应 body 中做子串搜索（大小写不敏感）。
  ///
  /// 仅搜索文本报文：二进制（图片/音视频/压缩/加密等）与超过 [maxSearchBytes] 的大 body
  /// 会跳过，避免解码与扫描大对象拖慢搜索。返回最新在前的匹配，最多 [limit] 条。
  Future<List<HttpRequest>> search(String keyword,
      {String side = 'both', int limit = 20, int maxSearchBytes = 2 * 1024 * 1024}) async {
    keyword = keyword.toLowerCase();
    if (keyword.isEmpty) return const [];
    limit = limit.clamp(1, 100);
    var matched = <HttpRequest>[];
    var entries = _byId.values.toList(growable: false);

    for (var i = entries.length - 1; i >= 0; i--) {
      if (matched.length >= limit) break;
      var request = entries[i];
      var hit = false;
      if (side != 'response' && await _bodyContains(request, keyword, maxSearchBytes, requestSide: true)) {
        hit = true;
      }
      if (!hit && side != 'request' && await _bodyContains(request, keyword, maxSearchBytes, requestSide: false)) {
        hit = true;
      }
      if (hit) matched.add(request);
    }
    return matched;
  }

  Future<bool> _bodyContains(HttpRequest request, String keyword, int maxSearchBytes,
      {required bool requestSide}) async {
    var message = requestSide ? request : request.response;
    if (message == null || FlowView.isBinary(message)) return false;
    var body = message.body;
    if (body == null || body.isEmpty || body.length > maxSearchBytes) return false;
    try {
      return (await message.decodeBodyString()).toLowerCase().contains(keyword);
    } catch (_) {
      return false;
    }
  }

  bool _matches(HttpRequest request, String? host, String? method, int? statusFrom, int? statusTo,
      String? keyword, int? sinceMs) {
    if (method != null && method.isNotEmpty && request.method.name.toUpperCase() != method) {
      return false;
    }

    if (host != null && host.isNotEmpty) {
      var reqHost = request.requestUri?.host.toLowerCase() ?? request.remoteDomain()?.toLowerCase() ?? '';
      if (!reqHost.contains(host)) {
        return false;
      }
    }

    var status = request.response?.status.code ?? 0;
    if (statusFrom != null && status < statusFrom) {
      return false;
    }
    if (statusTo != null && status > statusTo) {
      return false;
    }

    if (sinceMs != null && request.requestTime.millisecondsSinceEpoch < sinceMs) {
      return false;
    }

    if (keyword != null && keyword.isNotEmpty) {
      var haystack = request.requestUrl.toLowerCase();
      if (!haystack.contains(keyword)) {
        return false;
      }
    }
    return true;
  }
}
