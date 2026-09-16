import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/components/js/script_engine.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';

void main() {
  HttpHeaders buildResponseWithSetCookies() {
    final headers = HttpHeaders();
    headers.add('Set-Cookie', 'session_id=abc123; path=/');
    headers.add('Set-Cookie', 'logout_flag=deleted; Max-Age=0; path=/');
    return headers;
  }

  test('toMap preserves multi-value Set-Cookie as array instead of joining', () {
    final headers = buildResponseWithSetCookies();
    headers.set('Content-Type', 'text/html');

    final map = headers.toMap();

    expect(map['Set-Cookie'], [
      'session_id=abc123; path=/',
      'logout_flag=deleted; Max-Age=0; path=/',
    ]);
    // 单值 header 仍然保持字符串
    expect(map['Content-Type'], 'text/html');
  });

  test('convertHttpResponse round-trip keeps Set-Cookie as independent values', () async {
    final response = HttpResponse(HttpStatus.ok)
      ..headers.addAll(buildResponseWithSetCookies())
      ..body = utf8.encode('<h1>ok</h1>');

    // 模拟脚本读取响应后原样返回(经过 JS 序列化)
    final jsResponse = jsonDecode(jsonEncode(await JavaScriptEngine.convertJsResponse(response))) as Map;
    final rebuilt = JavaScriptEngine.convertHttpResponse(response, jsResponse);

    expect(rebuilt.headers.getList('Set-Cookie'), [
      'session_id=abc123; path=/',
      'logout_flag=deleted; Max-Age=0; path=/',
    ]);
  });

  test('codec encode emits each Set-Cookie value as its own header line', () {
    final response = HttpResponse(HttpStatus.ok)
      ..headers.addAll(buildResponseWithSetCookies())
      ..body = utf8.encode('<h1>ok</h1>');

    final raw = utf8.decode(HttpResponseCodec().encode(ChannelContext(), response));
    final setCookieLines =
        raw.split('\r\n').where((l) => l.toLowerCase().startsWith('set-cookie:')).toList();
    expect(setCookieLines, hasLength(2));
    expect(setCookieLines[0], 'Set-Cookie: session_id=abc123; path=/');
    expect(setCookieLines[1], 'Set-Cookie: logout_flag=deleted; Max-Age=0; path=/');
  });
}