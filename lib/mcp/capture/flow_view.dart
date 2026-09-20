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
import 'dart:typed_data';

import 'package:proxypin/mcp/capture/sensitive_data.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/util/crypto.dart';

/// 抓包数据的精简序列化层 —— MCP 与未来内嵌 AI 的唯一数据出口。
///
/// 统一负责：
///  - 列表只给元数据（零 body）；
///  - body 默认预览、按需分页、服务端硬上限；
///  - 二进制只描述（mime/size/sha256），绝不内联原文或 base64；
///  - 默认脱敏 Authorization/Cookie 等敏感头。
///
/// @author wanghongen
class FlowView {
  /// body 预览默认字节数
  static const int defaultPreviewBytes = 8 * 1024;

  /// 单次 body 分页硬上限
  static const int maxBodySliceBytes = 64 * 1024;

  /// WebSocket 帧最多返回条数
  static const int maxWsFrames = 200;

  /// WebSocket 帧文本总量上限
  static const int maxWsPayloadBytes = 1024 * 1024;


  /// 列表项元数据（不含 headers/body）
  static Map<String, dynamic> summary(HttpRequest request) {
    var response = request.response;
    var durationMs = response == null
        ? -1
        : response.responseTime.difference(request.requestTime).inMilliseconds;
    return {
      'id': request.requestId,
      'method': request.method.name,
      'url': request.requestUrl,
      'host': request.requestUri?.host ?? request.remoteDomain() ?? '',
      'path': request.pathAndQuery,
      'status': response?.status.code ?? 0,
      'requestMime': _mime(request),
      'responseMime': _mime(response),
      'requestSize': request.body?.length ?? 0,
      'responseSize': response?.body?.length ?? 0,
      'durationMs': durationMs,
      'time': request.requestTime.toUtc().toIso8601String(),
      'websocket': request.isWebSocket || (response?.isWebSocket ?? false),
    };
  }

  /// 单条详情：完整（脱敏后）头 + query + 请求/响应 body 预览
  static Future<Map<String, dynamic>> detail(HttpRequest request,
      {bool redact = true, int previewBytes = defaultPreviewBytes}) async {
    var response = request.response;
    return {
      'id': request.requestId,
      'method': request.method.name,
      'url': request.requestUrl,
      'httpVersion': request.protocolVersion,
      'time': request.requestTime.toUtc().toIso8601String(),
      'durationMs': response == null
          ? -1
          : response.responseTime.difference(request.requestTime).inMilliseconds,
      'request': {
        'headers': _headers(request, redact),
        'query': request.queries,
        'mimeType': _mime(request),
        'body': await _bodyPreview(request, previewBytes),
      },
      'response': response == null
          ? null
          : {
              'status': response.status.code,
              'statusText': response.status.reasonPhrase,
              'httpVersion': response.protocolVersion,
              'headers': _headers(response, redact),
              'mimeType': _mime(response),
              'body': await _bodyPreview(response, previewBytes),
            },
      if (request.isWebSocket || (response?.isWebSocket ?? false))
        'websocket': {'frameCount': request.messages.length},
    };
  }

  /// body 分页切片。二进制只返回描述信息。
  static Future<Map<String, dynamic>> bodySlice(HttpMessage? message,
      {int offset = 0, int limit = defaultPreviewBytes}) async {
    if (message == null) {
      return {'available': false, 'reason': 'message not available'};
    }
    offset = offset < 0 ? 0 : offset;
    limit = limit.clamp(1, maxBodySliceBytes);

    var mime = _mime(message);
    if (isBinary(message)) {
      return {
        'available': true,
        'binary': true,
        'mimeType': mime,
        'size': message.body?.length ?? 0,
        'sha256': _sha256(message.body),
      };
    }

    var full = await message.decodeBodyString();
    var bytes = Uint8List.fromList(utf8.encode(full));
    var total = bytes.length;
    if (offset > total) {
      offset = total;
    }
    var end = (offset + limit).clamp(0, total);
    var slice = utf8.decode(bytes.sublist(offset, end), allowMalformed: true);
    return {
      'available': true,
      'binary': false,
      'mimeType': mime,
      'encoding': 'utf-8',
      'offset': offset,
      'returned': end - offset,
      'total': total,
      'truncated': end < total,
      'text': slice,
    };
  }

  /// WebSocket/SSE 帧（最近 [maxWsFrames] 条，文本总量封顶）
  static Map<String, dynamic> messages(List<WebSocketFrame> frames,
      {int offset = 0, int limit = maxWsFrames}) {
    var total = frames.length;
    limit = limit.clamp(1, maxWsFrames);
    if (offset < 0) offset = 0;
    if (offset > total) offset = total;
    var end = (offset + limit).clamp(0, total);

    var items = <Map<String, dynamic>>[];
    var budget = maxWsPayloadBytes;
    // 倒序挑选后再正序输出，保证最新的帧优先获得字节预算
    for (var i = end - 1; i >= offset; i--) {
      var frame = frames[i];
      var text = frame.isText ? frame.payloadDataAsString : '<binary frame ${frame.payloadLength} bytes>';
      if (text.length > budget) {
        text = text.substring(0, budget.clamp(0, text.length));
      }
      budget -= text.length;
      items.insert(0, {
        'index': i,
        'from': frame.isFromClient ? 'client' : 'server',
        'opcode': frame.opcode,
        'time': frame.time.toUtc().toIso8601String(),
        'payloadLength': frame.payloadLength,
        'truncated': text.length < (frame.isText ? frame.payloadDataAsString.length : 0),
        'text': text,
      });
      if (budget <= 0) break;
    }

    return {'total': total, 'offset': offset, 'returned': items.length, 'truncated': end < total, 'frames': items};
  }

  static Future<Map<String, dynamic>> _bodyPreview(HttpMessage message, int previewBytes) async {
    var slice = await bodySlice(message, offset: 0, limit: previewBytes);
    return slice;
  }

  static List<Map<String, String>> _headers(HttpMessage? message, bool redact) {
    var result = <Map<String, String>>[];
    message?.headers.forEach((name, values) {
      var sensitive = redact && SensitiveData.isRedactedHeader(name);
      for (var value in values) {
        result.add({'name': name, 'value': sensitive ? SensitiveData.placeholder : value});
      }
    });
    return result;
  }

  static String? _mime(HttpMessage? message) {
    var contentType = message?.headers.contentType ?? '';
    if (contentType.isEmpty) return null;
    var semi = contentType.indexOf(';');
    return (semi >= 0 ? contentType.substring(0, semi) : contentType).trim();
  }

  static bool isBinary(HttpMessage message) {
    if (message.contentType.isBinary) return true;
    var mime = _mime(message)?.toLowerCase() ?? '';
    return mime.startsWith('image/') ||
        mime.startsWith('audio/') ||
        mime.startsWith('video/') ||
        mime.startsWith('font/') ||
        mime.contains('octet-stream') ||
        mime.contains('zip') ||
        mime.contains('pdf') ||
        mime.contains('protobuf');
  }

  static String? _sha256(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      var digest = CryptoUtils.getHashPlain(Uint8List.fromList(bytes), algorithmName: 'SHA-256');
      return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    } catch (_) {
      return null;
    }
  }
}
