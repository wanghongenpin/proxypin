import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/mcp/capture/curl_builder.dart';
import 'package:proxypin/mcp/capture/flow_store.dart';
import 'package:proxypin/mcp/capture/flow_view.dart';
import 'package:proxypin/mcp/protocol/mcp_actions.dart';
import 'package:proxypin/mcp/protocol/mcp_server.dart';
import 'package:proxypin/mcp/transport/mcp_http_server.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/util/file_read.dart';

void check(bool cond, String msg) {
  expect(cond, isTrue, reason: msg);
}

HttpRequest buildFlow({required int responseSize, bool binary = false, bool withAuth = true}) {
  var request = HttpRequest(HttpMethod.post, 'https://api.example.com/v1/login');
  request.headers.set('Host', 'api.example.com');
  request.headers.set('Content-Type', 'application/json');
  if (withAuth) request.headers.set('Authorization', 'Bearer secret-token');
  request.headers.set('Cookie', 'sid=abc123');
  request.body = utf8.encode(jsonEncode({'email': 'a@b.com', 'password': 'pw'}));

  var response = HttpResponse(HttpStatus.ok);
  if (binary) {
    response.headers.set('Content-Type', 'image/png');
    response.body = Uint8List.fromList(List.generate(5000, (i) => i % 256));
  } else {
    response.headers.set('Content-Type', 'application/json; charset=utf-8');
    response.body = utf8.encode(jsonEncode({'data': 'x' * responseSize}));
  }
  response.request = request;
  request.response = response;
  return request;
}

void main() {
  // 所有写工具落到临时目录，避免污染真实 ~/.proxypin
  FileRead.userHome =
      '${Directory.systemTemp.path}${Platform.pathSeparator}mcp_test_${DateTime.now().millisecondsSinceEpoch}';

  test('mcp flow store/view/curl behavior', () async {
  // ---- summary has no body/header leakage ----
  var big = buildFlow(responseSize: 20000);
  var store = FlowStore();
  store.backfill([big]);
  var listed = store.query(limit: 20);
  check(listed.length == 1, 'query returns one');
  var summary = FlowView.summary(listed.first);
  check(!summary.containsKey('headers'), 'summary has no headers');
  check(!summary.containsKey('body'), 'summary has no body');
  check(summary['status'] == 200, 'summary status');
  check(summary['id'] == big.requestId, 'summary id');

  // ---- detail redacts by default + previews body ----
  var detail = await FlowView.detail(big, redact: true, previewBytes: 8192);
  var reqHeaders = (detail['request']['headers'] as List).map((e) => e as Map).toList();
  var auth = reqHeaders.firstWhere((h) => h['name'].toLowerCase() == 'authorization');
  check(auth['value'] == '***redacted***', 'authorization redacted');
  var cookie = reqHeaders.firstWhere((h) => h['name'].toLowerCase() == 'cookie');
  check(cookie['value'] == '***redacted***', 'cookie redacted');

  var respBody = detail['response']['body'] as Map;
  check(respBody['truncated'] == true, 'preview truncated for >8KB body');
  check((respBody['text'] as String).length <= 8192, 'preview within 8KB');
  check(respBody['total'] > 8192, 'total reported');

  // ---- bodySlice pagination + hard cap ----
  var page1 = await FlowView.bodySlice(big.response, offset: 0, limit: 4096);
  check(page1['offset'] == 0 && page1['returned'] == 4096, 'first page 4096');
  check(page1['truncated'] == true, 'page1 truncated');
  var page2 = await FlowView.bodySlice(big.response, offset: 4096, limit: 1000000);
  check(page2['returned'] <= FlowView.maxBodySliceBytes, 'hard cap 64KB');
  check(page2['offset'] == 4096, 'page2 offset');

  // ---- binary is never inlined ----
  var img = buildFlow(responseSize: 0, binary: true);
  var binSlice = await FlowView.bodySlice(img.response);
  check(binSlice['binary'] == true, 'binary flagged');
  check(binSlice['mimeType'] == 'image/png', 'binary mime');
  check(!binSlice.containsKey('text'), 'binary has no text');
  check((binSlice['sha256'] as String).length == 64, 'binary sha256');

  // ---- redact=false exposes real value ----
  var rawDetail = await FlowView.detail(big, redact: false, previewBytes: 256);
  var rawAuth = (rawDetail['request']['headers'] as List)
      .map((e) => e as Map)
      .firstWhere((h) => h['name'].toLowerCase() == 'authorization');
  check(rawAuth['value'] == 'Bearer secret-token', 'unredacted exposes token');

  // ---- curl export ----
  var curlRedacted = CurlBuilder.build(big, redact: true);
  check(curlRedacted.contains('***redacted***'), 'curl redacted');
  check(!curlRedacted.contains('secret-token'), 'curl leaks no token');
  check(!curlRedacted.contains('abc123'), 'curl leaks no cookie');
  var curlRaw = CurlBuilder.build(big, redact: false);
  check(curlRaw.contains('secret-token'), 'curl raw contains token');

  // ---- filters ----
  var other = buildFlow(responseSize: 10);
  other.uri = 'https://other.test/path';
  store.backfill([other]);
  check(store.query(host: 'other').length == 1, 'host filter');
  check(store.query(method: 'POST').length == 2, 'method filter');
  check(store.query(host: 'nomatch').isEmpty, 'no match filter');
  });

  test('mcp json-rpc initialize / tools / call', () async {
    var flow = buildFlow(responseSize: 100);
    var store = FlowStore()..backfill([flow]);
    var mcp = McpServer(store: store, scope: () => 'minimal', redactEnabled: () => true);

    var init = await mcp.handle({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {}});
    check(init!['result']['protocolVersion'] == '2024-11-05', 'initialize protocol version');
    check(init['result']['serverInfo']['name'] == 'proxypin', 'initialize server name');

    var list = await mcp.handle({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'});
    var tools = list!['result']['tools'] as List;
    var names = tools.map((t) => (t as Map)['name']).toSet();
    check(names.contains('list_flows'), 'tools/list has list_flows');
    check(names.contains('get_flow_detail'), 'tools/list has get_flow_detail');
    check(names.contains('export_flow_curl'), 'tools/list has export_flow_curl');
    check(names.contains('search_flows'), 'tools/list has search_flows');
    check(names.contains('get_ssl_proxying_list'), 'tools/list has get_ssl_proxying_list');
    check(tools.length == 8, 'minimal scope exposes 8 read-only tools, got ${tools.length}');

    var call = await mcp.handle({
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': {'name': 'list_flows', 'arguments': {'limit': 5}}
    });
    var content = call!['result']['content'][0]['text'] as String;
    var payload = jsonDecode(content) as Map;
    check(payload['count'] == 1, 'list_flows returns one');
    check(call['result']['isError'] == false, 'list_flows not error');

    var missing = await mcp.handle({
      'jsonrpc': '2.0',
      'id': 4,
      'method': 'tools/call',
      'params': {'name': 'get_flow_detail', 'arguments': {'id': 'does-not-exist'}}
    });
    check(missing!['result']['isError'] == true, 'unknown id returns tool error, not crash');

    var unknownMethod = await mcp.handle({'jsonrpc': '2.0', 'id': 5, 'method': 'nope'});
    check(unknownMethod!['error']['code'] == -32601, 'unknown method -> methodNotFound');
  });

  test('mcp body full-text search', () async {
    var hit = buildFlow(responseSize: 10);
    hit.uri = 'https://api.example.com/v1/order';
    hit.body = utf8.encode(jsonEncode({'orderId': 'ORDER-88'}));
    hit.response!.body = utf8.encode(jsonEncode({'error': 'rate_limit', 'code': 'ERROR-42'}));

    var other = buildFlow(responseSize: 10);
    other.uri = 'https://other.test/ping';
    other.response!.body = utf8.encode(jsonEncode({'status': 'ok'}));

    var img = buildFlow(responseSize: 0, binary: true);
    img.uri = 'https://img.test/logo.png';

    var store = FlowStore()..backfill([hit, other, img]);

    // 命中响应体
    var resp = await store.search('error-42');
    check(resp.length == 1 && resp.first.requestId == hit.requestId, 'response body hit');

    // 命中请求体
    var req = await store.search('order-88');
    check(req.length == 1 && req.first.requestId == hit.requestId, 'request body hit');

    // side 过滤
    var reqOnly = await store.search('error-42', side: 'request');
    check(reqOnly.isEmpty, 'side=request excludes response body');

    // 二进制跳过，无匹配
    var bin = await store.search('png');
    check(bin.isEmpty, 'binary body not searched');

    // 无匹配
    var none = await store.search('definitely-not-here');
    check(none.isEmpty, 'no match');

    // JSON-RPC 工具面
    var mcp = McpServer(store: store, scope: () => 'minimal', redactEnabled: () => true);
    var call = await mcp.handle({
      'jsonrpc': '2.0',
      'id': 9,
      'method': 'tools/call',
      'params': {'name': 'search_flows', 'arguments': {'keyword': 'ERROR-42', 'limit': 10}}
    });
    var content = call!['result']['content'][0]['text'] as String;
    var payload = jsonDecode(content) as Map;
    check(payload['count'] == 1, 'search_flows returns one');
    check((payload['flows'] as List).length == 1, 'search_flows flows length');

    // 缺少 keyword -> 工具错误而非崩溃
    var missing = await mcp.handle({
      'jsonrpc': '2.0',
      'id': 10,
      'method': 'tools/call',
      'params': {'name': 'search_flows', 'arguments': {}}
    });
    check(missing!['result']['isError'] == false, 'empty keyword tolerated');
    var emptyPayload = jsonDecode(missing['result']['content'][0]['text'] as String) as Map;
    check(emptyPayload['count'] == 0, 'empty keyword returns 0');
  });

  test('mcp scope gates write tools', () async {
    var store = FlowStore();
    var actions = McpActions(store: store);
    var writeToolNames = actions.tools().map((t) => t.name).toSet();
    check(writeToolNames.contains('create_breakpoint'), 'actions include create_breakpoint');
    check(writeToolNames.contains('clear_session'), 'actions include clear_session');
    check(writeToolNames.contains('toggle_recording'), 'actions include toggle_recording');
    check(writeToolNames.contains('get_script_detail'), 'actions include get_script_detail');
    for (var type in ['breakpoint', 'block', 'map_local', 'redirect', 'script']) {
      check(writeToolNames.contains('update_$type'), 'actions include update_$type');
    }

    var scope = 'minimal';
    var mcp = McpServer(store: store, scope: () => scope, redactEnabled: () => true, extraTools: actions.tools());

    Future<Set<String>> toolNames() async {
      var res = await mcp.handle({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'});
      return (res!['result']['tools'] as List).map((t) => (t as Map)['name'].toString()).toSet();
    }

    var minimal = await toolNames();
    check(minimal.length == 8, 'minimal exposes only 8 read tools, got ${minimal.length}');
    check(!minimal.contains('create_breakpoint'), 'minimal hides write tools');
    check(!minimal.contains('toggle_recording'), 'minimal hides toggle_recording');
    check(!minimal.contains('update_script'), 'minimal hides update tools');

    scope = 'all';
    var all = await toolNames();
    check(all.contains('create_breakpoint'), 'all exposes create_breakpoint');
    check(all.contains('replay_flow') && all.contains('generate_code'), 'all exposes replay/generate');
    check(all.length == 8 + writeToolNames.length, 'all exposes minimal + action tools');
  });

  test('mcp http transport: loopback initialize', () async {
    var flow = buildFlow(responseSize: 10);
    var mcp = McpServer(
        store: FlowStore()..backfill([flow]), scope: () => 'minimal', redactEnabled: () => true);
    var http = McpHttpServer(mcp: mcp);
    await http.start(0); // ephemeral port
    var port = http.port!;

    // loopback, no auth -> initialize 200
    final client = HttpClient();
    final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port/mcp'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {}}));
    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    final json = jsonDecode(text) as Map;
    check(resp.statusCode == 200, 'loopback http returns 200 without token');
    check(json['result']['serverInfo']['name'] == 'proxypin', 'http initialize ok');
    client.close(force: true);

    await http.stop();
  });

  test('mcp all-scope write tools: rewrite rules', () async {
    var store = FlowStore();
    var actions = McpActions(store: store);
    var mcp = McpServer(
        store: store, scope: () => 'all', redactEnabled: () => true, extraTools: actions.tools());

    Future<Map?> call(String name, Map args) async {
      var res = await mcp.handle({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': name, 'arguments': args}
      });
      var isError = res!['result']['isError'] == true;
      var text = res['result']['content'][0]['text'] as String;
      return {'isError': isError, 'payload': isError ? null : jsonDecode(text) as Map};
    }

    var created = <int>[];
    try {
      // requestUpdate 规则：加头 + 改体
      var created1 = await call('create_rewrite', {
        'url': '*.example.com',
        'type': 'requestUpdate',
        'operations': [
          {'op': 'addHeader', 'key': 'X-Debug', 'value': '1'},
          {'op': 'updateBody', 'key': 'old', 'value': 'new'},
        ]
      });
      check(created1!['isError'] == false, 'create_rewrite ok');
      var index = (created1['payload'] as Map)['index'] as int;
      check((created1['payload'] as Map)['type'] == 'requestUpdate', 'type requestUpdate');
      created.add(index);

      var detail = await call('get_rewrite_detail', {'index': index});
      var ops = ((detail!['payload'] as Map)['operations'] as List).cast<Map>();
      check(ops.length == 2, 'detail has 2 ops');
      check(ops.any((o) => o['op'] == 'addHeader' && o['key'] == 'X-Debug' && o['value'] == '1'), 'addHeader op present');

      // update：改 url + 禁用
      var updated = await call('update_rewrite', {'index': index, 'url': '*.new.example.com', 'enabled': false});
      check(updated!['isError'] == false, 'update_rewrite ok');
      var detail2 = await call('get_rewrite_detail', {'index': index});
      check((detail2!['payload'] as Map)['url'] == '*.new.example.com', 'url updated');
      check((detail2['payload'] as Map)['enabled'] == false, 'enabled updated');

      // 类型推断：replaceRequestBody -> requestReplace
      var inferred = await call('create_rewrite', {
        'url': '*.replace.test',
        'operations': [
          {'op': 'replaceRequestBody', 'body': '{}'}
        ]
      });
      check(inferred!['isError'] == false, 'create_rewrite inferred type');
      check((inferred['payload'] as Map)['type'] == 'requestReplace', 'inferred requestReplace');
      created.add((inferred['payload'] as Map)['index'] as int);

      // 类型不匹配 -> 工具错误而非崩溃
      var bad = await call('create_rewrite', {
        'url': '*.bad.test',
        'type': 'responseUpdate',
        'operations': [
          {'op': 'addQueryParam', 'key': 'a', 'value': 'b'}
        ]
      });
      check(bad!['isError'] == true, 'op not allowed for type rejected');

      // 推断类型下混入不兼容操作 -> 拒绝（此前会生成运行时静默失效的规则）
      var mixed = await call('create_rewrite', {
        'url': '*.mixed.test',
        'operations': [
          {'op': 'addHeader', 'key': 'X', 'value': '1'},
          {'op': 'replaceRequestBody', 'body': '{}'}
        ]
      });
      check(mixed!['isError'] == true, 'mixed ops under inferred type rejected');

      // 未知 op -> 工具错误
      var unknown = await call('create_rewrite', {
        'url': '*.u.test',
        'operations': [
          {'op': 'notARealOp'}
        ]
      });
      check(unknown!['isError'] == true, 'unknown op rejected');
    } finally {
      // 清理本次创建的规则（逆序删除避免索引偏移）
      for (var i = created.length - 1; i >= 0; i--) {
        await call('remove_rewrite_rule', {'index': created[i]});
      }
    }
  });

  test('mcp all-scope write tools: host filter', () async {
    var store = FlowStore();
    var actions = McpActions(store: store);
    var mcp = McpServer(
        store: store, scope: () => 'all', redactEnabled: () => true, extraTools: actions.tools());

    Future<Map?> call(String name, Map args) async {
      var res = await mcp.handle({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': name, 'arguments': args}
      });
      var isError = res!['result']['isError'] == true;
      var text = res['result']['content'][0]['text'] as String;
      return {'isError': isError, 'payload': isError ? null : jsonDecode(text) as Map};
    }

    var listed = await call('list_hosts', {});
    check(listed!['isError'] == false, 'list_hosts ok');
    check((listed['payload'] as Map).containsKey('whitelist'), 'list_hosts has whitelist');
    check((listed['payload'] as Map).containsKey('blacklist'), 'list_hosts has blacklist');

    var added = await call('add_host', {'list': 'whitelist', 'pattern': '*.test.dev'});
    check(added!['isError'] == false, 'add_host ok');
    var listed2 = await call('list_hosts', {});
    var wlPatterns = (((listed2!['payload'] as Map)['whitelist'] as Map)['patterns'] as List).cast<String>();
    check(wlPatterns.contains('.*.test.dev'), 'whitelist contains added pattern');

    await call('set_hosts_enabled', {'list': 'whitelist', 'enabled': true});
    var listed3 = await call('list_hosts', {});
    check(((listed3!['payload'] as Map)['whitelist'] as Map)['enabled'] == true, 'whitelist enabled');

    var removed = await call('remove_host', {'list': 'whitelist', 'pattern': '*.test.dev'});
    check(removed!['isError'] == false, 'remove_host ok');
    var listed4 = await call('list_hosts', {});
    var wlAfter = (((listed4!['payload'] as Map)['whitelist'] as Map)['patterns'] as List).cast<String>();
    check(!wlAfter.contains('.*.test.dev'), 'whitelist pattern removed');

    var badList = await call('add_host', {'list': 'nope', 'pattern': 'x.dev'});
    check(badList!['isError'] == true, 'invalid list name rejected');
  });

  test('flow store bounds websocket/sse frames per flow', () async {
    var store = FlowStore(maxFramesPerFlow: 3);
    var request = HttpRequest(HttpMethod.get, 'https://ws.example.com');
    var id = request.requestId;
    var server = await ServerSocket.bind('127.0.0.1', 0);
    var client = await Socket.connect('127.0.0.1', server.port);
    var channel = Channel(client);

    WebSocketFrame frame(int n) => WebSocketFrame(
        fin: true,
        opcode: 0x01,
        mask: false,
        maskingKey: 0,
        payloadLength: 1,
        payloadData: Uint8List.fromList([0x30 + n]));

    for (var i = 0; i < 10; i++) {
      store.onMessage(channel, request, frame(i));
    }
    var kept = store.frames(id);
    check(kept.length == 3, 'only last 3 frames kept, got ${kept.length}');
    check(kept.first.payloadData.first == 0x37, 'oldest dropped, keeps 7,8,9');

    // 有界列表同样被 messages 视图遵循
    var view = FlowView.messages(kept);
    check((view['frames'] as List).length == 3, 'messages view uses bounded frames');
    check(view['total'] == 3, 'messages total bounded');

    server.close();
    client.close();
  });

  test('mcp script template is available without runtime', () async {
    var store = FlowStore();
    var actions = McpActions(store: store);
    var mcp = McpServer(
        store: store, scope: () => 'all', redactEnabled: () => true, extraTools: actions.tools());
    var res = await mcp.handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {'name': 'get_script_template', 'arguments': {}}
    });
    var payload = jsonDecode(res!['result']['content'][0]['text'] as String) as Map;
    check(payload.containsKey('template'), 'get_script_template returns template');
    check((payload['template'] as String).contains('onRequest'), 'template has onRequest');
    check(res['result']['isError'] == false, 'get_script_template not error');
  });
}
