import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/components/manager/hosts_manager.dart';
import 'package:proxypin/network/components/manager/request_block_manager.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/components/manager/rewrite_rule.dart';
import 'package:proxypin/network/components/manager/script_manager.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/mcp/mcp_bridge.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/desktop/desktop.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:flutter/material.dart';

class McpServer {
  static final McpServer _instance = McpServer._internal();

  factory McpServer() => _instance;

  McpServer._internal();

  io.HttpServer? _server;
  int? _port;
  
  int get port => _port ?? 17777;
  
  // SSE 连接池
  final List<io.HttpResponse> _sseConnections = [];
  
  // 状态变化回调
  VoidCallback? onStatusChanged;

  bool get isRunning => _server != null;

  Future<void> start() async {
    try {
      if (isRunning) return;
      
      var config = await Configuration.instance;
      _port = config.mcpPort;
      
      // 绑定 loopback 保证安全
      _server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, _port!);
      logger.i('MCP Server listening on http://127.0.0.1:$_port');

      _server!.listen((request) {
        // CORS 处理
        if (request.method == 'OPTIONS') {
           _handleOptions(request);
           return;
        }

        final path = request.uri.path;
        if (path == '/sse') {
          _handleSse(request);
        } else if (path == '/messages') {
          _handleMessages(request);
        } else {
          final response = request.response;
          response.statusCode = io.HttpStatus.notFound;
          response.close();
        }
      });
      
      // 监听 Bridge 的新请求事件，推送到 SSE
      McpBridge().onNewRequest = (log) {
          _broadcastEvent('resource', {
              'uri': 'proxypin://requests/latest',
              // 可以在这里推送增量更新
          });
      };
      
      // 通知状态变化
      onStatusChanged?.call();
      
    } catch (e) {
      logger.e('Failed to start MCP server', error: e);
    }
  }
  
  Future<void> stop() async {
      await _server?.close();
      _server = null;
      // 通知状态变化
      onStatusChanged?.call();
  }

  void _handleOptions(io.HttpRequest request) {
    final response = request.response;
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.headers.add('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type');
    response.close();
  }

  void _handleSse(io.HttpRequest request) {
    final response = request.response;
    response.headers.contentType = io.ContentType('text', 'event-stream');
    response.headers.add('Cache-Control', 'no-cache');
    response.headers.add('Connection', 'keep-alive');
    response.headers.add('Access-Control-Allow-Origin', '*');

    // 发送 endpoint 告知客户端 POST 地址
    final endpoint = '/messages';
    response.write('event: endpoint\ndata: $endpoint\n\n');
    response.flush();

    _sseConnections.add(response);
    
    logger.i('New MCP SSE connection');

    response.done.then((_) {
      _sseConnections.remove(response);
      logger.i('MCP SSE connection closed');
    }).catchError((e) {
      _sseConnections.remove(response);
    });
  }

  Future<void> _handleMessages(io.HttpRequest request) async {
    if (request.method != 'POST') {
      final response = request.response;
      response.statusCode = 405; // Method Not Allowed
      response.close();
      return;
    }

    try {
      final content = await utf8.decoder.bind(request).join();
      if (content.isEmpty) {
          final response = request.response;
          response.statusCode = io.HttpStatus.badRequest;
          response.close();
          return;
      }
      
      final Map<String, dynamic> jsonRpc = jsonDecode(content);
      final result = await _processJsonRpc(jsonRpc);

      final response = request.response;
      response.headers.contentType = io.ContentType.json;
      response.headers.add('Access-Control-Allow-Origin', '*');
      response.write(jsonEncode(result));
      response.close();
    } catch (e) {
      logger.e('MCP Message Error', error: e);
      final response = request.response;
      response.statusCode = io.HttpStatus.internalServerError;
      response.write(jsonEncode({'error': e.toString()}));
      await response.close();
    }
  }

  /// 广播 SSE 事件
  void _broadcastEvent(String event, Object data) {
      for (var conn in _sseConnections) {
          try {
              conn.write('event: $event\n');
              conn.write('data: ${jsonEncode(data)}\n');
              conn.write('\n');
          } catch (e) {
              // ignore
          }
      }
  }

  Future<Map<String, dynamic>> _processJsonRpc(Map<String, dynamic> request) async {
    final method = request['method'];
    final id = request['id'];
    
    // JSON-RPC Response 结构
    Map<String, dynamic> response(dynamic result) {
        return {'jsonrpc': '2.0', 'id': id, 'result': result};
    }
    
    Map<String, dynamic> error(int code, String message) {
        return {'jsonrpc': '2.0', 'id': id, 'error': {'code': code, 'message': message}};
    }

    try {
      switch (method) {
        case 'initialize':
          return response({
            'protocolVersion': '2024-11-05',
            'capabilities': {
              'tools': {},
              'resources': {}
            },
            'serverInfo': {'name': 'ProxyPin MCP', 'version': '1.0.0'}
          });
          
        case 'notifications/initialized':
          return {}; // No response
          
        case 'tools/list':
          return response({
            'tools': _getToolsList()
          });
          
        case 'tools/call':
          final params = request['params'];
          final name = params['name'];
          final args = params['arguments'] ?? {};
          final result = await _executeTool(name, args);
          return response({
              'content': [
                  {'type': 'text', 'text': jsonEncode(result)}
              ]
          });
          
        case 'resources/list':
          return response({
              'resources': [
                  {
                      'uri': 'proxypin://requests/latest',
                      'name': 'Latest Requests',
                      'mimeType': 'application/json'
                  },
                  {
                      'uri': 'proxypin://config/current',
                      'name': 'Current Configuration',
                      'mimeType': 'application/json'
                  }
              ]
          });
          
        case 'resources/read':
          final params = request['params'];
          final uri = params['uri'];
          final content = await _readResource(uri);
          return response({
              'contents': [
                  {
                      'uri': uri,
                      'mimeType': 'application/json',
                      'text': jsonEncode(content)
                  }
              ]
          });

        case 'ping':
          return response({});
          
        default:
          return error(-32601, 'Method not found: $method');
      }
    } catch (e, stack) {
      logger.e('MCP Execution Error', error: e, stackTrace: stack);
      return error(-32603, 'Internal error: $e');
    }
  }

  List<Map<String, dynamic>> _getToolsList() {
    return [
      {
        'name': 'set_config',
        'description': 'Update ProxyPin configuration (System Proxy, SSL Capture).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'system_proxy': {'type': 'boolean', 'description': 'Enable/Disable system proxy'},
            'ssl_capture': {'type': 'boolean', 'description': 'Enable/Disable SSL capture (MITM)'}
          }
        }
      },
      {
        'name': 'add_host_mapping',
        'description': 'Add a domain mapping (like hosts file).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'domain': {'type': 'string', 'description': 'Domain name (e.g. example.com)'},
            'ip': {'type': 'string', 'description': 'Target IP or domain (e.g. 127.0.0.1)'}
          },
          'required': ['domain', 'ip']
        }
      },
      {
        'name': 'add_response_rewrite',
        'description': 'Mock/Rewrite response (headers, status code, or body) for a specific URL.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'url_pattern': {'type': 'string', 'description': 'URL pattern to match (e.g. "api.com/users")'},
            'rewrite_type': {'type': 'string', 'description': 'Type: updateHeader, updateStatusCode, updateBody', 'enum': ['updateHeader', 'updateStatusCode', 'updateBody']},
            'key': {'type': 'string', 'description': 'Header name (for updateHeader) or "body" for body replacement'},
            'value': {'type': 'string', 'description': 'New value (header value, status code, or body content)'}
          },
          'required': ['url_pattern', 'rewrite_type', 'value']
        }
      },
      {
        'name': 'export_har',
        'description': 'Export captured requests to HAR (HTTP Archive) format.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'limit': {'type': 'integer', 'description': 'Max requests to export (default 100)'},
             'request_ids': {'type': 'array', 'items': {'type': 'string'}, 'description': 'Specific request IDs to export'}
          }
        }
      },
      {
        'name': 'import_har',
        'description': 'Import HAR (HTTP Archive) data into ProxyPin session.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'har_content': {'type': 'string', 'description': 'HAR JSON content string'}
          },
          'required': ['har_content']
        }
      },
      {
        'name': 'search_requests',
        'description': 'Search and filter captured HTTP requests with powerful filters.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': 'Keyword in URL'},
            'method': {'type': 'string', 'description': 'HTTP Method (GET, POST...)'},
            'status_code': {'type': 'string', 'description': 'Status code pattern (e.g. "200", "4xx", "5xx")'},
            'domain': {'type': 'string', 'description': 'Domain name filter'},
            'header_search': {'type': 'string', 'description': 'Search in request/response headers (key or value)'},
            'request_body_search': {'type': 'string', 'description': 'Search in request body'},
            'response_body_search': {'type': 'string', 'description': 'Search in response body'},
            'min_duration': {'type': 'integer', 'description': 'Minimum duration in ms'},
            'max_duration': {'type': 'integer', 'description': 'Maximum duration in ms'},
            'limit': {'type': 'integer', 'description': 'Max results (default 20)'}
          }
        }
      },
      {
        'name': 'generate_code',
        'description': 'Generate code for a specific request in Python, JavaScript, or cURL.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {'type': 'string', 'description': 'The ID of the request'},
            'language': {'type': 'string', 'description': 'Target language: python, js, curl', 'enum': ['python', 'js', 'curl']}
          },
          'required': ['request_id', 'language']
        }
      },
      {
        'name': 'get_curl',
        'description': 'Generate cURL command for a specific request.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {'type': 'string', 'description': 'The ID of the request'}
          },
          'required': ['request_id']
        }
      },
      {
        'name': 'get_recent_requests',
        'description': 'Get a list of recent HTTP requests (Legacy, use search_requests instead).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'limit': {'type': 'integer', 'description': 'Max number of requests (default 20)'},
            'url_filter': {'type': 'string', 'description': 'Filter by URL keyword'},
            'method': {'type': 'string', 'description': 'Filter by HTTP Method (GET, POST...)'}
          }
        }
      },
      {
        'name': 'get_request_details',
        'description': '''Get full details (headers, body) of a specific request.

Response includes:
- request.body: Request body content
- request.bodySize: Body size in bytes
- request.bodyEncoding: Encoding type ('utf8', 'base64', or 'none')
- response.body: Response body content
- response.bodySize: Body size in bytes
- response.bodyEncoding: Encoding type ('utf8', 'base64', or 'none')

Body Encoding Rules:
- bodyEncoding='utf8': Text data (JSON, HTML, XML, etc.), use directly
- bodyEncoding='base64': Binary data (images, files, etc.), decode with base64.b64decode() in Python
- bodyEncoding='none': Empty body''',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {'type': 'string', 'description': 'The ID of the request'}
          },
          'required': ['request_id']
        }
      },
      {
        'name': 'start_proxy',
        'description': 'Start the ProxyPin server on a specific port.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'port': {'type': 'integer', 'description': 'Port number (default 9099)'}
          }
        }
      },
      {
        'name': 'stop_proxy',
        'description': 'Stop the ProxyPin server.',
        'inputSchema': {
          'type': 'object',
          'properties': {}
        }
      },
      {
        'name': 'get_proxy_status',
        'description': 'Get current status of the proxy server.',
        'inputSchema': {
          'type': 'object',
          'properties': {}
        }
      },
      {
        'name': 'clear_requests',
        'description': 'Clear all captured requests (session history and UI list).',
        'inputSchema': {
           'type': 'object',
           'properties': {}
        }
      },
      {
        'name': 'replay_request',
        'description': 'Replay/resend a captured HTTP request.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {'type': 'string', 'description': 'The ID of the request to replay'}
          },
          'required': ['request_id']
        }
      },
      {
        'name': 'block_url',
        'description': 'Block requests or responses matching a URL pattern.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'url_pattern': {'type': 'string', 'description': 'URL pattern to block (supports wildcard *)'},
            'block_type': {'type': 'string', 'description': 'Type: blockRequest or blockResponse', 'enum': ['blockRequest', 'blockResponse']}
          },
          'required': ['url_pattern', 'block_type']
        }
      },
      {
        'name': 'add_request_rewrite',
        'description': 'Add a request rewrite rule (modify headers, query params, or body).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'url_pattern': {'type': 'string', 'description': 'URL pattern to match'},
            'rewrite_type': {'type': 'string', 'description': 'Type: updateHeader, updateQueryParam, updateBody', 'enum': ['updateHeader', 'updateQueryParam', 'updateBody']},
            'key': {'type': 'string', 'description': 'Header name, query param name, or "body" for body replacement'},
            'value': {'type': 'string', 'description': 'New value'}
          },
          'required': ['url_pattern', 'rewrite_type', 'key', 'value']
        }
      },
      {
        'name': 'update_script',
        'description': 'Update or create a JavaScript script for request/response modification.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'description': 'Script name'},
            'url_pattern': {'type': 'string', 'description': 'URL pattern to match (supports wildcard *)'},
            'script_content': {'type': 'string', 'description': 'JavaScript code (onRequest/onResponse functions)'}
          },
          'required': ['name', 'url_pattern', 'script_content']
        }
      },
      {
        'name': 'get_scripts',
        'description': 'Get all configured scripts.',
        'inputSchema': {
          'type': 'object',
          'properties': {}
        }
      },
      {
        'name': 'get_statistics',
        'description': 'Get statistics of captured requests (methods, status codes, domains, etc.).',
        'inputSchema': {
          'type': 'object',
          'properties': {}
        }
      },
      {
        'name': 'compare_requests',
        'description': 'Compare two requests side by side (useful for debugging API changes).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id_1': {'type': 'string', 'description': 'First request ID'},
            'request_id_2': {'type': 'string', 'description': 'Second request ID'}
          },
          'required': ['request_id_1', 'request_id_2']
        }
      },
      {
        'name': 'find_similar_requests',
        'description': 'Find requests similar to a given request (same URL pattern, method, etc.).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {'type': 'string', 'description': 'Reference request ID'},
            'limit': {'type': 'integer', 'description': 'Max results (default 10)'}
          },
          'required': ['request_id']
        }
      },
      {
        'name': 'extract_api_endpoints',
        'description': 'Extract and group unique API endpoints from captured requests.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'domain_filter': {'type': 'string', 'description': 'Filter by domain (optional)'}
          }
        }
      }
    ];
  }

  Future<dynamic> _executeTool(String name, Map<String, dynamic> args) async {
    switch (name) {
      case 'set_config':
        var config = await Configuration.instance;
        var changed = false;
        
        if (args.containsKey('system_proxy')) {
            bool enable = args['system_proxy'];
            config.enableSystemProxy = enable;
            if (ProxyServer.current?.isRunning == true) {
                await ProxyServer.current?.setSystemProxyEnable(enable);
            }
            changed = true;
        }
        
        if (args.containsKey('ssl_capture')) {
            bool enable = args['ssl_capture'];
            config.enableSsl = enable;
            ProxyServer.current?.enableSsl = enable;
            changed = true;
        }
        
        if (changed) await config.flushConfig();
        return {'status': 'success', 'system_proxy': config.enableSystemProxy, 'ssl_capture': config.enableSsl};

      case 'add_host_mapping':
        final domain = args['domain'];
        final ip = args['ip'];
        var hostsManager = await HostsManager.instance;
        await hostsManager.addHosts(HostsItem(host: domain, toAddress: ip, enabled: true));
        await hostsManager.flushConfig();
        return {'status': 'success', 'message': 'Added host mapping: $domain -> $ip'};

      case 'add_response_rewrite':
        final urlPattern = args['url_pattern'];
        final rewriteTypeStr = args['rewrite_type'] ?? 'updateBody';
        final key = args['key'];
        final value = args['value'];
        
        try {
          var manager = await RequestRewriteManager.instance;
          var rule = RequestRewriteRule(
            type: RuleType.responseReplace,
            url: urlPattern,
            name: 'MCP: Response $rewriteTypeStr for $urlPattern'
          );
          
          RewriteItem item;
          if (rewriteTypeStr == 'updateHeader') {
            item = RewriteItem(RewriteType.updateHeader, true)
              ..key = key
              ..value = value;
          } else if (rewriteTypeStr == 'updateStatusCode') {
            item = RewriteItem(RewriteType.replaceResponseStatus, true)
              ..statusCode = int.tryParse(value) ?? 200;
          } else {
            // updateBody
            item = RewriteItem(RewriteType.replaceResponseBody, true)
              ..body = value;
          }
          
          await manager.addRule(rule, [item]);
          return {'status': 'success', 'message': 'Added response rewrite rule for $urlPattern'};
        } catch (e) {
          return {'error': 'Failed to add response rewrite rule: $e'};
        }

      case 'export_har':
        final limit = args['limit'] ?? 100;
        final requestIds = args['request_ids'];
        
        var list = DesktopHomePage.container.source;
        if (requestIds != null) {
            list = list.where((r) => requestIds.contains(r.requestId)).toList();
        } else {
            // 默认导出最近的
            list = list.reversed.take(limit).toList(); 
        }
        
        return _generateHar(list);

      case 'import_har':
        final content = args['har_content'];
        try {
            var json = jsonDecode(content);
            var entries = json['log']['entries'] as List;
            int count = 0;
            for (var entry in entries) {
                var req = _parseHarEntry(entry);
                if (req != null) {
                    DesktopHomePage.container.add(req);
                    count++;
                }
            }
            return {'status': 'success', 'imported_count': count};
        } catch (e) {
            return {'error': 'Failed to import HAR: $e'};
        }
        
      case 'search_requests':
        final limit = args['limit'] ?? 20;
        final query = args['query'];
        final method = args['method'];
        final statusCode = args['status_code'];
        final contentType = args['content_type'];
        final minDuration = args['min_duration'];

        try {
           var list = DesktopHomePage.container.source;
           var logs = list.where((r) {
             if (query != null && !r.requestUrl.contains(query)) return false;
             if (method != null && r.method.name.toUpperCase() != method.toString().toUpperCase()) return false;
             if (minDuration != null) {
                var duration = r.response != null ? r.response!.responseTime.difference(r.requestTime).inMilliseconds : 0;
                if (duration < minDuration) return false;
             }
             if (statusCode != null && r.response != null) {
                String code = r.response!.status.code.toString();
                String filter = statusCode.toString();
                if (filter.endsWith('xx')) {
                   if (!code.startsWith(filter.substring(0, 1))) return false;
                } else if (code != filter) {
                   return false;
                }
             }
             if (contentType != null) {
                var ct = r.response?.headers.contentType ?? r.headers.contentType;
                if (!ct.toLowerCase().contains(contentType.toLowerCase())) return false;
             }
             return true;
           }).toList();
           
           logs.sort((a, b) => b.requestTime.compareTo(a.requestTime));
           
           return logs.take(limit).map((r) => {
             'id': r.requestId,
             'url': r.requestUrl,
             'method': r.method.name,
             'statusCode': r.response?.status.code,
             'contentType': r.response?.headers.contentType,
             'timestamp': r.requestTime.toIso8601String(),
             'duration': r.response != null ? r.response!.responseTime.difference(r.requestTime).inMilliseconds : 0
           }).toList();
           
        } catch (e) {
           return {'error': 'Failed to search requests: $e'};
        }

      case 'generate_code':
        final id = args['request_id'];
        final lang = args['language'];
        
        try {
            var req = DesktopHomePage.container.source.firstWhere((r) => r.requestId == id);
            String code;
            if (lang == 'python') {
                code = _generatePythonCode(req);
            } else if (lang == 'js') {
                code = _generateJsCode(req);
            } else {
                code = _generateCurl(req);
            }
            return {'code': code, 'language': lang};
        } catch (e) {
            return {'error': 'Request not found or generation failed: $e'};
        }

      case 'get_curl':
        final id = args['request_id'];
        try {
            var req = DesktopHomePage.container.source.firstWhere((r) => r.requestId == id);
            return {'curl': _generateCurl(req)};
        } catch (e) {
            return {'error': 'Request not found'};
        }

      case 'get_request_details':
        final id = args['request_id'];
        
        final req = McpBridge().getRequestById(id);
        if (req == null) return {'error': 'Request not found'};
        
        return McpBridge.requestToJson(req, includeBody: true);
        
      case 'start_proxy':
        int port = args['port'] ?? 9099;
        var config = await Configuration.instance;
        config.port = port;
        if (ProxyServer.current?.isRunning == true) {
             await ProxyServer.current?.stop();
        }
        var server = ProxyServer(config);
        await server.start();
        return {'status': 'started', 'port': port};
        
      case 'stop_proxy':
        await ProxyServer.current?.stop();
        return {'status': 'stopped'};
        
      case 'get_proxy_status':
        final isRunning = ProxyServer.current?.isRunning ?? false;
        final port = ProxyServer.current?.port;
        return {'isRunning': isRunning, 'port': port};
        
      case 'clear_requests':
        // 调用真正的清除方法（对应UI垃圾桶图标）
        final success = McpBridge().clearWithUI();
        if (success) {
          return {'status': 'cleared', 'message': 'All requests cleared (UI and storage)'};
        } else {
          // 降级方案：只清空内存容器
          McpBridge().clear();
          return {'status': 'cleared', 'message': 'Requests cleared from memory only'};
        }

      case 'replay_request':
        final id = args['request_id'];
        try {
          var req = DesktopHomePage.container.source.firstWhere((r) => r.requestId == id);
          
          var response = await HttpClients.proxyRequest(req, timeout: const Duration(seconds: 30));
          
          return {
            'status': 'success',
            'response': {
              'statusCode': response.status.code,
              'statusText': response.status.reasonPhrase,
              'headers': response.headers.toMap(),
              'body': response.bodyAsString,
              'duration': response.responseTime.difference(req.requestTime).inMilliseconds
            }
          };
        } catch (e) {
          return {'error': 'Failed to replay request: $e'};
        }

      case 'block_url':
        final urlPattern = args['url_pattern'];
        final blockTypeStr = args['block_type'];
        
        try {
          var manager = await RequestBlockManager.instance;
          var blockType = BlockType.nameOf(blockTypeStr);
          var item = RequestBlockItem(true, urlPattern, blockType);
          manager.addBlockRequest(item);
          return {'status': 'success', 'message': 'Added block rule for $urlPattern'};
        } catch (e) {
          return {'error': 'Failed to add block rule: $e'};
        }

      case 'add_request_rewrite':
        final urlPattern = args['url_pattern'];
        final rewriteTypeStr = args['rewrite_type'];
        final key = args['key'];
        final value = args['value'];
        
        try {
          var manager = await RequestRewriteManager.instance;
          var rule = RequestRewriteRule(
            type: RuleType.requestUpdate,
            url: urlPattern,
            name: 'MCP: $rewriteTypeStr $key'
          );
          
          RewriteItem item;
          if (rewriteTypeStr == 'updateHeader') {
            item = RewriteItem(RewriteType.updateHeader, true)
              ..key = key
              ..value = value;
          } else if (rewriteTypeStr == 'updateQueryParam') {
            item = RewriteItem(RewriteType.updateQueryParam, true)
              ..key = key
              ..value = value;
          } else {
            item = RewriteItem(RewriteType.replaceRequestBody, true)
              ..body = value;
          }
          
          await manager.addRule(rule, [item]);
          return {'status': 'success', 'message': 'Added request rewrite rule for $urlPattern'};
        } catch (e) {
          return {'error': 'Failed to add request rewrite rule: $e'};
        }

      case 'update_script':
        final name = args['name'];
        final urlPattern = args['url_pattern'];
        final scriptContent = args['script_content'];
        
        try {
          var manager = await ScriptManager.instance;
          
          var existingIndex = manager.list.indexWhere((s) => s.name == name);
          
          if (existingIndex >= 0) {
            var item = manager.list[existingIndex];
            item.urls = [urlPattern];
            item.urlRegs = null;
            await manager.updateScript(item, scriptContent);
            await manager.flushConfig();
            return {'status': 'success', 'message': 'Updated script: $name'};
          } else {
            var item = ScriptItem(true, name, [urlPattern]);
            await manager.addScript(item, scriptContent);
            await manager.flushConfig();
            return {'status': 'success', 'message': 'Created script: $name'};
          }
        } catch (e) {
          return {'error': 'Failed to update script: $e'};
        }

      case 'get_scripts':
        try {
          var manager = await ScriptManager.instance;
          var scripts = manager.list.map((s) => {
            'name': s.name,
            'enabled': s.enabled,
            'urls': s.urls,
            'scriptPath': s.scriptPath
          }).toList();
          return {'scripts': scripts, 'enabled': manager.enabled};
        } catch (e) {
          return {'error': 'Failed to get scripts: $e'};
        }

      case 'get_recent_requests':
        final limit = args['limit'] ?? 20;
        final urlFilter = args['url_filter'];
        final method = args['method'];
        
        final requests = McpBridge().getRecentRequests(
          limit: limit,
          urlFilter: urlFilter,
          method: method,
        );
        
        return requests.map((r) => McpBridge.requestToJson(r)).toList();

      case 'get_statistics':
        return McpBridge().getStatistics();

      case 'compare_requests':
        final id1 = args['request_id_1'];
        final id2 = args['request_id_2'];
        
        final req1 = McpBridge().getRequestById(id1);
        final req2 = McpBridge().getRequestById(id2);
        
        if (req1 == null) return {'error': 'Request 1 not found'};
        if (req2 == null) return {'error': 'Request 2 not found'};
        
        // Header 差异对比
        var reqHeaders1 = req1.headers.toMap();
        var reqHeaders2 = req2.headers.toMap();
        var respHeaders1 = req1.response?.headers.toMap() ?? {};
        var respHeaders2 = req2.response?.headers.toMap() ?? {};
        
        var headerDiff = _compareHeaders(reqHeaders1, reqHeaders2);
        var respHeaderDiff = _compareHeaders(respHeaders1, respHeaders2);
        
        // Body 差异对比（如果是 JSON）
        var bodyDiff = _compareBody(req1.bodyAsString, req2.bodyAsString);
        var respBodyDiff = _compareBody(
          req1.response?.bodyAsString ?? '',
          req2.response?.bodyAsString ?? ''
        );
        
        return {
          'request_1': McpBridge.requestToJson(req1, includeBody: true),
          'request_2': McpBridge.requestToJson(req2, includeBody: true),
          'comparison': {
            'same_url': req1.requestUrl == req2.requestUrl,
            'same_method': req1.method == req2.method,
            'same_status': req1.response?.status.code == req2.response?.status.code,
            'duration_diff': (req1.response?.responseTime.difference(req1.requestTime).inMilliseconds ?? 0) - 
                            (req2.response?.responseTime.difference(req2.requestTime).inMilliseconds ?? 0),
            'request_header_diff': headerDiff,
            'response_header_diff': respHeaderDiff,
            'request_body_diff': bodyDiff,
            'response_body_diff': respBodyDiff,
          }
        };

      case 'find_similar_requests':
        final refId = args['request_id'];
        final limit = args['limit'] ?? 10;
        
        final refReq = McpBridge().getRequestById(refId);
        if (refReq == null) return {'error': 'Reference request not found'};
        
        try {
          var refUri = Uri.parse(refReq.requestUrl);
          var refPath = refUri.path;
          
          // 查找相似的请求（相同路径模式和方法）
          var similar = DesktopHomePage.container.source.where((req) {
            if (req.requestId == refId) return false; // 排除自己
            if (req.method != refReq.method) return false; // 方法必须相同
            
            try {
              var uri = Uri.parse(req.requestUrl);
              // 相同域名和路径
              return uri.host == refUri.host && uri.path == refPath;
            } catch (e) {
              return false;
            }
          }).take(limit).toList();
          
          return {
            'reference': McpBridge.requestToJson(refReq),
            'similar_requests': similar.map((r) => McpBridge.requestToJson(r)).toList(),
            'count': similar.length,
          };
        } catch (e) {
          return {'error': 'Failed to find similar requests: $e'};
        }

      case 'extract_api_endpoints':
        final domainFilter = args['domain_filter'];
        
        try {
          var requests = DesktopHomePage.container.source;
          var endpoints = <String, ApiEndpoint>{};
          
          for (var req in requests) {
            try {
              var uri = Uri.parse(req.requestUrl);
              
              // 域名过滤
              if (domainFilter != null && !uri.host.contains(domainFilter)) {
                continue;
              }
              
              var key = '${req.method.name} ${uri.host}${uri.path}';
              
              if (!endpoints.containsKey(key)) {
                endpoints[key] = ApiEndpoint(req.method.name, uri.host, uri.path);
              }
              
              endpoints[key]!.addRequest(req);
            } catch (e) {
              // 忽略解析失败的 URL
            }
          }
          
          // 转换为列表并按请求数量排序
          var result = endpoints.values.toList();
          result.sort((a, b) => b.count.compareTo(a.count));
          
          return {
            'endpoints': result.map((e) => e.toJson()).toList(),
            'total_unique': result.length,
          };
        } catch (e) {
          return {'error': 'Failed to extract endpoints: $e'};
        }
        
      default:
        throw Exception('Unknown tool: $name');
    }
  }

  String _generateCurl(HttpRequest req) {
    var sb = StringBuffer();
    sb.write("curl -X ${req.method.name} '${req.requestUrl}'");
    
    req.headers.forEach((key, values) {
        for (var v in values) {
            sb.write(" -H '$key: $v'");
        }
    });
    
    var body = req.bodyAsString;
    if (body.isNotEmpty) {
        var escapedBody = body.replaceAll("'", "'\\''");
        sb.write(" -d '$escapedBody'");
    }
    
    if (req.headers.contentEncoding == 'gzip') {
         sb.write(" --compressed");
    }
    return sb.toString();
  }

  String _generatePythonCode(HttpRequest req) {
    var sb = StringBuffer();
    sb.writeln("import requests");
    sb.writeln();
    sb.writeln("url = \"${req.requestUrl}\"");
    sb.writeln();
    
    sb.writeln("headers = {");
    req.headers.forEach((key, values) {
       // Python requests usually takes the first value if multiple, or list
       var val = values.length == 1 ? values.first : values.join(','); 
       // Escape quotes
       val = val.replaceAll('"', '\\"');
       sb.writeln("    \"$key\": \"$val\",");
    });
    sb.writeln("}");
    sb.writeln();
    
    var body = req.bodyAsString;
    if (body.isNotEmpty) {
        // Try to pretty print JSON if possible
        try {
            // Check if it's json
            if (req.headers.contentType.contains("json")) {
                 // Use json parameter
                 sb.writeln("payload = $body"); // Assume body is valid json string, maybe problematic if not formatted
                 // Safe way: treat as string then json.loads? Or just raw string
                 // Let's just use data for now to be safe
                 sb.writeln("response = requests.request(\"${req.method.name}\", url, headers=headers, data='''$body''')");
            } else {
                 sb.writeln("response = requests.request(\"${req.method.name}\", url, headers=headers, data='''$body''')");
            }
        } catch(e) {
             sb.writeln("response = requests.request(\"${req.method.name}\", url, headers=headers, data='''$body''')");
        }
    } else {
        sb.writeln("response = requests.request(\"${req.method.name}\", url, headers=headers)");
    }
    
    sb.writeln();
    sb.writeln("print(response.text)");
    return sb.toString();
  }

  String _generateJsCode(HttpRequest req) {
    var sb = StringBuffer();
    sb.writeln("const url = \"${req.requestUrl}\";");
    sb.writeln("const options = {");
    sb.writeln("  method: \"${req.method.name}\",");
    sb.writeln("  headers: {");
    req.headers.forEach((key, values) {
        var val = values.join(',');
        val = val.replaceAll('"', '\\"');
        sb.writeln("    \"$key\": \"$val\",");
    });
    sb.writeln("  },");
    
    var body = req.bodyAsString;
    if (body.isNotEmpty) {
        // Javascript multiline string with backticks
        sb.writeln("  body: `$body`");
    }
    sb.writeln("};");
    sb.writeln();
    sb.writeln("fetch(url, options)");
    sb.writeln("  .then(response => response.text())");
    sb.writeln("  .then(result => console.log(result))");
    sb.writeln("  .catch(error => console.error('error', error));");
    return sb.toString();
  }

  Map<String, dynamic> _generateHar(Iterable<HttpRequest> requests) {
    var entries = [];
    for (var req in requests) {
        var response = req.response;
        var duration = response != null ? response.responseTime.difference(req.requestTime).inMilliseconds : 0;
        
        entries.add({
            "startedDateTime": req.requestTime.toIso8601String(),
            "time": duration,
            "request": {
                "method": req.method.name,
                "url": req.requestUrl,
                "httpVersion": req.protocolVersion,
                "cookies": _parseCookies(req.headers.get('cookie')),
                "headers": req.headers.entries.map((e) => {"name": e.key, "value": e.value.join(',')}).toList(),
                "queryString": _parseQueryString(req.requestUrl),
                "headersSize": -1,
                "bodySize": req.packageSize ?? -1,
                "postData": req.bodyAsString.isNotEmpty ? {"mimeType": req.headers.contentType, "text": req.bodyAsString} : null
            },
            "response": {
                "status": response?.status.code ?? 0,
                "statusText": response?.status.reasonPhrase ?? "",
                "httpVersion": response?.protocolVersion ?? "HTTP/1.1",
                "cookies": [],
                "headers": response?.headers.entries.map((e) => {"name": e.key, "value": e.value.join(',')}).toList() ?? [],
                "content": {
                    "size": response?.body?.length ?? 0,
                    "mimeType": response?.headers.contentType ?? "",
                    "text": response?.bodyAsString
                },
                "redirectURL": "",
                "headersSize": -1,
                "bodySize": response?.packageSize ?? -1,
            },
            "cache": {},
            "timings": {
                "send": 0,
                "wait": duration,
                "receive": 0
            }
        });
    }

    return {
        "log": {
            "version": "1.2",
            "creator": {"name": "ProxyPin MCP", "version": "1.0"},
            "entries": entries
        }
    };
  }

  HttpRequest? _parseHarEntry(Map<String, dynamic> entry) {
     try {
         var requestJson = entry['request'];
         var url = requestJson['url'];
         var method = requestJson['method'];
         var req = HttpRequest(HttpMethod.valueOf(method), url);
         
         if (entry['startedDateTime'] != null) {
             req.requestTime = DateTime.parse(entry['startedDateTime']);
         }
         
         // Headers
         if (requestJson['headers'] != null) {
             for (var h in requestJson['headers']) {
                 req.headers.add(h['name'], h['value']);
             }
         }
         
         // Body
         if (requestJson['postData'] != null && requestJson['postData']['text'] != null) {
             req.body = utf8.encode(requestJson['postData']['text']);
         }
         
         // Response
         var responseJson = entry['response'];
         if (responseJson != null) {
             var status = responseJson['status'];
             var statusText = responseJson['statusText'];
             var res = HttpResponse(HttpStatus(status, statusText));
             
             if (responseJson['headers'] != null) {
                 for (var h in responseJson['headers']) {
                     res.headers.add(h['name'], h['value']);
                 }
             }
             
             if (responseJson['content'] != null && responseJson['content']['text'] != null) {
                 res.body = utf8.encode(responseJson['content']['text']);
             }
             
             res.request = req;
             // Calculate response time from duration
             var time = entry['time'] ?? 0;
             res.responseTime = req.requestTime.add(Duration(milliseconds: time is num ? time.toInt() : 0));
             req.response = res;
         }
         
         return req;
     } catch (e) {
         logger.e("Failed to parse HAR entry", error: e);
         return null;
     }
  }
  
  Future<dynamic> _readResource(String uri) async {
      if (uri == 'proxypin://requests/latest') {
          return McpBridge().getRecentRequests(limit: 50).map((r) => McpBridge.requestToJson(r)).toList();
      } else if (uri == 'proxypin://config/current') {
          var config = await Configuration.instance;
          return config.toJson();
      }
      throw Exception('Resource not found: $uri');
  }

  /// 比较两个 Header Map 的差异
  Map<String, dynamic> _compareHeaders(Map<String, String> h1, Map<String, String> h2) {
    var added = <String, String>{};
    var removed = <String, String>{};
    var changed = <String, Map<String, String>>{};
    
    // 检查新增和修改
    h2.forEach((key, value) {
      if (!h1.containsKey(key)) {
        added[key] = value;
      } else if (h1[key] != value) {
        changed[key] = {'old': h1[key]!, 'new': value};
      }
    });
    
    // 检查删除
    h1.forEach((key, value) {
      if (!h2.containsKey(key)) {
        removed[key] = value;
      }
    });
    
    return {
      'added': added,
      'removed': removed,
      'changed': changed,
      'has_diff': added.isNotEmpty || removed.isNotEmpty || changed.isNotEmpty,
    };
  }

  /// 比较两个 Body 的差异（支持 JSON）
  Map<String, dynamic> _compareBody(String body1, String body2) {
    if (body1 == body2) {
      return {'same': true, 'type': 'identical'};
    }
    
    // 尝试作为 JSON 对比
    try {
      var json1 = jsonDecode(body1);
      var json2 = jsonDecode(body2);
      
      if (json1 is Map && json2 is Map) {
        return {
          'same': false,
          'type': 'json',
          'diff': _compareJsonObjects(json1, json2),
        };
      }
    } catch (e) {
      // 不是 JSON，按文本对比
    }
    
    return {
      'same': false,
      'type': 'text',
      'length_diff': body2.length - body1.length,
      'body1_length': body1.length,
      'body2_length': body2.length,
    };
  }

  /// 比较两个 JSON 对象
  Map<String, dynamic> _compareJsonObjects(Map json1, Map json2) {
    var added = <String, dynamic>{};
    var removed = <String, dynamic>{};
    var changed = <String, Map<String, dynamic>>{};
    
    // 检查新增和修改
    json2.forEach((key, value) {
      if (!json1.containsKey(key)) {
        added[key.toString()] = value;
      } else if (json1[key] != value) {
        changed[key.toString()] = {'old': json1[key], 'new': value};
      }
    });
    
    // 检查删除
    json1.forEach((key, value) {
      if (!json2.containsKey(key)) {
        removed[key.toString()] = value;
      }
    });
    
    return {
      'added': added,
      'removed': removed,
      'changed': changed,
    };
  }

  /// 解析 Cookie 字符串为 HAR 格式
  List<Map<String, String>> _parseCookies(String? cookieHeader) {
    if (cookieHeader == null || cookieHeader.isEmpty) return [];
    
    var cookies = <Map<String, String>>[];
    var parts = cookieHeader.split(';');
    
    for (var part in parts) {
      var trimmed = part.trim();
      var index = trimmed.indexOf('=');
      if (index > 0) {
        var name = trimmed.substring(0, index);
        var value = trimmed.substring(index + 1);
        cookies.add({'name': name, 'value': value});
      }
    }
    
    return cookies;
  }

  /// 解析 URL 查询参数为 HAR 格式
  List<Map<String, String>> _parseQueryString(String url) {
    try {
      var uri = Uri.parse(url);
      return uri.queryParameters.entries
          .map((e) => {'name': e.key, 'value': e.value})
          .toList();
    } catch (e) {
      return [];
    }
  }
}

/// API 端点信息类
class ApiEndpoint {
  final String method;
  final String domain;
  final String path;
  final List<HttpRequest> requests = [];
  final Set<int> statusCodes = {};
  
  ApiEndpoint(this.method, this.domain, this.path);
  
  void addRequest(HttpRequest req) {
    requests.add(req);
    if (req.response?.status.code != null) {
      statusCodes.add(req.response!.status.code);
    }
  }
  
  int get count => requests.length;
  
  Map<String, dynamic> toJson() {
    return {
      'method': method,
      'domain': domain,
      'path': path,
      'count': count,
      'status_codes': statusCodes.toList()..sort(),
    };
  }
}
