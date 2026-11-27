import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/ui/mobile/setting/mcp_client_config.dart';

void main() {
  const endpoint = 'http://192.168.1.23:9127/mcp';

  test('includes bearer credentials when token authentication is enabled', () {
    const token = 'secret';
    expect(McpMobileClientConfig.claudeCommand(endpoint: endpoint, token: token),
        contains('--header "Authorization: Bearer secret"'));
    expect(
        McpMobileClientConfig.codexCommand(endpoint: endpoint, token: token), contains('export PROXYPIN_MOBILE_TOKEN'));
    expect(McpMobileClientConfig.oneClickShell(endpoint: endpoint, token: token), contains('-H "Authorization:'));
    expect(McpMobileClientConfig.oneClickPowershell(endpoint: endpoint, token: token), contains('-Headers'));

    var config = jsonDecode(McpMobileClientConfig.genericHttpConfig(endpoint: endpoint, token: token));
    expect(config['mcpServers']['proxypin_mobile']['headers']['Authorization'], 'Bearer secret');
  });

  test('omits credentials when token authentication is disabled', () {
    var commands = [
      McpMobileClientConfig.claudeCommand(endpoint: endpoint),
      McpMobileClientConfig.codexCommand(endpoint: endpoint, token: ''),
      McpMobileClientConfig.oneClickShell(endpoint: endpoint),
      McpMobileClientConfig.oneClickPowershell(endpoint: endpoint, token: ''),
    ];
    for (var command in commands) {
      expect(command, contains(endpoint));
      expect(command, isNot(contains('Authorization')));
      expect(command, isNot(contains('TOKEN')));
    }
    expect(commands[0], isNot(contains('--header')));
    expect(commands[1], isNot(contains('--bearer-token-env-var')));

    var config = jsonDecode(McpMobileClientConfig.genericHttpConfig(endpoint: endpoint));
    var server = config['mcpServers']['proxypin_mobile'];
    expect(server['url'], endpoint);
    expect(server.containsKey('headers'), isFalse);
  });
}
