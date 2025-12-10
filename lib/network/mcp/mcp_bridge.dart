import 'dart:convert';

import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/utils/listenable_list.dart';

/// MCP 数据桥接，负责从 ProxyPin 收集流量并提供给 MCP Server
class McpBridge implements EventListener {
  static final McpBridge _instance = McpBridge._internal();

  factory McpBridge() => _instance;

  McpBridge._internal();

  /// 主程序的请求容器（由外部设置，避免重复存储）
  ListenableList<HttpRequest>? _requestContainer;

  /// 设置请求容器（从主程序传入）
  void setRequestContainer(ListenableList<HttpRequest> container) {
    _requestContainer = container;
  }

  // 这里可以添加回调，当有新请求时通知 McpServer 推送 SSE
  Function(HttpRequest)? onNewRequest;
  
  // UI清除回调（由主程序设置，对应垃圾桶图标的清除功能）
  Function()? onClearUI;

  /// 获取最近的请求列表（增强版过滤）
  List<HttpRequest> getRecentRequests({
    int limit = 20, 
    String? urlFilter, 
    String? method, 
    String? statusCode,
    String? domain,
    int? minDuration,
    int? maxDuration,
    String? headerSearch,      // 新增：搜索 header（key 或 value）
    String? requestBodySearch, // 新增：搜索请求 body
    String? responseBodySearch, // 新增：搜索响应 body
  }) {
    if (_requestContainer == null) return [];
    
    var requests = _requestContainer!.source.toList();
    
    // URL 过滤（支持大小写不敏感）
    if (urlFilter != null && urlFilter.isNotEmpty) {
      requests = requests.where((req) => 
        req.requestUrl.toLowerCase().contains(urlFilter.toLowerCase())
      ).toList();
    }
    
    // HTTP 方法过滤
    if (method != null && method.isNotEmpty) {
      requests = requests.where((req) => 
        req.method.name.toUpperCase() == method.toUpperCase()
      ).toList();
    }
    
    // 状态码过滤（支持精确匹配如 "200"，也支持范围如 "2xx"）
    if (statusCode != null && statusCode.isNotEmpty) {
      requests = requests.where((req) {
        if (req.response == null) return false;
        var code = req.response!.status.code;
        
        // 支持范围查询：2xx, 3xx, 4xx, 5xx
        if (statusCode.endsWith('xx')) {
          var prefix = int.tryParse(statusCode.substring(0, 1));
          if (prefix != null) {
            return code >= prefix * 100 && code < (prefix + 1) * 100;
          }
        }
        
        // 精确匹配：200, 404, 500 等
        return code.toString() == statusCode;
      }).toList();
    }
    
    // 域名过滤
    if (domain != null && domain.isNotEmpty) {
      requests = requests.where((req) {
        try {
          var uri = Uri.parse(req.requestUrl);
          return uri.host.toLowerCase().contains(domain.toLowerCase());
        } catch (e) {
          return false;
        }
      }).toList();
    }
    
    // Header 搜索（搜索请求和响应的 header）
    if (headerSearch != null && headerSearch.isNotEmpty) {
      var searchLower = headerSearch.toLowerCase();
      requests = requests.where((req) {
        // 搜索请求 headers
        var reqMatch = req.headers.toMap().entries.any((entry) =>
          entry.key.toLowerCase().contains(searchLower) ||
          entry.value.toLowerCase().contains(searchLower)
        );
        if (reqMatch) return true;
        
        // 搜索响应 headers
        if (req.response != null) {
          return req.response!.headers.toMap().entries.any((entry) =>
            entry.key.toLowerCase().contains(searchLower) ||
            entry.value.toLowerCase().contains(searchLower)
          );
        }
        return false;
      }).toList();
    }
    
    // 请求 Body 搜索
    if (requestBodySearch != null && requestBodySearch.isNotEmpty) {
      var searchLower = requestBodySearch.toLowerCase();
      requests = requests.where((req) {
        if (req.body == null) return false;
        try {
          var bodyStr = utf8.decode(req.body!, allowMalformed: true);
          return bodyStr.toLowerCase().contains(searchLower);
        } catch (e) {
          return false;
        }
      }).toList();
    }
    
    // 响应 Body 搜索
    if (responseBodySearch != null && responseBodySearch.isNotEmpty) {
      var searchLower = responseBodySearch.toLowerCase();
      requests = requests.where((req) {
        if (req.response?.body == null) return false;
        try {
          var bodyStr = utf8.decode(req.response!.body!, allowMalformed: true);
          return bodyStr.toLowerCase().contains(searchLower);
        } catch (e) {
          return false;
        }
      }).toList();
    }
    
    // 耗时过滤
    if (minDuration != null || maxDuration != null) {
      requests = requests.where((req) {
        if (req.response == null) return false;
        var duration = req.response!.responseTime.difference(req.requestTime).inMilliseconds;
        if (minDuration != null && duration < minDuration) return false;
        if (maxDuration != null && duration > maxDuration) return false;
        return true;
      }).toList();
    }
    
    // 按时间倒序（最新的在前）
    requests.sort((a, b) => b.requestTime.compareTo(a.requestTime));
    
    return requests.take(limit).toList();
  }
  
  /// 根据 ID 获取请求详情
  HttpRequest? getRequestById(String id) {
    if (_requestContainer == null) return null;
    try {
      return _requestContainer!.source.firstWhere((req) => req.requestId == id);
    } catch (e) {
      return null;
    }
  }

  /// 获取当前存储的请求总数
  int get totalCount => _requestContainer?.length ?? 0;
  
  /// 清空所有请求（对应垃圾桶按钮）
  void clear() {
    _requestContainer?.clear();
  }
  
  /// 通过UI清除（调用真正的UI清除方法）
  bool clearWithUI() {
    if (onClearUI != null) {
      try {
        onClearUI!();
        return true;
      } catch (e) {
        logger.e('Failed to call UI clear callback: $e');
        return false;
      }
    }
    return false;
  }
  
  /// 清理早期数据，保留最新的 N 条（内存优化）
  void cleanupEarlyData(int retain) {
    if (_requestContainer == null) return;
    var list = _requestContainer!.source;
    if (list.length <= retain) return;
    
    _requestContainer!.removeRange(0, list.length - retain);
  }
  
  /// 获取请求统计信息
  Map<String, dynamic> getStatistics() {
    if (_requestContainer == null) return {};
    
    var requests = _requestContainer!.source;
    var methodCount = <String, int>{};
    var statusCount = <String, int>{};
    var domainCount = <String, int>{};
    var totalSize = 0;
    var totalDuration = 0;
    var errorCount = 0;
    
    for (var req in requests) {
      // 方法统计
      methodCount[req.method.name] = (methodCount[req.method.name] ?? 0) + 1;
      
      // 状态码统计
      if (req.response != null) {
        var code = req.response!.status.code;
        var codeGroup = '${code ~/ 100}xx';
        statusCount[codeGroup] = (statusCount[codeGroup] ?? 0) + 1;
        
        if (code >= 400) errorCount++;
        
        // 大小统计
        totalSize += (req.body?.length ?? 0) + (req.response!.body?.length ?? 0);
        
        // 耗时统计
        totalDuration += req.response!.responseTime.difference(req.requestTime).inMilliseconds;
      }
      
      // 域名统计
      try {
        var uri = Uri.parse(req.requestUrl);
        var domain = uri.host;
        domainCount[domain] = (domainCount[domain] ?? 0) + 1;
      } catch (e) {
        // ignore
      }
    }
    
    return {
      'total': requests.length,
      'methods': methodCount,
      'statusCodes': statusCount,
      'domains': domainCount,
      'totalSize': totalSize,
      'averageDuration': requests.isEmpty ? 0 : totalDuration ~/ requests.length,
      'errorCount': errorCount,
    };
  }

  @override
  void onRequest(Channel channel, HttpRequest request) {
    // MCP不需要在这里处理，主程序已经添加到容器了
    // 只需要通知回调即可
  }

  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) {
    final request = response.request;
    if (request == null) return;
    
    // 通知有新的响应（可用于SSE推送）
    onNewRequest?.call(request);
  }

  @override
  void onMessage(Channel channel, HttpMessage message, WebSocketFrame frame) {
    // 暂不处理 WebSocket, TODO: 后续支持WebSocket
  }

  /// 辅助方法：将 HttpRequest 转换为 JSON（用于 MCP 响应）
  static Map<String, dynamic> requestToJson(HttpRequest request, {bool includeBody = false}) {
    return {
      'id': request.requestId,
      'url': request.requestUrl,
      'method': request.method.name,
      'timestamp': request.requestTime.toIso8601String(),
      'statusCode': request.response?.status.code,
      'duration': request.response?.responseTime.difference(request.requestTime).inMilliseconds,
      if (includeBody) ...{
        'request': {
          'headers': request.headers.toMap(),
          ..._encodeBodyWithMetadata(request.body),
        },
        'response': {
          'statusCode': request.response?.status.code,
          'statusText': request.response?.status.reasonPhrase,
          'headers': request.response?.headers.toMap(),
          ..._encodeBodyWithMetadata(request.response?.body),
        },
      },
    };
  }
  
  /// 编码 body 并返回元数据（包含编码类型、大小、内容）
  static Map<String, dynamic> _encodeBodyWithMetadata(List<int>? body) {
    if (body == null || body.isEmpty) {
      return {
        'body': null,
        'bodySize': 0,
        'bodyEncoding': 'none',
      };
    }
    
    try {
      // 尝试 UTF-8 解码
      var text = utf8.decode(body, allowMalformed: false);
      return {
        'body': text,
        'bodySize': body.length,
        'bodyEncoding': 'utf8',
      };
    } catch (e) {
      // 解码失败，说明是二进制数据，用 Base64 编码
      return {
        'body': base64Encode(body),
        'bodySize': body.length,
        'bodyEncoding': 'base64',
      };
    }
  }
}

