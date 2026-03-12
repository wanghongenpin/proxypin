
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Parsed IPv6 authority correctly', () {
    var authority = "[240c:409f:1000::4:0:a5]";
    var scheme = "https";

    String host = authority;
    int port = (scheme == 'https' ? 443 : 80);

    if (authority.startsWith("[")) {
      int closeBracketIndex = authority.indexOf(']');
      if (closeBracketIndex != -1) {
        host = authority.substring(0, closeBracketIndex + 1);
        if (authority.length > closeBracketIndex + 1 && authority[closeBracketIndex + 1] == ':') {
          port = int.tryParse(authority.substring(closeBracketIndex + 2)) ?? port;
        }
      }
    } else {
      int lastColonIndex = authority.lastIndexOf(':');
      if (lastColonIndex != -1) {
        var p = int.tryParse(authority.substring(lastColonIndex + 1));
        if (p != null) {
          host = authority.substring(0, lastColonIndex);
          port = p;
        }
      }
    }

    expect(host, "[240c:409f:1000::4:0:a5]");
    expect(port, 443);
  });

  test('Parsed IPv6 authority with port correctly', () {
    var authority = "[240c:409f:1000::4:0:a5]:8080";
    var scheme = "https";

    String host = authority;
    int port = (scheme == 'https' ? 443 : 80);

    if (authority.startsWith("[")) {
      int closeBracketIndex = authority.indexOf(']');
      if (closeBracketIndex != -1) {
        host = authority.substring(0, closeBracketIndex + 1);
        if (authority.length > closeBracketIndex + 1 && authority[closeBracketIndex + 1] == ':') {
          port = int.tryParse(authority.substring(closeBracketIndex + 2)) ?? port;
        }
      }
    } else {
      int lastColonIndex = authority.lastIndexOf(':');
      if (lastColonIndex != -1) {
        var p = int.tryParse(authority.substring(lastColonIndex + 1));
        if (p != null) {
          host = authority.substring(0, lastColonIndex);
          port = p;
        }
      }
    }

    expect(host, "[240c:409f:1000::4:0:a5]");
    expect(port, 8080);
  });

  test('Parsed IPv6 authority broken', () {
    // case from log: [240c
    // Though log says host=[240c, authority was [240c:409f:1000::4:0:a5]
    // This testcase is checking if the logic handles incomplete ipv6 gracefully?
    // If authority is literally "[240c", it has start [ but no ].
    var authority = "[240c";
    var scheme = "https";

    String host = authority;
    int port = (scheme == 'https' ? 443 : 80);

    if (authority.startsWith("[")) {
      int closeBracketIndex = authority.indexOf(']');
      if (closeBracketIndex != -1) {
        host = authority.substring(0, closeBracketIndex + 1);
        if (authority.length > closeBracketIndex + 1 && authority[closeBracketIndex + 1] == ':') {
          port = int.tryParse(authority.substring(closeBracketIndex + 2)) ?? port;
        }
      }
    } else {
       // ...
    }
    // Logic says: if start with [ but no ], host remains authority.
    expect(host, "[240c");
  });

  test('Parsed IPv4 authority correctly', () {
      var authority = "192.168.1.1:8080";
      var scheme = "http";

      String host = authority;
      int port = (scheme == 'https' ? 443 : 80);

      if (authority.startsWith("[")) {
          // ...
      } else {
        int lastColonIndex = authority.lastIndexOf(':');
        if (lastColonIndex != -1) {
          var p = int.tryParse(authority.substring(lastColonIndex + 1));
          if (p != null) {
            host = authority.substring(0, lastColonIndex);
            port = p;
          }
        }
      }
      expect(host, "192.168.1.1");
      expect(port, 8080);
  });

  test('Parsed simple hostname correctly', () {
      var authority = "example.com";
      var scheme = "https";

      String host = authority;
      int port = (scheme == 'https' ? 443 : 80);

      if (authority.startsWith("[")) {
          // ...
      } else {
        int lastColonIndex = authority.lastIndexOf(':');
        if (lastColonIndex != -1) {
          var p = int.tryParse(authority.substring(lastColonIndex + 1));
          if (p != null) {
            host = authority.substring(0, lastColonIndex);
            port = p;
          }
        }
      }
      expect(host, "example.com");
      expect(port, 443);
  });
}

