import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/utils/python.dart';

void main() {
  group('copyAsPythonRequests', () {
    test('generates import statement', () {
      var request = HttpRequest(HttpMethod.get, 'https://example.com/api');
      request.hostAndPort = HostAndPort.of('https://example.com');
      request.headers.set('Accept', 'application/json');

      var result = copyAsPythonRequests(request);
      expect(result, contains('import requests'));
    });

    test('sets correct method', () {
      var request = HttpRequest(HttpMethod.post, 'https://example.com/api');
      request.hostAndPort = HostAndPort.of('https://example.com');
      request.headers.set('Content-Type', 'application/json');

      var result = copyAsPythonRequests(request);
      expect(result, contains('requests.post('));
    });

    test('includes URL', () {
      var request = HttpRequest(HttpMethod.get, 'https://example.com/path');
      request.hostAndPort = HostAndPort.of('https://example.com');
      request.headers.set('Accept', '*/*');

      var result = copyAsPythonRequests(request);
      expect(result, contains('url = "https://example.com/path"'));
    });

    test('extracts cookies into separate dict', () {
      var request = HttpRequest(HttpMethod.get, 'https://example.com');
      request.hostAndPort = HostAndPort.of('https://example.com');
      request.headers.set('Cookie', 'session=abc123; theme=dark');
      request.headers.set('Accept', '*/*');

      var result = copyAsPythonRequests(request);
      expect(result, contains('cookies = {'));
      expect(result, contains(', cookies=cookies'));
    });

    test('includes body as data', () {
      var request = HttpRequest(HttpMethod.post, 'https://example.com');
      request.hostAndPort = HostAndPort.of('https://example.com');
      request.headers.set('Content-Type', 'text/plain');
      request.body = 'hello world'.codeUnits;

      var result = copyAsPythonRequests(request);
      expect(result, contains('data = """hello world"""'));
      expect(result, contains(', data=data'));
    });

    test('omits data when body is empty', () {
      var request = HttpRequest(HttpMethod.get, 'https://example.com');
      request.hostAndPort = HostAndPort.of('https://example.com');
      request.headers.set('Accept', '*/*');

      var result = copyAsPythonRequests(request);
      expect(result, isNot(contains('data =')));
    });

    test('prints response', () {
      var request = HttpRequest(HttpMethod.get, 'https://example.com');
      request.hostAndPort = HostAndPort.of('https://example.com');
      request.headers.set('Accept', '*/*');

      var result = copyAsPythonRequests(request);
      expect(result, contains('print(res.text)'));
    });
  });

  group('escapeCharacter', () {
    test('escapes backslash', () {
      expect(escapeCharacter('a\\b'), 'a\\\\b');
    });

    test('escapes double quotes', () {
      expect(escapeCharacter('say "hi"'), 'say \\"hi\\"');
    });

    test('escapes single quotes', () {
      expect(escapeCharacter("it's"), "it\\'s");
    });

    test('handles mixed special chars', () {
      expect(escapeCharacter('a\\b"c\'d'), 'a\\\\b\\"c\\\'d');
    });
  });
}
