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
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/components/manager/request_block_manager.dart';
import 'package:proxypin/network/components/manager/request_breakpoint_manager.dart';
import 'package:proxypin/network/components/manager/request_map_manager.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/components/manager/rewrite_rule.dart';
import 'package:proxypin/network/components/manager/script_manager.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/storage/favorites.dart';
import 'package:proxypin/utils/curl.dart';
import 'package:proxypin/utils/lang.dart';

import 'mcp_server.dart';
import 'mcp_tool.dart';

/// 写工具面：规则读写、SSL/系统代理、重放/构造、收藏、清理、代码生成。
///
/// 复用现有各 manager，规则在进程内即时生效。破坏性动作（clear_session）与平台相关的
/// 证书状态通过回调注入，避免本层依赖 UI / 平台插件。
///
/// @author wanghongen
class McpActions {
  final FlowStore store;

  /// 清空 UI 抓包列表（平台注入）；为空时仅清空 MCP 自身缓存
  final Future<void> Function()? onClearSession;

  /// 桌面端 CA 证书安装/信任状态（平台注入）
  final Future<Map<String, dynamic>> Function()? certStatusProvider;

  McpActions({required this.store, this.onClearSession, this.certStatusProvider});

  List<McpTool> tools() => [
        _listRules(),
        _toggleRecording(),
        _createBreakpoint(),
        _updateBreakpoint(),
        _removeBreakpoint(),
        _createBlock(),
        _updateBlock(),
        _removeBlock(),
        _createMapLocal(),
        _updateMapLocal(),
        _removeMapRule(),
        _createRedirect(),
        _updateRedirect(),
        _removeRewriteRule(),
        _createRewrite(),
        _updateRewrite(),
        _getRewriteDetail(),
        _listHosts(),
        _addHost(),
        _removeHost(),
        _setHostsEnabled(),
        _createScript(),
        _updateScript(),
        _getScriptTemplate(),
        _getScriptDetail(),
        _removeScript(),
        _enableSslProxying(),
        _setSystemProxy(),
        _getCertificateStatus(),
        _replayFlow(),
        _sendRequest(),
        _addFavorite(),
        _clearSession(),
        _generateCode(),
      ];

  HttpRequest _requireFlow(String? id) {
    var request = store.getById(id ?? '');
    if (request == null) {
      throw ToolException('Flow not found or expired: $id');
    }
    return request;
  }

  // ------------------------------------------------------------- rules

  McpTool _listRules() => McpTool(
        name: 'list_rules',
        description:
            'List all debugging rules with their indices: breakpoints, blocks, map-local, rewrites/redirects, scripts. Use the returned index with the remove_* tools.',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async {
          var bp = await RequestBreakpointManager.instance;
          var block = await RequestBlockManager.instance;
          var map = await RequestMapManager.instance;
          var rewrite = await RequestRewriteManager.instance;
          var script = await ScriptManager.instance;

          return {
            'breakpoints': {
              'enabled': bp.enabled,
              'rules': [
                for (var i = 0; i < bp.list.length; i++)
                  {
                    'index': i,
                    'name': bp.list[i].name,
                    'url': bp.list[i].url,
                    'enabled': bp.list[i].enabled,
                    'interceptRequest': bp.list[i].interceptRequest,
                    'interceptResponse': bp.list[i].interceptResponse,
                    'method': bp.list[i].method?.name,
                  }
              ],
            },
            'blocks': {
              'enabled': block.enabled,
              'rules': [
                for (var i = 0; i < block.list.length; i++)
                  {'index': i, 'url': block.list[i].url, 'enabled': block.list[i].enabled, 'type': block.list[i].type.name}
              ],
            },
            'mapLocal': {
              'enabled': map.enabled,
              'rules': [
                for (var i = 0; i < map.rules.length; i++)
                  {'index': i, 'name': map.rules[i].name, 'url': map.rules[i].url, 'enabled': map.rules[i].enabled}
              ],
            },
            'rewrites': {
              'enabled': rewrite.enabled,
              'rules': [
                for (var i = 0; i < rewrite.rules.length; i++)
                  {
                    'index': i,
                    'name': rewrite.rules[i].name,
                    'url': rewrite.rules[i].url,
                    'enabled': rewrite.rules[i].enabled,
                    'type': rewrite.rules[i].type.name,
                    'method': rewrite.rules[i].method?.name,
                  }
              ],
            },
            'scripts': {
              'enabled': script.enabled,
              'rules': [
                for (var i = 0; i < script.list.length; i++)
                  {
                    'index': i,
                    'name': script.list[i].name,
                    'urls': script.list[i].urls,
                    'enabled': script.list[i].enabled,
                    'remoteUrl': script.list[i].remoteUrl,
                  }
              ],
            },
          };
        },
      );

  McpTool _createBreakpoint() => McpTool(
        name: 'create_breakpoint',
        description:
            'Create a request/response breakpoint. `url` is a REGEX matched against the full URL. Intercepts matching traffic for inspection/edit in the app.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'url': {'type': 'string', 'description': 'Regex matched against full URL'},
            'name': {'type': 'string'},
            'method': {'type': 'string', 'description': 'Optional HTTP method filter'},
            'intercept_request': {'type': 'boolean'},
            'intercept_response': {'type': 'boolean'},
          },
          'required': ['url'],
        },
        handler: (a) async {
          var url = a['url']?.toString();
          if (url == null || url.isEmpty) throw ToolException('url is required');
          var rule = RequestBreakpointRule(
            url: url,
            name: a['name']?.toString(),
            method: a['method'] == null ? null : HttpMethod.valueOf(a['method'].toString()),
            interceptRequest: a['intercept_request'] is bool ? a['intercept_request'] as bool : true,
            interceptResponse: a['intercept_response'] is bool ? a['intercept_response'] as bool : true,
          );
          var mgr = await RequestBreakpointManager.instance;
          mgr.add(rule);
          return {'created': true, 'index': mgr.list.length - 1, 'url': url};
        },
      );

  McpTool _removeBreakpoint() => McpTool(
        name: 'remove_breakpoint',
        description: 'Remove a breakpoint by index (see list_rules), or disable the breakpoint feature globally.',
        inputSchema: {
          'type': 'object',
          'properties': {'index': {'type': 'integer'}, 'enabled': {'type': 'boolean'}},
        },
        handler: (a) async {
          var mgr = await RequestBreakpointManager.instance;
          if (a['enabled'] is bool) {
            mgr.enabled = a['enabled'] as bool;
            await mgr.save();
            return {'enabled': mgr.enabled};
          }
          var index = _int(a['index']);
          if (index == null || index < 0 || index >= mgr.list.length) throw ToolException('invalid index');
          var removed = mgr.list.removeAt(index);
          await mgr.save();
          return {'removed': removed.url};
        },
      );

  McpTool _updateBreakpoint() => McpTool(
        name: 'update_breakpoint',
        description:
            'Update an existing breakpoint rule by index (see list_rules). Only the fields you pass change; omit the rest to keep them.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'index': {'type': 'integer'},
            'url': {'type': 'string', 'description': 'Regex matched against full URL'},
            'name': {'type': 'string'},
            'method': {'type': 'string', 'description': 'Optional HTTP method filter'},
            'intercept_request': {'type': 'boolean'},
            'intercept_response': {'type': 'boolean'},
            'enabled': {'type': 'boolean'},
          },
          'required': ['index'],
        },
        handler: (a) async {
          var mgr = await RequestBreakpointManager.instance;
          var index = _int(a['index']);
          if (index == null || index < 0 || index >= mgr.list.length) throw ToolException('invalid index');
          var rule = mgr.list[index];
          if (a['url'] != null) rule.url = a['url'].toString();
          if (a['name'] != null) rule.name = a['name'].toString();
          if (a['method'] != null) rule.method = HttpMethod.valueOf(a['method'].toString());
          if (a['intercept_request'] is bool) rule.interceptRequest = a['intercept_request'] as bool;
          if (a['intercept_response'] is bool) rule.interceptResponse = a['intercept_response'] as bool;
          if (a['enabled'] is bool) rule.enabled = a['enabled'] as bool;
          await mgr.save();
          return {'updated': true, 'index': index, 'url': rule.url};
        },
      );

  McpTool _createBlock() => McpTool(
        name: 'create_block',
        description: 'Block matching requests or responses (blacklist). `url` is a wildcard pattern (e.g. *.example.com/*).',
        inputSchema: {
          'type': 'object',
          'properties': {
            'url': {'type': 'string'},
            'type': {'type': 'string', 'enum': ['blockRequest', 'blockResponse']},
          },
          'required': ['url'],
        },
        handler: (a) async {
          var url = a['url']?.toString();
          if (url == null || url.isEmpty) throw ToolException('url is required');
          var type = a['type']?.toString() == 'blockResponse' ? BlockType.blockResponse : BlockType.blockRequest;
          var mgr = await RequestBlockManager.instance;
          mgr.addBlockRequest(RequestBlockItem(true, url, type));
          return {'created': true, 'index': mgr.list.length - 1, 'url': url, 'type': type.name};
        },
      );

  McpTool _removeBlock() => McpTool(
        name: 'remove_block',
        description: 'Remove a block rule by index, or enable/disable blocking globally.',
        inputSchema: {
          'type': 'object',
          'properties': {'index': {'type': 'integer'}, 'enabled': {'type': 'boolean'}},
        },
        handler: (a) async {
          var mgr = await RequestBlockManager.instance;
          if (a['enabled'] is bool) {
            mgr.enabled = a['enabled'] as bool;
            await mgr.flushConfig();
            return {'enabled': mgr.enabled};
          }
          var index = _int(a['index']);
          if (index == null || index < 0 || index >= mgr.list.length) throw ToolException('invalid index');
          mgr.removeBlockRequest(index);
          return {'removed': true, 'index': index};
        },
      );

  McpTool _updateBlock() => McpTool(
        name: 'update_block',
        description:
            'Update an existing block rule by index. `url` is a wildcard pattern (e.g. *.example.com/*). Only the fields you pass change.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'index': {'type': 'integer'},
            'url': {'type': 'string'},
            'type': {'type': 'string', 'enum': ['blockRequest', 'blockResponse']},
            'enabled': {'type': 'boolean'},
          },
          'required': ['index'],
        },
        handler: (a) async {
          var mgr = await RequestBlockManager.instance;
          var index = _int(a['index']);
          if (index == null || index < 0 || index >= mgr.list.length) throw ToolException('invalid index');
          var item = mgr.list[index];
          if (a['url'] != null) {
            item.url = a['url'].toString();
            item.urlReg = null;
          }
          if (a['type'] != null) {
            item.type = a['type'].toString() == 'blockResponse' ? BlockType.blockResponse : BlockType.blockRequest;
          }
          if (a['enabled'] is bool) item.enabled = a['enabled'] as bool;
          await mgr.flushConfig();
          return {'updated': true, 'index': index, 'url': item.url, 'type': item.type.name};
        },
      );

  McpTool _createMapLocal() => McpTool(
        name: 'create_map_local',
        description:
            'Map matching URL to a locally defined response (status/headers/body). `url` is a wildcard pattern. The mapped response replaces the server response.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'url': {'type': 'string'},
            'name': {'type': 'string'},
            'status_code': {'type': 'integer'},
            'headers': {'type': 'object', 'additionalProperties': {'type': 'string'}},
            'body': {'type': 'string'},
          },
          'required': ['url'],
        },
        handler: (a) async {
          var url = a['url']?.toString();
          if (url == null || url.isEmpty) throw ToolException('url is required');
          var rule = RequestMapRule(
            url: url,
            name: a['name']?.toString(),
            type: RequestMapType.local,
          );
          var headers = (a['headers'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString()));
          var item = RequestMapItem(
            statusCode: _int(a['status_code']) ?? 200,
            headers: headers,
            body: a['body']?.toString(),
            bodyType: MapBodyType.text.name,
          );
          var mgr = await RequestMapManager.instance;
          await mgr.addRule(rule, item);
          return {'created': true, 'index': mgr.rules.length - 1, 'url': url};
        },
      );

  McpTool _removeMapRule() => McpTool(
        name: 'remove_map_rule',
        description: 'Remove a map-local/script rule by index, or enable/disable mapping globally.',
        inputSchema: {
          'type': 'object',
          'properties': {'index': {'type': 'integer'}, 'enabled': {'type': 'boolean'}},
        },
        handler: (a) async {
          var mgr = await RequestMapManager.instance;
          if (a['enabled'] is bool) {
            mgr.enabled = a['enabled'] as bool;
            await mgr.flushConfig();
            return {'enabled': mgr.enabled};
          }
          var index = _int(a['index']);
          if (index == null || index < 0 || index >= mgr.rules.length) throw ToolException('invalid index');
          await mgr.deleteRule(index);
          await mgr.flushConfig();
          return {'removed': true, 'index': index};
        },
      );

  McpTool _updateMapLocal() => McpTool(
        name: 'update_map_local',
        description:
            'Update an existing map-local rule by index: its URL match and/or the locally served response (status/headers/body). Only the fields you pass change.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'index': {'type': 'integer'},
            'url': {'type': 'string'},
            'name': {'type': 'string'},
            'status_code': {'type': 'integer'},
            'headers': {'type': 'object', 'additionalProperties': {'type': 'string'}},
            'body': {'type': 'string'},
            'enabled': {'type': 'boolean'},
          },
          'required': ['index'],
        },
        handler: (a) async {
          var mgr = await RequestMapManager.instance;
          var index = _int(a['index']);
          if (index == null || index < 0 || index >= mgr.rules.length) throw ToolException('invalid index');
          var rule = mgr.rules[index];
          var item = await mgr.getMapItem(rule);
          if (item == null) throw ToolException('map item not found for rule $index');
          if (a['url'] != null) rule.url = a['url'].toString();
          if (a['name'] != null) rule.name = a['name'].toString();
          if (a['status_code'] != null) item.statusCode = _int(a['status_code']);
          if (a['headers'] is Map) {
            item.headers = (a['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
          }
          if (a['body'] != null) item.body = a['body'].toString();
          if (a['enabled'] is bool) rule.enabled = a['enabled'] as bool;
          await mgr.updateRule(rule, item);
          return {'updated': true, 'index': index, 'url': rule.url};
        },
      );

  McpTool _createRedirect() => McpTool(
        name: 'create_redirect',
        description: 'Redirect (map remote) requests matching `url` wildcard to `target_url`.',
        inputSchema: {
          'type': 'object',
          'properties': {'url': {'type': 'string'}, 'target_url': {'type': 'string'}, 'name': {'type': 'string'}},
          'required': ['url', 'target_url'],
        },
        handler: (a) async {
          var url = a['url']?.toString();
          var target = a['target_url']?.toString();
          if (url == null || url.isEmpty || target == null || target.isEmpty) {
            throw ToolException('url and target_url are required');
          }
          var rule = RequestRewriteRule(url: url, name: a['name']?.toString(), type: RuleType.redirect);
          var items = [RewriteItem(RewriteType.redirect, true)..redirectUrl = target];
          var mgr = await RequestRewriteManager.instance;
          await mgr.addRule(rule, items);
          await mgr.flushRequestRewriteConfig();
          return {'created': true, 'index': mgr.rules.length - 1, 'url': url, 'target': target};
        },
      );

  McpTool _removeRewriteRule() => McpTool(
        name: 'remove_rewrite_rule',
        description: 'Remove a rewrite/redirect rule by index (see list_rules), or enable/disable rewriting globally.',
        inputSchema: {
          'type': 'object',
          'properties': {'index': {'type': 'integer'}, 'enabled': {'type': 'boolean'}},
        },
        handler: (a) async {
          var mgr = await RequestRewriteManager.instance;
          if (a['enabled'] is bool) {
            mgr.enabled = a['enabled'] as bool;
            await mgr.flushRequestRewriteConfig();
            return {'enabled': mgr.enabled};
          }
          var index = _int(a['index']);
          if (index == null || index < 0 || index >= mgr.rules.length) throw ToolException('invalid index');
          await mgr.removeIndex([index]);
          await mgr.flushRequestRewriteConfig();
          return {'removed': true, 'index': index};
        },
      );

  McpTool _updateRedirect() => McpTool(
        name: 'update_redirect',
        description:
            'Update an existing redirect rule by index: its URL wildcard match and/or target URL. Only the fields you pass change.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'index': {'type': 'integer'},
            'url': {'type': 'string'},
            'target_url': {'type': 'string'},
            'name': {'type': 'string'},
            'enabled': {'type': 'boolean'},
          },
          'required': ['index'],
        },
        handler: (a) async {
          var mgr = await RequestRewriteManager.instance;
          var index = _int(a['index']);
          if (index == null || index < 0 || index >= mgr.rules.length) throw ToolException('invalid index');
          var rule = mgr.rules[index];
          var items = await mgr.getRewriteItems(rule);
          if (a['url'] != null) rule.url = a['url'].toString();
          if (a['name'] != null) rule.name = a['name'].toString();
          if (a['enabled'] is bool) rule.enabled = a['enabled'] as bool;
          if (a['target_url'] != null) {
            if (items == null) throw ToolException('redirect items not found for rule $index');
            var redirect = items.firstWhereOrNull((e) => e.type == RewriteType.redirect);
            if (redirect == null) throw ToolException('rule $index is not a redirect rule');
            redirect.redirectUrl = a['target_url'].toString();
          }
          await mgr.updateRule(index, rule, items);
          await mgr.flushRequestRewriteConfig();
          return {'updated': true, 'index': index, 'url': rule.url};
        },
      );

  // ------------------------------------------------------------- rewrite (generic)

  /// 每个 op 允许出现的规则类型
  static Set<RewriteType> _opsForRuleType(RuleType type) => switch (type) {
        RuleType.requestReplace => {
            RewriteType.replaceRequestLine,
            RewriteType.replaceRequestHeader,
            RewriteType.replaceRequestBody
          },
        RuleType.responseReplace => {
            RewriteType.replaceResponseStatus,
            RewriteType.replaceResponseHeader,
            RewriteType.replaceResponseBody
          },
        RuleType.requestUpdate => {
            RewriteType.updateBody,
            RewriteType.addQueryParam,
            RewriteType.updateQueryParam,
            RewriteType.removeQueryParam,
            RewriteType.addHeader,
            RewriteType.updateHeader,
            RewriteType.removeHeader
          },
        RuleType.responseUpdate => {
            RewriteType.updateBody,
            RewriteType.addHeader,
            RewriteType.updateHeader,
            RewriteType.removeHeader
          },
        RuleType.redirect => {RewriteType.redirect},
      };

  /// 从操作推断规则类型；改参数类归 request，header/body 修改默认归 request
  static RuleType _inferRewriteType(List<RewriteItem> items) {
    var hasRequestReplace = items.any((i) =>
        _opsForRuleType(RuleType.requestReplace).contains(i.type));
    var hasResponseReplace = items.any((i) =>
        _opsForRuleType(RuleType.responseReplace).contains(i.type));
    if (hasRequestReplace && hasResponseReplace) {
      throw ToolException('cannot mix request and response replace ops in one rule; create two rules');
    }
    if (hasRequestReplace) return RuleType.requestReplace;
    if (hasResponseReplace) return RuleType.responseReplace;
    return RuleType.requestUpdate;
  }

  static RewriteItem _rewriteItemFromArgs(Map<String, dynamic> op) {
    var name = op['op']?.toString();
    if (name == null || name.isEmpty) throw ToolException('each operation needs "op"');
    RewriteType type;
    try {
      type = RewriteType.fromName(name);
    } catch (_) {
      throw ToolException('unknown rewrite op: $name');
    }
    var item = RewriteItem(type, true);
    switch (type) {
      case RewriteType.addHeader:
      case RewriteType.addQueryParam:
        item.key = op['key']?.toString();
        item.value = op['value']?.toString();
        break;
      case RewriteType.updateHeader:
      case RewriteType.updateQueryParam:
      case RewriteType.removeQueryParam:
      case RewriteType.removeHeader:
      case RewriteType.updateBody:
        item.key = op['key']?.toString();
        item.value = op['value']?.toString();
        item.useRegex = op['use_regex'] is bool ? op['use_regex'] as bool : true;
        break;
      case RewriteType.replaceRequestLine:
        if (op['method'] != null) item.method = HttpMethod.valueOf(op['method'].toString());
        item.path = op['path']?.toString();
        item.queryParam = op['query']?.toString();
        break;
      case RewriteType.replaceRequestHeader:
      case RewriteType.replaceResponseHeader:
        if (op['headers'] is Map) {
          item.headers = (op['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
        }
        break;
      case RewriteType.replaceRequestBody:
      case RewriteType.replaceResponseBody:
        item.body = op['body']?.toString();
        item.bodyType = op['body_type']?.toString();
        break;
      case RewriteType.replaceResponseStatus:
        item.statusCode = _int(op['status_code']);
        break;
      case RewriteType.redirect:
        item.redirectUrl = op['target_url']?.toString();
        break;
    }
    return item;
  }

  static List<RewriteItem> _parseRewriteOps(dynamic ops) {
    if (ops is! List) throw ToolException('operations must be a list of operation objects');
    return ops.map((e) => _rewriteItemFromArgs((e as Map).cast<String, dynamic>())).toList();
  }

  static Map<String, dynamic> _rewriteItemToJson(RewriteItem item) {
    var map = <String, dynamic>{'op': item.type.name, 'enabled': item.enabled};
    if (item.key != null) map['key'] = item.key;
    if (item.value != null) map['value'] = item.value;
    map['use_regex'] = item.useRegex;
    if (item.redirectUrl != null) map['target_url'] = item.redirectUrl;
    if (item.method != null) map['method'] = item.method!.name;
    if (item.path != null) map['path'] = item.path;
    if (item.queryParam != null) map['query'] = item.queryParam;
    if (item.statusCode != null) map['status_code'] = item.statusCode;
    if (item.headers != null) map['headers'] = item.headers;
    if (item.body != null) map['body'] = item.body;
    if (item.bodyType != null) map['body_type'] = item.bodyType;
    return map;
  }

  McpTool _createRewrite() => McpTool(
        name: 'create_rewrite',
        description:
            'Create a rewrite rule. `type` is optional: requestUpdate/responseUpdate/requestReplace/responseReplace (use create_redirect for redirect). `operations` is a list of ops; each op has `op` (addHeader/updateHeader/removeHeader/addQueryParam/updateQueryParam/removeQueryParam/updateBody/replaceRequestLine/replaceRequestHeader/replaceRequestBody/replaceResponseStatus/replaceResponseHeader/replaceResponseBody) plus fields (`key`, `value`, `use_regex`, `method`, `path`, `query`, `status_code`, `headers`, `body`, `body_type`). If `type` is omitted it is inferred from the ops.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'url': {'type': 'string', 'description': 'Wildcard URL pattern'},
            'type': {
              'type': 'string',
              'enum': ['requestUpdate', 'responseUpdate', 'requestReplace', 'responseReplace']
            },
            'name': {'type': 'string'},
            'method': {'type': 'string', 'description': 'Optional HTTP method filter'},
            'enabled': {'type': 'boolean'},
            'operations': {'type': 'array', 'items': {'type': 'object'}},
          },
          'required': ['url'],
        },
        handler: (a) async {
          var url = a['url']?.toString();
          if (url == null || url.isEmpty) throw ToolException('url is required');
          var ops = _parseRewriteOps(a['operations'] ?? []);

          RuleType type;
          if (a['type'] != null) {
            type = RuleType.fromName(a['type'].toString());
          } else {
            type = _inferRewriteType(ops);
          }
          // 显式指定或推断出的类型都要校验操作归属，避免生成运行时被静默忽略的无效规则
          var allowed = _opsForRuleType(type);
          var invalid = ops.where((o) => !allowed.contains(o.type)).toList();
          if (invalid.isNotEmpty) {
            throw ToolException(
                'ops not allowed for type ${type.name}: ${invalid.map((o) => o.type.name).join(', ')}');
          }

          var rule = RequestRewriteRule(url: url, name: a['name']?.toString(), type: type);
          if (a['method'] != null) rule.method = HttpMethod.valueOf(a['method'].toString());
          if (a['enabled'] is bool) rule.enabled = a['enabled'] as bool;

          var mgr = await RequestRewriteManager.instance;
          await mgr.addRule(rule, ops);
          await mgr.flushRequestRewriteConfig();
          return {'created': true, 'index': mgr.rules.length - 1, 'type': type.name, 'url': url};
        },
      );

  McpTool _updateRewrite() => McpTool(
        name: 'update_rewrite',
        description:
            'Update a rewrite rule by index: URL wildcard, name, method, enabled, and/or replace its operations list. Only the fields you pass change; passing `operations` replaces the whole list. For redirect rules use update_redirect.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'index': {'type': 'integer'},
            'url': {'type': 'string'},
            'name': {'type': 'string'},
            'method': {'type': 'string'},
            'enabled': {'type': 'boolean'},
            'operations': {'type': 'array', 'items': {'type': 'object'}},
          },
          'required': ['index'],
        },
        handler: (a) async {
          var mgr = await RequestRewriteManager.instance;
          var index = _int(a['index']);
          if (index == null || index < 0 || index >= mgr.rules.length) throw ToolException('invalid index');
          var rule = mgr.rules[index];

          var items = a['operations'] != null
              ? _parseRewriteOps(a['operations'])
              : (await mgr.getRewriteItems(rule)) ?? [];
          if (a['operations'] != null) {
            var allowed = _opsForRuleType(rule.type);
            var invalid = items.where((o) => !allowed.contains(o.type)).toList();
            if (invalid.isNotEmpty) {
              throw ToolException(
                  'ops not allowed for type ${rule.type.name}: ${invalid.map((o) => o.type.name).join(', ')}');
            }
          }
          if (a['url'] != null) rule.url = a['url'].toString();
          if (a['name'] != null) rule.name = a['name'].toString();
          if (a['method'] != null) rule.method = HttpMethod.valueOf(a['method'].toString());
          if (a['enabled'] is bool) rule.enabled = a['enabled'] as bool;

          await mgr.updateRule(index, rule, items);
          await mgr.flushRequestRewriteConfig();
          return {'updated': true, 'index': index, 'url': rule.url};
        },
      );

  McpTool _getRewriteDetail() => McpTool(
        name: 'get_rewrite_detail',
        description: 'Get one rewrite rule by index: URL, type, enabled, method and its operations list (op/key/value/use_regex/...).',
        inputSchema: {
          'type': 'object',
          'properties': {
            'index': {'type': 'integer'},
          },
          'required': ['index'],
        },
        handler: (a) async {
          var mgr = await RequestRewriteManager.instance;
          var index = _int(a['index']);
          if (index == null || index < 0 || index >= mgr.rules.length) throw ToolException('invalid index');
          var rule = mgr.rules[index];
          var items = await mgr.getRewriteItems(rule) ?? [];
          return {
            'index': index,
            'name': rule.name,
            'url': rule.url,
            'enabled': rule.enabled,
            'type': rule.type.name,
            'method': rule.method?.name,
            'operations': items.map(_rewriteItemToJson).toList(),
          };
        },
      );

  // ------------------------------------------------------------- host filter

  HostList _hostList(String? name) {
    switch (name) {
      case 'whitelist':
        return HostFilter.whitelist;
      case 'blacklist':
        return HostFilter.blacklist;
      default:
        throw ToolException('list must be "whitelist" or "blacklist"');
    }
  }

  McpTool _listHosts() => McpTool(
        name: 'list_hosts',
        description:
            'List host filter lists. Whitelist (when enabled) captures ONLY the listed hosts; blacklist skips the listed hosts. Returns patterns and enabled state for each list.',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async {
          await Configuration.instance;
          Map<String, dynamic> listJson(HostList l) =>
              {'enabled': l.enabled, 'patterns': l.list.map((e) => e.pattern).toList()};
          return {
            'whitelist': listJson(HostFilter.whitelist),
            'blacklist': listJson(HostFilter.blacklist),
          };
        },
      );

  McpTool _addHost() => McpTool(
        name: 'add_host',
        description: 'Add a host pattern to the whitelist or blacklist. `*` is a wildcard, e.g. "*.example.com".',
        inputSchema: {
          'type': 'object',
          'properties': {
            'list': {'type': 'string', 'enum': ['whitelist', 'blacklist']},
            'pattern': {'type': 'string'},
          },
          'required': ['list', 'pattern'],
        },
        handler: (a) async {
          var config = await Configuration.instance;
          var listName = a['list']?.toString();
          var pattern = a['pattern']?.toString();
          if (pattern == null || pattern.isEmpty) throw ToolException('pattern is required');
          var list = _hostList(listName);
          list.add(pattern);
          await config.flushConfig();
          return {'added': true, 'list': listName, 'pattern': pattern};
        },
      );

  McpTool _removeHost() => McpTool(
        name: 'remove_host',
        description: 'Remove a host pattern from the whitelist or blacklist.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'list': {'type': 'string', 'enum': ['whitelist', 'blacklist']},
            'pattern': {'type': 'string'},
          },
          'required': ['list', 'pattern'],
        },
        handler: (a) async {
          var config = await Configuration.instance;
          var listName = a['list']?.toString();
          var pattern = a['pattern']?.toString();
          if (pattern == null || pattern.isEmpty) throw ToolException('pattern is required');
          var list = _hostList(listName);
          list.remove(pattern);
          await config.flushConfig();
          return {'removed': true, 'list': listName, 'pattern': pattern};
        },
      );

  McpTool _setHostsEnabled() => McpTool(
        name: 'set_hosts_enabled',
        description: 'Enable or disable a host filter list (whitelist/blacklist).',
        inputSchema: {
          'type': 'object',
          'properties': {
            'list': {'type': 'string', 'enum': ['whitelist', 'blacklist']},
            'enabled': {'type': 'boolean'},
          },
          'required': ['list', 'enabled'],
        },
        handler: (a) async {
          var config = await Configuration.instance;
          var listName = a['list']?.toString();
          var list = _hostList(listName);
          list.enabled = a['enabled'] is bool && a['enabled'] as bool;
          await config.flushConfig();
          return {'list': listName, 'enabled': list.enabled};
        },
      );

  McpTool _createScript() => McpTool(
        name: 'create_script',
        description:
            'Create a JavaScript rule matching `urls` (comma separated or list). Provide `script`; if omitted a starter template is used. `remote_url` makes it a remote script fetched from the URL. The script runs on request/response and can modify them.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
            'urls': {
              'oneOf': [
                {'type': 'string'},
                {'type': 'array', 'items': {'type': 'string'}}
              ]
            },
            'script': {'type': 'string'},
            'remote_url': {'type': 'string'},
            'enabled': {'type': 'boolean'},
          },
          'required': ['urls'],
        },
        handler: (a) async {
          dynamic urls = a['urls'];
          if (urls == null) throw ToolException('urls is required');
          var item = ScriptItem(
            a['enabled'] is bool ? a['enabled'] as bool : true,
            a['name']?.toString() ?? 'MCP script',
            urls,
            remoteUrl: a['remote_url']?.toString(),
          );
          var mgr = await ScriptManager.instance;
          await mgr.addScript(item, a['script']?.toString());
          await mgr.flushConfig();
          return {'created': true, 'index': mgr.list.length - 1, 'urls': item.urls};
        },
      );

  McpTool _updateScript() => McpTool(
        name: 'update_script',
        description:
            'Update an existing script rule by index: matching URLs, script body, name, enabled and/or remote_url. Only the fields you pass change.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'index': {'type': 'integer'},
            'urls': {
              'oneOf': [
                {'type': 'string'},
                {'type': 'array', 'items': {'type': 'string'}}
              ]
            },
            'script': {'type': 'string'},
            'name': {'type': 'string'},
            'enabled': {'type': 'boolean'},
            'remote_url': {'type': 'string'},
          },
          'required': ['index'],
        },
        handler: (a) async {
          var mgr = await ScriptManager.instance;
          var index = _int(a['index']);
          if (index == null || index < 0 || index >= mgr.list.length) throw ToolException('invalid index');
          var item = mgr.list[index];
          if (a['urls'] != null) {
            dynamic urls = a['urls'];
            var newUrls = urls is String
                ? (urls.contains(',') ? urls.split(',').map((e) => e.trim()).toList() : [urls])
                : (urls is List ? urls.map((e) => e.toString()).toList() : <String>[]);
            item.urls..clear()..addAll(newUrls);
            item.urlRegs = null;
          }
          if (a['name'] != null) item.name = a['name'].toString();
          if (a['enabled'] is bool) item.enabled = a['enabled'] as bool;
          if (a['remote_url'] != null) item.remoteUrl = a['remote_url'].toString();
          if (a['script'] != null) await mgr.updateScript(item, a['script'].toString());
          await mgr.flushConfig();
          return {'updated': true, 'index': index, 'name': item.name, 'urls': item.urls};
        },
      );

  McpTool _getScriptTemplate() => McpTool(
        name: 'get_script_template',
        description: 'Get the built-in JavaScript script template (onRequest/onResponse skeleton) to author scripts.',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async => {'template': ScriptManager.template},
      );

  McpTool _getScriptDetail() => McpTool(
        name: 'get_script_detail',
        description:
            'Get one script rule by index: name, urls, enabled, remoteUrl and its full JavaScript body (for remote scripts, the fetched/cached body).',
        inputSchema: {
          'type': 'object',
          'properties': {'index': {'type': 'integer'}},
          'required': ['index'],
        },
        handler: (a) async {
          var mgr = await ScriptManager.instance;
          var index = _int(a['index']);
          if (index == null || index < 0 || index >= mgr.list.length) throw ToolException('invalid index');
          var item = mgr.list[index];
          return {
            'index': index,
            'name': item.name,
            'urls': item.urls,
            'enabled': item.enabled,
            'remoteUrl': item.remoteUrl,
            'script': await mgr.getScript(item),
          };
        },
      );

  McpTool _removeScript() => McpTool(
        name: 'remove_script',
        description: 'Remove a script rule by index, or enable/disable scripting globally.',
        inputSchema: {
          'type': 'object',
          'properties': {'index': {'type': 'integer'}, 'enabled': {'type': 'boolean'}},
        },
        handler: (a) async {
          var mgr = await ScriptManager.instance;
          if (a['enabled'] is bool) {
            mgr.enabled = a['enabled'] as bool;
            await mgr.flushConfig();
            return {'enabled': mgr.enabled};
          }
          var index = _int(a['index']);
          if (index == null || index < 0 || index >= mgr.list.length) throw ToolException('invalid index');
          await mgr.removeScript(index);
          await mgr.flushConfig();
          return {'removed': true, 'index': index};
        },
      );

  // ------------------------------------------------------- environment

  McpTool _toggleRecording() => McpTool(
        name: 'toggle_recording',
        description:
            'Start or stop traffic recording by starting/stopping the local proxy server. When enabled=false the system proxy is restored and capture halts.',
        inputSchema: {
          'type': 'object',
          'properties': {'enabled': {'type': 'boolean'}},
          'required': ['enabled'],
        },
        handler: (a) async {
          var server = ProxyServer.current;
          if (server == null) throw ToolException('Proxy server is not initialized');
          var enabled = a['enabled'] == true;
          if (enabled && !server.isRunning) {
            await server.start();
          } else if (!enabled && server.isRunning) {
            await server.stop();
          }
          return {'recording': server.isRunning};
        },
      );

  McpTool _enableSslProxying() => McpTool(
        name: 'enable_ssl_proxying',
        description:
            'Enable HTTPS interception (SSL MITM) globally and ensure `domain` is not on the blacklist. The CA certificate must be trusted on the device first (see get_certificate_status).',
        inputSchema: {
          'type': 'object',
          'properties': {
            'enabled': {'type': 'boolean'},
            'domain': {'type': 'string', 'description': 'Optional domain to ensure is not blacklisted'},
          },
        },
        handler: (a) async {
          var enabled = a['enabled'] is bool ? a['enabled'] as bool : true;
          var server = ProxyServer.current;
          if (server == null) throw ToolException('Proxy server is not initialized');
          server.enableSsl = enabled;
          var domain = a['domain']?.toString();
          if (domain != null && domain.isNotEmpty) {
            HostFilter.blacklist.remove(domain);
          }
          await server.configuration.flushConfig();
          return {'sslInterception': enabled, if (domain != null) 'domain': domain};
        },
      );

  McpTool _setSystemProxy() => McpTool(
        name: 'set_system_proxy',
        description: 'Turn the operating-system HTTP/HTTPS proxy setting on or off (desktop only).',
        inputSchema: {
          'type': 'object',
          'properties': {'enabled': {'type': 'boolean'}},
          'required': ['enabled'],
        },
        handler: (a) async {
          var enabled = a['enabled'] is bool && a['enabled'] == true;
          var server = ProxyServer.current;
          if (server == null) throw ToolException('Proxy server is not initialized');
          await server.setSystemProxyEnable(enabled);
          await server.configuration.flushConfig();
          return {'systemProxy': enabled};
        },
      );

  McpTool _getCertificateStatus() => McpTool(
        name: 'get_certificate_status',
        description: 'Get whether the ProxyPin root CA is installed/trusted on this machine (desktop).',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async {
          if (certStatusProvider != null) {
            return await certStatusProvider!();
          }
          return {'available': false, 'reason': 'certificate status is only available in the desktop app'};
        },
      );

  // ------------------------------------------------------------- traffic

  Future<Map<String, dynamic>> _send(HttpRequest request) async {
    ProxyInfo? proxyInfo;
    var server = ProxyServer.current;
    if (server != null && server.isRunning) {
      proxyInfo = ProxyInfo.of('127.0.0.1', server.port);
    }
    HttpResponse response;
    try {
      response = await HttpClients.proxyRequest(request, proxyInfo: proxyInfo).timeout(const Duration(seconds: 30));
    } catch (e) {
      throw ToolException('request failed: $e');
    }
    var body = await FlowView.bodySlice(response, offset: 0, limit: FlowView.defaultPreviewBytes);
    return {
      'status': response.status.code,
      'statusText': response.status.reasonPhrase,
      'headers': _redactHeaders(response.headers.toMap()),
      'body': body,
    };
  }

  /// 与 FlowView 保持一致，敏感头一律打码后再交给 AI
  static const _sensitiveHeaders = {'authorization', 'proxy-authorization', 'cookie', 'set-cookie'};

  static Map<String, dynamic> _redactHeaders(Map<String, dynamic> headers) {
    var out = <String, dynamic>{};
    headers.forEach((k, v) {
      out[k] = _sensitiveHeaders.contains(k.toLowerCase()) ? '***redacted***' : v;
    });
    return out;
  }

  McpTool _replayFlow() => McpTool(
        name: 'replay_flow',
        description:
            'Re-send a captured request (by id) through the running proxy and return the fresh response (status, headers, body preview).',
        inputSchema: {
          'type': 'object',
          'properties': {'id': {'type': 'string'}},
          'required': ['id'],
        },
        handler: (a) async {
          var original = _requireFlow(a['id']?.toString());
          var copy = original.copy();
          copy.body = original.body;
          return await _send(copy);
        },
      );

  McpTool _sendRequest() => McpTool(
        name: 'send_request',
        description:
            'Build and send a new HTTP request. Either provide `curl` (raw cURL command) or method/url/headers/body. Returns status, headers and a body preview.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'curl': {'type': 'string'},
            'method': {'type': 'string'},
            'url': {'type': 'string'},
            'headers': {'type': 'object', 'additionalProperties': {'type': 'string'}},
            'body': {'type': 'string'},
          },
        },
        handler: (a) async {
          HttpRequest request;
          var curl = a['curl']?.toString();
          if (curl != null && curl.trim().isNotEmpty) {
            request = Curl.parse(curl);
          } else {
            var url = a['url']?.toString();
            if (url == null || url.isEmpty) throw ToolException('url or curl is required');
            var method = HttpMethod.valueOf(a['method']?.toString() ?? 'GET');
            request = HttpRequest(method, url);
            (a['headers'] as Map?)?.forEach((k, v) => request.headers.add(k.toString(), v.toString()));
            var body = a['body']?.toString();
            if (body != null) request.body = utf8.encode(body);
          }
          return await _send(request);
        },
      );

  McpTool _addFavorite() => McpTool(
        name: 'add_favorite',
        description: 'Save a captured flow (by id) to Favorites for later reuse.',
        inputSchema: {
          'type': 'object',
          'properties': {'id': {'type': 'string'}},
          'required': ['id'],
        },
        handler: (a) async {
          var request = _requireFlow(a['id']?.toString());
          await FavoriteStorage.addFavorite(request);
          return {'saved': true, 'id': request.requestId};
        },
      );

  McpTool _clearSession() => McpTool(
        name: 'clear_session',
        description: 'Clear all currently captured flows (both the MCP buffer and the app capture list). Destructive.',
        inputSchema: {'type': 'object', 'properties': {'confirm': {'type': 'boolean'}}},
        handler: (a) async {
          if (a['confirm'] != true) {
            throw ToolException('Pass confirm:true to clear the session');
          }
          store.clear();
          await onClearSession?.call();
          return {'cleared': true};
        },
      );

  McpTool _generateCode() => McpTool(
        name: 'generate_code',
        description: 'Generate runnable code for a captured flow. language: curl (default), fetch (JS), or python (requests).',
        inputSchema: {
          'type': 'object',
          'properties': {
            'id': {'type': 'string'},
            'language': {'type': 'string', 'enum': ['curl', 'fetch', 'python']},
            'redact': {'type': 'boolean'},
          },
          'required': ['id'],
        },
        handler: (a) async {
          var request = _requireFlow(a['id']?.toString());
          var lang = a['language']?.toString() ?? 'curl';
          var redact = a['redact'] is bool ? a['redact'] as bool : true;
          return {'language': lang, 'code': CurlBuilder.code(request, lang, redact: redact)};
        },
      );

  static int? _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
