import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/mcp/mcp_listen_options.dart';

void main() {
  group('MCP listen address normalization', () {
    test('keeps the two supported addresses', () {
      expect(McpListenOptions.normalizeAddress(McpListenOptions.loopbackAddress), McpListenOptions.loopbackAddress);
      expect(McpListenOptions.normalizeAddress(McpListenOptions.anyAddress), McpListenOptions.anyAddress);
    });

    test('falls back to LAN for legacy and invalid values', () {
      for (var value in [null, '', 'localhost', '192.168.1.2', 0, false]) {
        expect(McpListenOptions.normalizeAddress(value), McpListenOptions.anyAddress);
      }
    });
  });

  group('MCP listen options', () {
    test('mobile loopback still requires bearer authentication', () {
      var options = McpListenOptions.resolve(
        isMobile: true,
        configuredAddress: McpListenOptions.loopbackAddress,
      );

      expect(options.address.address, InternetAddress.loopbackIPv4.address);
      expect(options.requiresBearerToken, isTrue);
    });

    test('mobile LAN binds all interfaces and requires bearer authentication', () {
      var options = McpListenOptions.resolve(isMobile: true, configuredAddress: McpListenOptions.anyAddress);

      expect(options.address.address, InternetAddress.anyIPv4.address);
      expect(options.requiresBearerToken, isTrue);
    });

    test('invalid mobile configuration preserves LAN behavior', () {
      var options = McpListenOptions.resolve(isMobile: true, configuredAddress: 'invalid');

      expect(options.address.address, InternetAddress.anyIPv4.address);
      expect(options.requiresBearerToken, isTrue);
    });

    test('desktop always uses unauthenticated loopback', () {
      for (var address in [McpListenOptions.loopbackAddress, McpListenOptions.anyAddress, 'invalid']) {
        var options = McpListenOptions.resolve(isMobile: false, configuredAddress: address);

        expect(options.address.address, InternetAddress.loopbackIPv4.address);
        expect(options.requiresBearerToken, isFalse);
      }
    });
  });
}
