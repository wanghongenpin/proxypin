import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/channel/host_port.dart';

void main() {
  group('HostAndPort.of', () {
    test('parses plain host:port', () {
      var hp = HostAndPort.of('example.com:8080');
      expect(hp.host, 'example.com');
      expect(hp.port, 8080);
      expect(hp.scheme, 'http://');
    });

    test('parses https URL', () {
      var hp = HostAndPort.of('https://example.com/path?q=1');
      expect(hp.host, 'example.com');
      expect(hp.port, 443);
      expect(hp.scheme, 'https://');
    });

    test('parses http URL with port', () {
      var hp = HostAndPort.of('http://example.com:9090/api');
      expect(hp.host, 'example.com');
      expect(hp.port, 9090);
      expect(hp.scheme, 'http://');
    });

    test('defaults to port 80 for http', () {
      var hp = HostAndPort.of('example.com');
      expect(hp.port, 80);
      expect(hp.scheme, 'http://');
    });

    test('defaults to port 443 when ssl=true', () {
      var hp = HostAndPort.of('example.com', ssl: true);
      expect(hp.port, 443);
      expect(hp.scheme, 'https://');
    });

    test('parses port 443 as https', () {
      var hp = HostAndPort.of('example.com:443');
      expect(hp.scheme, 'https://');
      expect(hp.port, 443);
    });

    test('parses ws:// scheme with port', () {
      var hp = HostAndPort.of('ws://echo.websocket.org:8080/path');
      expect(hp.scheme, 'ws://');
      expect(hp.host, 'echo.websocket.org');
      expect(hp.port, 8080);
    });

    test('parses wss:// scheme with port', () {
      var hp = HostAndPort.of('wss://echo.websocket.org:443/path');
      expect(hp.scheme, 'wss://');
      expect(hp.host, 'echo.websocket.org');
      expect(hp.port, 443);
    });
  });

  group('HostAndPort properties', () {
    test('domain includes scheme and host', () {
      var hp = HostAndPort('https://', 'example.com', 443);
      expect(hp.domain, 'https://example.com');
    });

    test('domain includes non-standard port', () {
      var hp = HostAndPort('http://', 'example.com', 8080);
      expect(hp.domain, 'http://example.com:8080');
    });

    test('isSsl returns true for https', () {
      var hp = HostAndPort('https://', 'example.com', 443);
      expect(hp.isSsl(), true);
    });

    test('isSsl returns false for http', () {
      var hp = HostAndPort('http://', 'example.com', 80);
      expect(hp.isSsl(), false);
    });

    test('equality works', () {
      var a = HostAndPort('https://', 'example.com', 443);
      var b = HostAndPort('https://', 'example.com', 443);
      expect(a, equals(b));
    });

    test('inequality on different port', () {
      var a = HostAndPort('https://', 'example.com', 443);
      var b = HostAndPort('https://', 'example.com', 8443);
      expect(a, isNot(equals(b)));
    });

    test('copyWith overrides fields', () {
      var hp = HostAndPort('http://', 'example.com', 80);
      var copy = hp.copyWith(scheme: 'https://', port: 443);
      expect(copy.scheme, 'https://');
      expect(copy.port, 443);
      expect(copy.host, 'example.com');
    });
  });

  group('HostAndPort.startsWithScheme', () {
    test('returns true for http://', () {
      expect(HostAndPort.startsWithScheme('http://example.com'), true);
    });

    test('returns true for https://', () {
      expect(HostAndPort.startsWithScheme('https://example.com'), true);
    });

    test('returns false for plain host', () {
      expect(HostAndPort.startsWithScheme('example.com:8080'), false);
    });
  });

  group('HostAndPort.host factory', () {
    test('creates with default http scheme for port 80', () {
      var hp = HostAndPort.host('example.com', 80);
      expect(hp.scheme, 'http://');
    });

    test('creates with https scheme for port 443', () {
      var hp = HostAndPort.host('example.com', 443);
      expect(hp.scheme, 'https://');
    });

    test('uses explicit scheme if provided', () {
      var hp = HostAndPort.host('example.com', 8080, scheme: 'wss://');
      expect(hp.scheme, 'wss://');
    });
  });
}
