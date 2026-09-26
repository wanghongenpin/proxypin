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
import 'history_provider.dart';

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

  /// 历史抓包数据源；为空时历史相关工具返回空 / 不可用
  final HistoryProvider? historyProvider;

  final LinkedHashMap<String, HttpRequest> _byId = LinkedHashMap();

  /// 每流的有界帧索引：不裁剪共享的 message.messages（App UI 也在用），
  /// 而是单独维护，避免影响界面展示。
  final Map<String, List<WebSocketFrame>> _wsFrames = {};

  /// 最多在内存中同时保留的历史会话数，超出淘汰最久未访问的，
  /// 与实时缓冲一样防止长时间运行 / 连续翻阅多个大会话导致内存膨胀。
  static const int defaultMaxHistorySessions = 3;

  /// 已加载的历史会话 LRU：稳定 history_id -> 该会话请求列表（由 [historyProvider] 懒加载）。
  /// 用 LinkedHashMap 记录访问顺序，访问时移到末尾、从头部淘汰。
  final LinkedHashMap<int, List<HttpRequest>> _historyCache = LinkedHashMap();

  final int maxHistorySessions;

  FlowStore(
      {this.maxEntries = defaultMaxEntries,
      this.maxFramesPerFlow = defaultMaxFramesPerFlow,
      this.historyProvider,
      this.maxHistorySessions = defaultMaxHistorySessions});

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
    _historyCache.clear();
  }

  int get count => _byId.length;

  HttpRequest? getById(String id) => _byId[id];

  // ------------------------------------------------------------- history

  /// 全部历史会话元数据；未配置历史数据源时返回空。
  Future<List<HistoryMeta>> listHistories() async => await historyProvider?.list() ?? const [];

  Future<List<HttpRequest>> _historyRequests(int historyId) async {
    var cached = _historyCache.remove(historyId);
    if (cached != null) {
      // 命中则标记为最近使用（移到末尾）
      _historyCache[historyId] = cached;
      return cached;
    }
    var provider = historyProvider;
    if (provider == null) throw ArgumentError('history not found: $historyId');
    var metas = await provider.list();
    if (!metas.any((m) => m.id == historyId)) {
      throw ArgumentError('history not found: $historyId');
    }
    var requests = await provider.requests(historyId);
    _historyCache[historyId] = requests;
    _evictHistoryIfNeeded();
    return requests;
  }

  /// 历史会话缓存超限时淘汰最久未访问的（LinkedHashMap 头部）。
  void _evictHistoryIfNeeded() {
    while (_historyCache.length > maxHistorySessions) {
      _historyCache.remove(_historyCache.keys.first);
    }
  }

  Future<HttpRequest?> historyGetById(int historyId, String id) async {
    var requests = await _historyRequests(historyId);
    for (var request in requests) {
      if (request.requestId == id) return request;
    }
    return null;
  }

  Future<List<HttpRequest>> historyQuery(
    int historyId, {
    int limit = 20,
    int offset = 0,
    String? host,
    String? method,
    int? statusFrom,
    int? statusTo,
    String? keyword,
    int? sinceMs,
  }) async {
    var requests = await _historyRequests(historyId);
    return _filter(requests,
        limit: limit,
        offset: offset,
        host: host,
        method: method,
        statusFrom: statusFrom,
        statusTo: statusTo,
        keyword: keyword,
        sinceMs: sinceMs);
  }

  Future<List<HttpRequest>> historySearch(int historyId, String keyword,
      {String side = 'both', int limit = 20, int maxSearchBytes = 2 * 1024 * 1024}) async {
    var requests = await _historyRequests(historyId);
    return await _searchIn(requests, keyword, side: side, limit: limit, maxSearchBytes: maxSearchBytes);
  }

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
    return _filter(_byId.values.toList(growable: false),
        limit: limit,
        offset: offset,
        host: host,
        method: method,
        statusFrom: statusFrom,
        statusTo: statusTo,
        keyword: keyword,
        sinceMs: sinceMs);
  }

  /// 在给定请求集合上按条件过滤，按时间倒序（最新在前）返回，应用 limit/offset。
  /// 实时缓冲与历史会话共用，保证两处过滤口径一致。
  List<HttpRequest> _filter(
    List<HttpRequest> source, {
    required int limit,
    required int offset,
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
    for (var i = source.length - 1; i >= 0; i--) {
      var request = source[i];
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
    return await _searchIn(_byId.values.toList(growable: false), keyword,
        side: side, limit: limit, maxSearchBytes: maxSearchBytes);
  }

  /// 在给定请求集合上做 body 子串搜索，实时缓冲与历史会话共用同一口径。
  Future<List<HttpRequest>> _searchIn(List<HttpRequest> source, String keyword,
      {required String side, required int limit, required int maxSearchBytes}) async {
    keyword = keyword.toLowerCase();
    if (keyword.isEmpty) return const [];
    limit = limit.clamp(1, 100);
    var matched = <HttpRequest>[];

    for (var i = source.length - 1; i >= 0; i--) {
      if (matched.length >= limit) break;
      var request = source[i];
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
