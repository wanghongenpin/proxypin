import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/utils/curl.dart';

void main() {
  test('多行反斜杠续行 + 全部 header + body', () {
    const cmd = r"""curl --http1.1 -L -X POST 'https://50.118.186.185:8090/api.php/app/analytics/report_ad_event' \
-H 'Host: 50.118.186.185:8090' \
-H 'Content-Type: application/json' \
-H 'x-sign: B2844B4817319A12557F6092D82D505B2AC31D60B8B8D6D61D7CB63E1C80E98F' \
-d '{"event":"splash_open","elapsed_ms":142}'""";

    final req = Curl.parse(cmd);
    expect(req.method, HttpMethod.post);
    expect(req.requestUrl, 'https://50.118.186.185:8090/api.php/app/analytics/report_ad_event');
    expect(req.protocolVersion, 'HTTP/1.1');
    expect(req.headers.get('Host'), '50.118.186.185:8090');
    expect(req.headers.get('Content-Type'), 'application/json');
    expect(req.headers.get('x-sign'),
        'B2844B4817319A12557F6092D82D505B2AC31D60B8B8D6D61D7CB63E1C80E98F');
    expect(String.fromCharCodes(req.body ?? []), '{"event":"splash_open","elapsed_ms":142}');
  });

  test('单行 GET 双引号 URL', () {
    final req = Curl.parse('curl "https://example.com/path?q=1" -H "Accept: application/json"');
    expect(req.method, HttpMethod.get);
    expect(req.requestUrl, 'https://example.com/path?q=1');
    expect(req.headers.get('Accept'), 'application/json');
  });

  test('带 data 自动推断 POST', () {
    final req = Curl.parse(r"""curl https://example.com -d 'a=1&b=2'""");
    expect(req.method, HttpMethod.post);
    expect(String.fromCharCodes(req.body ?? []), 'a=1&b=2');
  });

  test('连写与等号选项 -XPOST --header= -H', () {
    final req = Curl.parse("curl -XPOST https://example.com --header='X-A: 1' -H'X-B: 2'");
    expect(req.method, HttpMethod.post);
    expect(req.headers.get('X-A'), '1');
    expect(req.headers.get('X-B'), '2');
  });

  test('-u 生成 basic 认证, -b cookie, -e referer, -A ua', () {
    final req = Curl.parse("curl https://example.com -u user:pass -b 'a=1' -e https://ref.com -A MyUA");
    expect(req.headers.get('Authorization'), 'Basic dXNlcjpwYXNz');
    expect(req.headers.get('Cookie'), 'a=1');
    expect(req.headers.get('Referer'), 'https://ref.com');
    expect(req.headers.get('User-Agent'), 'MyUA');
  });

  test('--http2 协议版本', () {
    final req = Curl.parse('curl --http2 https://example.com');
    expect(req.protocolVersion, 'HTTP/2');
  });

  test('双引号内转义点号被保留', () {
    final req = Curl.parse(r'''curl https://example.com -d "{\"k\":\"v\"}"''');
    expect(String.fromCharCodes(req.body ?? []), '{"k":"v"}');
  });

  test('-G 数据拼到 query 且保持 GET、无 body', () {
    final req = Curl.parse(r"""curl -G https://example.com/search -d 'q=hi&page=2'""");
    expect(req.method, HttpMethod.get);
    expect(req.requestUrl, 'https://example.com/search?q=hi&page=2');
    expect(req.body, isNull);
  });

  test('-G 追加到已有 query', () {
    final req = Curl.parse(r"""curl -G 'https://example.com/s?a=1' -d 'b=2'""");
    expect(req.requestUrl, 'https://example.com/s?a=1&b=2');
  });

  test('多个 -d 用 & 连接', () {
    final req = Curl.parse(r"""curl https://example.com -d 'a=1' -d 'b=2'""");
    expect(req.method, HttpMethod.post);
    expect(String.fromCharCodes(req.body ?? []), 'a=1&b=2');
  });

  test('未实现的带值选项不会被当成 URL', () {
    final req = Curl.parse('curl https://example.com --max-time 30 -F file=@a.png -o out.txt');
    expect(req.requestUrl, 'https://example.com');
  });

  test('带值选项的连写/等号形式', () {
    final req = Curl.parse("curl https://example.com -m30 --resolve='x.com:443:1.2.3.4'");
    expect(req.requestUrl, 'https://example.com');
  });

  test('--json 作为 body 并设置 JSON 头', () {
    final req = Curl.parse(r"""curl https://example.com --json '{"a":1}'""");
    expect(req.method, HttpMethod.post);
    expect(String.fromCharCodes(req.body ?? []), '{"a":1}');
    expect(req.headers.get('Content-Type'), 'application/json');
  });
}
