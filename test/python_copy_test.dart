import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/utils/python.dart';

HttpRequest _request(String method, String uri) => HttpRequest(HttpMethod.valueOf(method), uri);

void main() {
  test('GET with headers and cookies', () {
    final request = _request('GET', 'https://example.com/api?a=1');
    request.headers.set('User-Agent', 'Mozilla/5.0');
    request.headers.set('Accept', 'application/json');
    request.headers.set('Cookie', 'session_id=123456; user=john');
    request.headers.set('Content-Length', '0'); // 必须被忽略

    final py = copyAsPythonRequests(request);

    expect(py, contains("url = 'https://example.com/api?a=1'"));
    expect(py, contains("'session_id': '123456'"));
    expect(py, contains("'user': 'john'"));
    // header 值不能被截断
    expect(py, contains("'User-Agent': 'Mozilla/5.0'"));
    expect(py, contains("'Accept': 'application/json'"));
    expect(py, isNot(contains('Content-Length')));
    expect(py, contains('cookies=cookies'));
    expect(py, contains('requests.get('));
  });

  test('JSON body is pretty printed and uses json=', () {
    final request = _request('POST', 'https://example.com/login');
    request.headers.contentType = 'application/json; charset=utf-8';
    request.body = utf8.encode(jsonEncode({'name': '张三', 'age': 20, 'ok': true, 'none': null}));

    final py = copyAsPythonRequests(request);

    expect(py, contains('json_data = {'));
    expect(py, contains("'name': '张三'"));
    expect(py, contains("'age': 20"));
    expect(py, contains("'ok': True"));
    expect(py, contains("'none': None"));
    expect(py, contains('json=json_data'));
    // Content-Type 交给 requests 自动生成
    expect(py, isNot(contains('Content-Type')));
  });

  test('form-urlencoded body uses data dict', () {
    final request = _request('POST', 'https://example.com/form');
    request.headers.contentType = 'application/x-www-form-urlencoded';
    request.body = utf8.encode('name=hello&age=30');

    final py = copyAsPythonRequests(request);

    expect(py, contains('data = {'));
    expect(py, contains("'name': 'hello'"));
    expect(py, contains("'age': '30'"));
    expect(py, contains('data=data'));
  });

  test('special characters are escaped without scrambling', () {
    final request = _request('POST', 'https://example.com/x');
    request.headers.set('X-Custom', "a\"b'c");
    request.body = utf8.encode('line1\nline2\ttab');

    final py = copyAsPythonRequests(request);
    expect(py, contains("a\"b\\'c")); // a"b\'c —— 双引号原样，单引号转义
    expect(py, contains('data = '));
  });

  test('same-name multi-value header is comma-joined, not a list', () {
    final request = _request('GET', 'https://example.com/a');
    request.headers.add('X-Multi', 'v1');
    request.headers.add('X-Multi', 'v2');

    final py = copyAsPythonRequests(request);
    expect(py, contains("'X-Multi': 'v1, v2'"));
    expect(py, isNot(contains('[')));
  });

  test('non-standard method falls back to requests.request()', () {
    final request = _request('PROPFIND', 'https://example.com/dav');
    final py = copyAsPythonRequests(request);
    expect(py, contains("requests.request('PROPFIND', url)"));
  });

  test('multipart body uses files dict with file bytes', () {
    final request = _request('POST', 'https://example.com/up');
    request.headers.contentType = 'multipart/form-data; boundary=----X';
    final body = StringBuffer();
    void part(String h, String v) {
      body.writeln('------X');
      body.writeln(h);
      body.writeln();
      body.writeln(v);
    }
    part('Content-Disposition: form-data; name="title"', 'hello');
    part('Content-Disposition: form-data; name="f"; filename="a.txt"', 'file-bytes');
    body.write('------X--');
    request.body = utf8.encode(body.toString());

    final py = copyAsPythonRequests(request);
    expect(py, contains("'title': (None, 'hello')"));
    expect(py, contains("'f': ('a.txt', b'file-bytes')"));
    expect(py, contains('files=files'));
  });

  test('generated Python compiles', () async {
    final request = _request('POST', 'https://example.com/login');
    request.headers.contentType = 'application/json';
    request.headers.set('Cookie', 'sid=abc; q=z');
    request.body = utf8.encode(jsonEncode({'k': 'v', 'list': [1, 2]}));

    final py = copyAsPythonRequests(request);

    // 有 python3 时做真实语法校验
    final tmp = File('${Directory.systemTemp.path}/proxypin_py_${DateTime.now().microsecondsSinceEpoch}.py')
      ..writeAsString(py);
    addTearDown(() => tmp.delete());
    final result = await Process.run('python3', ['-m', 'py_compile', tmp.path]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
  }, skip: !_hasPython3());
}

bool _hasPython3() {
  try {
    final r = Process.runSync('python3', ['--version']);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}
