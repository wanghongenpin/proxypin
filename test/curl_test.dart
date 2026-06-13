import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/utils/curl.dart';

void main() {
  group('Curl.parse', () {
    test('parses simple GET request', () {
      var request = Curl.parse("curl 'https://example.com/api'");
      expect(request.method, HttpMethod.get);
      expect(request.requestUrl, contains('example.com/api'));
    });

    test('parses POST with -X flag', () {
      var request = Curl.parse("curl -X POST 'https://example.com/api'");
      expect(request.method, HttpMethod.post);
    });

    test('parses --request flag', () {
      var request = Curl.parse("curl --request PUT 'https://example.com/api'");
      expect(request.method, HttpMethod.put);
    });

    test('parses headers with -H flag', () {
      var request = Curl.parse(
          "curl 'https://example.com' -H 'Content-Type: application/json' -H 'Authorization: Bearer token123'");
      expect(request.headers.get('Content-Type'), 'application/json');
      expect(request.headers.get('Authorization'), 'Bearer token123');
    });

    test('parses --header flag', () {
      var request = Curl.parse("curl 'https://example.com' --header 'Accept: text/html'");
      expect(request.headers.get('Accept'), 'text/html');
    });

    test('parses data with -d flag', () {
      var request = Curl.parse("curl -X POST 'https://example.com' -d '{\"key\":\"value\"}'");
      expect(request.method, HttpMethod.post);
      expect(request.bodyAsString, '{"key":"value"}');
    });

    test('parses --data-raw flag', () {
      var request = Curl.parse("curl -X POST 'https://example.com' --data-raw 'hello=world'");
      expect(request.bodyAsString, 'hello=world');
    });

    test('defaults to POST when data present and method not specified', () {
      var request = Curl.parse("curl 'https://example.com' -d 'body content'");
      expect(request.method, HttpMethod.post);
    });

    test('parses URL without quotes', () {
      var request = Curl.parse("curl https://example.com/path");
      expect(request.requestUrl, contains('example.com/path'));
    });
  });

  group('curlRequest', () {
    test('generates valid curl command', () {
      var request = HttpRequest(HttpMethod.get, 'https://example.com/api');
      request.hostAndPort = HostAndPort.of('https://example.com');
      request.headers.set('Accept', 'application/json');

      var curl = curlRequest(request);
      expect(curl, contains("curl -X GET"));
      expect(curl, contains("'https://example.com/api'"));
      expect(curl, contains("-H 'Accept: application/json'"));
    });

    test('includes body for POST request', () {
      var request = HttpRequest(HttpMethod.post, 'https://example.com/api');
      request.hostAndPort = HostAndPort.of('https://example.com');
      request.body = 'test body'.codeUnits;

      var curl = curlRequest(request);
      expect(curl, contains("--data 'test body'"));
    });
  });

  group('copyAsFetch', () {
    test('generates valid fetch code', () {
      var request = HttpRequest(HttpMethod.post, 'https://example.com/api');
      request.hostAndPort = HostAndPort.of('https://example.com');
      request.headers.set('Content-Type', 'application/json');
      request.body = '{"key":"value"}'.codeUnits;

      var fetch = copyAsFetch(request);
      expect(fetch, contains('fetch('));
      expect(fetch, contains('method:'));
      expect(fetch, contains('"POST"'));
      expect(fetch, contains('headers:'));
      expect(fetch, contains('"Content-Type"'));
      expect(fetch, contains('body:'));
    });

    test('excludes Content-Length header', () {
      var request = HttpRequest(HttpMethod.get, 'https://example.com');
      request.hostAndPort = HostAndPort.of('https://example.com');
      request.headers.set('Content-Length', '100');
      request.headers.set('Accept', '*/*');

      var fetch = copyAsFetch(request);
      expect(fetch, isNot(contains('"Content-Length"')));
      expect(fetch, isNot(contains('"content-length"')));
    });
  });
}
