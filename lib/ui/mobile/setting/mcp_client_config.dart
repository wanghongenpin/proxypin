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

import 'package:proxypin/mcp/mcp_names.dart';

/// 手机端 MCP 客户端配置。token 为空时不生成任何认证参数。
class McpMobileClientConfig {
  McpMobileClientConfig._();

  static String claudeCommand({required String endpoint, String? token}) {
    var command = 'claude mcp add ${McpClientNames.mobile} -s user --transport http $endpoint';
    return _hasToken(token) ? '$command --header "Authorization: Bearer $token"' : command;
  }

  static String codexCommand({required String endpoint, String? token}) {
    var command = StringBuffer();
    if (_hasToken(token)) command.writeln('export PROXYPIN_MOBILE_TOKEN="$token"');
    command.writeln('codex mcp remove ${McpClientNames.mobile} 2>/dev/null || true');
    command.write('codex mcp add ${McpClientNames.mobile} --url $endpoint');
    if (_hasToken(token)) command.write(' --bearer-token-env-var PROXYPIN_MOBILE_TOKEN');
    return command.toString();
  }

  static String oneClickShell({required String endpoint, String? token}) {
    var command = 'curl -s ';
    if (_hasToken(token)) command += '-H "Authorization: Bearer $token" ';
    return '$command$endpoint/setup.sh | sh';
  }

  static String oneClickPowershell({required String endpoint, String? token}) {
    var command = 'irm ';
    if (_hasToken(token)) command += '-Headers @{ Authorization = "Bearer $token" } ';
    return '$command$endpoint/setup.ps1 | iex';
  }

  static String genericHttpConfig({required String endpoint, String? token}) {
    var entry = <String, dynamic>{'type': 'http', 'url': endpoint};
    if (_hasToken(token)) {
      entry['headers'] = {'Authorization': 'Bearer $token'};
    }
    return const JsonEncoder.withIndent('  ').convert({
      'mcpServers': {McpClientNames.mobile: entry}
    });
  }

  static bool _hasToken(String? token) => token?.isNotEmpty ?? false;
}
