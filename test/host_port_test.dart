import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/util/idna.dart';

void main() {
  group('punycodeEncode', () {
    test('should encode basic CJK and latin labels', () {
      expect(punycodeEncode('小度'), 'yet23d');
      expect(punycodeEncode('中国'), 'fiqs8s');
      expect(punycodeEncode('百度'), 'wxtr44c');
      expect(punycodeEncode('münchen'), 'mnchen-3ya');
      expect(punycodeEncode('mañana'), 'maana-pta');
    });

    test('should keep pure ascii unchanged', () {
      expect(punycodeEncode('abc'), 'abc');
    });
  });

  group('idnToAscii', () {
    test('should convert non-ascii host to punycode', () {
      expect(idnToAscii('小度.中国'), 'xn--yet23d.xn--fiqs8s');
      expect(idnToAscii('münchen.de'), 'xn--mnchen-3ya.de');
    });

    test('should keep ascii host unchanged', () {
      expect(idnToAscii('example.com'), 'example.com');
      expect(idnToAscii('xn--fiqs8s.com'), 'xn--fiqs8s.com');
    });

    test('should preserve trailing dot', () {
      expect(idnToAscii('小度.中国.'), 'xn--yet23d.xn--fiqs8s.');
    });
  });

  group('hostToAscii', () {
    test('should percent decode then convert to punycode', () {
      expect(hostToAscii('%E5%B0%8F%E5%BA%A6.%E4%B8%AD%E5%9B%BD'), 'xn--yet23d.xn--fiqs8s');
      expect(hostToAscii('xn--fiqs8s'), 'xn--fiqs8s');
    });

    test('should keep IPv6 link-local scope unchanged', () {
      expect(hostToAscii('fe80::1%eth0'), 'fe80::1%eth0');
    });
  });

  group('HostAndPort', () {
    test('should normalize percent encoded host', () {
      var hostAndPort = HostAndPort.of('http://%E5%B0%8F%E5%BA%A6.%E4%B8%AD%E5%9B%BD/');
      expect(hostAndPort.host, 'xn--yet23d.xn--fiqs8s');
      expect(hostAndPort.port, 80);
      expect(hostAndPort.isIPv6, isFalse);
    });

    test('should normalize percent encoded host with port', () {
      var hostAndPort = HostAndPort.of('https://%E5%B0%8F%E5%BA%A6.%E4%B8%AD%E5%9B%BD:8443/api');
      expect(hostAndPort.host, 'xn--yet23d.xn--fiqs8s');
      expect(hostAndPort.port, 8443);
      expect(hostAndPort.isSsl(), isTrue);
    });

    test('should keep ascii host unchanged', () {
      expect(HostAndPort.of('http://example.com/').host, 'example.com');
      expect(HostAndPort.of('http://127.0.0.1:8080/').host, '127.0.0.1');
      expect(HostAndPort.of('http://[::1]:8080/').host, '::1');
    });

    test('should normalize host assigned from Host header', () {
      var hostAndPort = HostAndPort.of('http://example.com/');
      hostAndPort.host = '%E5%B0%8F%E5%BA%A6.%E4%B8%AD%E5%9B%BD';
      expect(hostAndPort.host, 'xn--yet23d.xn--fiqs8s');
    });
  });
}
