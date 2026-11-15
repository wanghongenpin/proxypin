import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/mcp/protocol/mcp_server.dart';
import 'package:proxypin/mcp/capture/flow_store.dart';
import 'package:proxypin/mcp/transport/mcp_http_server.dart';

void main() {
  test('GET /mcp/setup.sh returns script', () async {
    var server = McpHttpServer(
      mcp: McpServer(store: FlowStore(), redactEnabled: () => true),
      address: InternetAddress.loopbackIPv4,
      token: 'tok',
    );
    await server.start(0);
    var port = server.port!;

    final client = HttpClient();
    try {
      // 1) 无 token -> 401
      var r1 = await client.getUrl(Uri.parse('http://127.0.0.1:$port/mcp/setup.sh'));
      var resp1 = await r1.close();
      print('no-token status: ${resp1.statusCode}');
      expect(resp1.statusCode, 401);

      // 2) 带 token -> 200 且 body 非空
      var r2 = await client.getUrl(Uri.parse('http://127.0.0.1:$port/mcp/setup.sh'));
      r2.headers.set('Authorization', 'Bearer tok');
      var resp2 = await r2.close();
      var body = await resp2.transform(utf8.decoder).join();
      print('with-token status: ${resp2.statusCode}, len=${body.length}');
      print(body.substring(0, math.min(120, body.length)));
      expect(resp2.statusCode, 200);
      expect(body.isNotEmpty, true);

      // 3) ps1
      var r3 = await client.getUrl(Uri.parse('http://127.0.0.1:$port/mcp/setup.ps1'));
      r3.headers.set('Authorization', 'Bearer tok');
      var resp3 = await r3.close();
      var body3 = await resp3.transform(utf8.decoder).join();
      print('ps1 status: ${resp3.statusCode}, len=${body3.length}');
      expect(resp3.statusCode, 200);
      expect(body3.isNotEmpty, true);
    } finally {
      client.close(force: true);
      await server.stop();
    }
  });
  test('no-token setup scripts allow unauthenticated download without empty credentials', () async {
    var server = McpHttpServer(
      mcp: McpServer(store: FlowStore(), redactEnabled: () => true),
      address: InternetAddress.loopbackIPv4,
    );
    await server.start(0);
    final client = HttpClient();
    try {
      for (var script in ['setup.sh', 'setup.ps1']) {
        var request = await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/mcp/$script'));
        var response = await request.close();
        var body = await response.transform(utf8.decoder).join();
        expect(response.statusCode, 200);
        if (script == 'setup.sh') {
          expect(body, contains('if [ -n "\$TOKEN" ]'));
          expect(body, contains('TOKEN=""'));
        } else {
          expect(body, contains('if (\$Token)'));
          expect(body, contains("\$Token = ''"));
        }
      }
    } finally {
      client.close(force: true);
      await server.stop();
    }
  });
}
