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

import 'package:proxypin/mcp/capture/curl_builder.dart';
import 'package:proxypin/mcp/capture/flow_store.dart';
import 'package:proxypin/mcp/capture/flow_view.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/http/http.dart';

import 'json_rpc.dart';
import 'mcp_tool.dart';

/// MCP 协议处理器（与传输无关）：JSON-RPC 2.0 + MCP 2024-11-05。
///
/// 工具集 = 内置只读流量工具 + [extraTools]（规则写操作等，由 McpActions 注入）。
///
/// @author wanghongen
class McpServer {
  static const String protocolVersion = '2024-11-05';
  static const String serverName = 'proxypin';
  static const String serverVersion = '1.0.0';

  final FlowStore store;

  /// 是否默认脱敏敏感头
  final bool Function() redactEnabled;

  /// 额外注册的工具（规则写操作、重放、清理等）
  final List<McpTool> extraTools;

  McpServer({required this.store, required this.redactEnabled, this.extraTools = const []});

  late final List<McpTool> _tools = [...builtinTools(store, redactEnabled: redactEnabled), ...extraTools];

  /// 内置只读工具集（不依赖具体 [McpServer] 实例），供设置页展示工具目录。
  /// 返回的 handler 依赖真实抓包存储，仅用于元数据展示时不会被调用。
  static List<McpTool> builtinTools(FlowStore store, {required bool Function() redactEnabled}) =>
      _buildTools(store, redactEnabled);

  /// 处理一条已解析的 JSON-RPC 请求；通知（无 id）返回 null。
  Future<Map<String, dynamic>?> handle(Map<String, dynamic> message) async {
    var id = message['id'];
    var method = message['method'];
    var params = (message['params'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    switch (method) {
      case 'initialize':
        return JsonRpcResponse.result(id, _initializeResult(params));
      case 'ping':
        return JsonRpcResponse.result(id, {});
      case 'tools/list':
        return JsonRpcResponse.result(id, {
          'tools': _tools.map((t) => t.toJson()).toList(),
        });
      case 'tools/call':
        return await _callTool(id, params);
      case 'notifications/initialized':
      case 'initialized':
        return null;
      default:
        if (id == null) return null;
        return JsonRpcResponse.error(
            id, JsonRpcError(JsonRpcError.methodNotFound, 'Method not found: $method'));
    }
  }

  Map<String, dynamic> _initializeResult(Map<String, dynamic> params) {
    return {
      'protocolVersion': protocolVersion,
      'capabilities': {
        'tools': {'listChanged': false},
      },
      'serverInfo': {'name': serverName, 'version': serverVersion},
    };
  }

  Future<Map<String, dynamic>> _callTool(Object? id, Map<String, dynamic> params) async {
    var name = params['name']?.toString();
    var tool = _tools.firstWhere((t) => t.name == name, orElse: () => McpTool(
          name: '_missing',
          description: '',
          inputSchema: const {},
          handler: (_) async => null,
        ));

    if (name == null || tool.name == '_missing') {
      return JsonRpcResponse.error(
          id, JsonRpcError(JsonRpcError.invalidParams, 'Unknown tool: $name'));
    }

    var args = (params['arguments'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    try {
      var result = await tool.handler(args);
      return JsonRpcResponse.result(id, {
        'content': [
          {'type': 'text', 'text': jsonEncode(result)}
        ],
        'isError': false,
      });
    } on ToolException catch (e) {
      return JsonRpcResponse.result(id, {
        'content': [
          {'type': 'text', 'text': e.message}
        ],
        'isError': true,
      });
    } catch (e) {
      return JsonRpcResponse.result(id, {
        'content': [
          {'type': 'text', 'text': 'tool error: $e'}
        ],
        'isError': true,
      });
    }
  }

  // ---------------------------------------------------------------- tools

  static List<McpTool> _buildTools(FlowStore store, bool Function() redactEnabled) => [
        McpTool(
          name: 'get_proxy_status',
          description:
              'Get ProxyPin capture status: whether recording, proxy port, SSL interception, MCP version, and number of buffered flows.',
          inputSchema: {'type': 'object', 'properties': {}},
          handler: (_) async {
            var server = ProxyServer.current;
            return {
              'recording': server?.isRunning ?? false,
              'proxyPort': server?.port,
              'sslInterception': server?.enableSsl ?? false,
              'mcpVersion': serverVersion,
              'protocolVersion': protocolVersion,
              'bufferedFlows': store.count,
            };
          },
        ),
        McpTool(
          name: 'list_flows',
          description:
              'List captured HTTP flows as compact metadata (no headers/body). Newest first. Use filters, then get_flow_detail / get_flow_body for a specific id.',
          inputSchema: {
            'type': 'object',
            'properties': {
              'limit': {'type': 'integer', 'description': 'Max items, default 20, max 100'},
              'offset': {'type': 'integer', 'description': 'Pagination offset, default 0'},
              'host': {'type': 'string', 'description': 'Substring match on host'},
              'method': {'type': 'string', 'description': 'HTTP method, e.g. GET/POST'},
              'status_from': {'type': 'integer'},
              'status_to': {'type': 'integer'},
              'keyword': {'type': 'string', 'description': 'Substring match on full URL'},
              'since_ms': {'type': 'integer', 'description': 'Epoch milliseconds lower bound'},
            }
          },
          handler: (args) async {
            var flows = store.query(
              limit: _intArgOr(args['limit'], 20),
              offset: _intArgOr(args['offset'], 0),
              host: args['host']?.toString(),
              method: args['method']?.toString(),
              statusFrom: _intArg(args['status_from']),
              statusTo: _intArg(args['status_to']),
              keyword: args['keyword']?.toString(),
              sinceMs: _intArg(args['since_ms']),
            );
            return {
              'count': flows.length,
              'totalBuffered': store.count,
              'flows': flows.map(FlowView.summary).toList(),
            };
          },
        ),
        McpTool(
          name: 'search_flows',
          description:
              'Full-text search of captured request/response BODIES for a substring (case-insensitive, binary bodies skipped). Returns matching flow summaries, newest first.',
          inputSchema: {
            'type': 'object',
            'properties': {
              'keyword': {'type': 'string', 'description': 'Substring to search in request/response bodies'},
              'side': {
                'type': 'string',
                'enum': ['both', 'request', 'response'],
                'description': 'Which side to search, default both'
              },
              'limit': {'type': 'integer', 'description': 'Max items, default 20, max 100'},
            },
            'required': ['keyword'],
          },
          handler: (args) async {
            var keyword = args['keyword']?.toString() ?? '';
            var flows = await store.search(
              keyword,
              side: args['side']?.toString() ?? 'both',
              limit: _intArgOr(args['limit'], 20),
            );
            return {
              'keyword': keyword,
              'count': flows.length,
              'totalBuffered': store.count,
              'flows': flows.map(FlowView.summary).toList(),
            };
          },
        ),
        McpTool(
          name: 'get_flow_detail',
          description:
              'Get full detail of one flow: headers (sensitive values redacted by default), query, and a truncated body preview. Use get_flow_body to page the rest.',
          inputSchema: {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'description': 'Flow id from list_flows'},
              'redact': {
                'type': 'boolean',
                'description':
                    'Redact Authorization/Cookie. Forced true unless the user has disabled redaction in app settings.'
              },
              'preview_bytes': {'type': 'integer', 'description': 'Body preview bytes, default 8192'},
            },
            'required': ['id'],
          },
          handler: (args) async {
            var request = _requireFlow(store, args['id']?.toString());
            var redact = _effectiveRedact(args['redact'], redactEnabled());
            var preview = _intArgOr(args['preview_bytes'], FlowView.defaultPreviewBytes);
            preview = preview.clamp(1, FlowView.maxBodySliceBytes);
            return await FlowView.detail(request, redact: redact, previewBytes: preview);
          },
        ),
        McpTool(
          name: 'get_flow_body',
          description:
              'Page a flow request/response body as UTF-8 text. Bodies are capped per call; binary bodies return only mimeType/size/sha256.',
          inputSchema: {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
              'side': {'type': 'string', 'enum': ['request', 'response'], 'description': 'default response'},
              'offset': {'type': 'integer', 'description': 'Byte offset, default 0'},
              'limit': {'type': 'integer', 'description': 'Max bytes, default 8192, hard cap 65536'},
            },
            'required': ['id'],
          },
          handler: (args) async {
            var request = _requireFlow(store, args['id']?.toString());
            var side = args['side']?.toString() ?? 'response';
            HttpMessage? message = side == 'request' ? request : request.response;
            if (side == 'response' && request.response == null) {
              return {'available': false, 'reason': 'response not received yet'};
            }
            return await FlowView.bodySlice(
              message,
              offset: _intArgOr(args['offset'], 0),
              limit: _intArgOr(args['limit'], FlowView.defaultPreviewBytes),
            );
          },
        ),
        McpTool(
          name: 'get_flow_messages',
          description: 'Page WebSocket frames of a flow (newest have byte-budget priority). Text frames include payload text.',
          inputSchema: {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
              'offset': {'type': 'integer'},
              'limit': {'type': 'integer', 'description': 'Max frames, default/max 200'},
            },
            'required': ['id'],
          },
          handler: (args) async {
            var id = args['id']?.toString();
            _requireFlow(store, id);
            return FlowView.messages(
              store.frames(id ?? ''),
              offset: _intArgOr(args['offset'], 0),
              limit: _intArgOr(args['limit'], FlowView.maxWsFrames),
            );
          },
        ),
        McpTool(
          name: 'get_ssl_proxying_list',
          description:
              'Get HTTPS interception state: whether SSL MITM is enabled, plus the excluded (blacklist) and restricted (whitelist) domain lists. Blacklisted domains are passed through without decryption.',
          inputSchema: {'type': 'object', 'properties': {}},
          handler: (_) async {
            var server = ProxyServer.current;
            var blacklist = HostFilter.blacklist;
            var whitelist = HostFilter.whitelist;
            return {
              'sslInterception': server?.enableSsl ?? false,
              'blacklist': {
                'enabled': blacklist.enabled,
                'domains': blacklist.list.map((e) => e.pattern).toList(),
              },
              'whitelist': {
                'enabled': whitelist.enabled,
                'domains': whitelist.list.map((e) => e.pattern).toList(),
              },
            };
          },
        ),
        McpTool(
          name: 'export_flow_curl',
          description: 'Export a captured request as a runnable cURL command. Sensitive headers are redacted by default.',
          inputSchema: {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
              'redact': {
                'type': 'boolean',
                'description':
                    'Forced true unless the user has disabled redaction in app settings.'
              },
            },
            'required': ['id'],
          },
          handler: (args) async {
            var request = _requireFlow(store, args['id']?.toString());
            var redact = _effectiveRedact(args['redact'], redactEnabled());
            return {'curl': CurlBuilder.build(request, redact: redact)};
          },
        ),
      ];

  static HttpRequest _requireFlow(FlowStore store, String? id) {
    if (id == null || id.isEmpty) {
      throw ToolException('Missing required parameter: id');
    }
    var request = store.getById(id);
    if (request == null) {
      throw ToolException('Flow not found or expired (buffer keeps newest ${FlowStore.defaultMaxEntries}): $id');
    }
    return request;
  }

  /// 生效脱敏状态：用户设置是硬门槛。
  /// 脱敏开启（默认）时，工具参数无法关闭；用户在设置中主动关闭后，未传参数遵循设置，
  /// 显式传 redact:true 仍可脱敏。
  static bool _effectiveRedact(dynamic arg, bool settingEnabled) => settingEnabled || arg == true;

  static int? _intArg(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static int _intArgOr(dynamic value, int fallback) => _intArg(value) ?? fallback;
}

/// 可预期的工具调用错误，message 直接返回给模型。
class ToolException implements Exception {
  final String message;

  ToolException(this.message);

  @override
  String toString() => message;
}
