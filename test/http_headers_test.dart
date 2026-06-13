import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/http/http_headers.dart';

void main() {
  group('HttpHeaders set/get', () {
    test('set stores a single value', () {
      var h = HttpHeaders();
      h.set('Content-Type', 'application/json');
      expect(h.get('Content-Type'), 'application/json');
    });

    test('set overwrites previous value', () {
      var h = HttpHeaders();
      h.set('X-Foo', 'bar');
      h.set('X-Foo', 'baz');
      expect(h.get('X-Foo'), 'baz');
      expect(h.getList('X-Foo')?.length, 1);
    });

    test('get is case-insensitive', () {
      var h = HttpHeaders();
      h.set('Content-Type', 'text/html');
      expect(h.get('content-type'), 'text/html');
      expect(h.get('CONTENT-TYPE'), 'text/html');
    });
  });

  group('HttpHeaders add', () {
    test('add appends to existing values', () {
      var h = HttpHeaders();
      h.add('Set-Cookie', 'a=1');
      h.add('Set-Cookie', 'b=2');
      expect(h.getList('Set-Cookie')?.length, 2);
    });

    test('addValues appends multiple at once', () {
      var h = HttpHeaders();
      h.addValues('Accept', ['text/html', 'application/json']);
      expect(h.getList('Accept')?.length, 2);
    });
  });

  group('HttpHeaders remove', () {
    test('remove deletes header', () {
      var h = HttpHeaders();
      h.set('X-Remove', 'value');
      expect(h.remove('X-Remove'), true);
      expect(h.get('X-Remove'), null);
    });

    test('remove returns false for non-existent', () {
      var h = HttpHeaders();
      expect(h.remove('Non-Existent'), false);
    });
  });

  group('HttpHeaders computed properties', () {
    test('contentLength parses integer', () {
      var h = HttpHeaders();
      h.set('Content-Length', '1234');
      expect(h.contentLength, 1234);
    });

    test('contentLength defaults to 0', () {
      var h = HttpHeaders();
      expect(h.contentLength, 0);
    });

    test('isGzip returns true for gzip encoding', () {
      var h = HttpHeaders();
      h.set('Content-Encoding', 'gzip');
      expect(h.isGzip, true);
    });

    test('isChunked returns true for chunked transfer', () {
      var h = HttpHeaders();
      h.set('Transfer-Encoding', 'chunked');
      expect(h.isChunked, true);
    });

    test('contentType getter/setter', () {
      var h = HttpHeaders();
      h.contentType = 'text/plain';
      expect(h.contentType, 'text/plain');
    });

    test('host getter/setter', () {
      var h = HttpHeaders();
      h.host = 'example.com';
      expect(h.host, 'example.com');
    });

    test('cookies returns cookie list', () {
      var h = HttpHeaders();
      h.add('Cookie', 'session=abc');
      h.add('Cookie', 'theme=dark');
      expect(h.cookies.length, 2);
    });
  });

  group('HttpHeaders serialization', () {
    test('toJson produces correct map', () {
      var h = HttpHeaders();
      h.add('X-A', 'val1');
      h.add('X-A', 'val2');
      var json = h.toJson();
      expect(json['X-A'], ['val1', 'val2']);
    });

    test('fromJson round-trips', () {
      var original = HttpHeaders();
      original.add('Accept', 'text/html');
      original.add('Accept', 'application/json');
      original.set('Host', 'example.com');

      var json = original.toJson();
      var restored = HttpHeaders.fromJson(json);
      expect(restored.get('Accept'), 'text/html');
      expect(restored.getList('Accept')?.length, 2);
      expect(restored.get('Host'), 'example.com');
    });

    test('toMap joins multiple values with semicolon', () {
      var h = HttpHeaders();
      h.add('X-Multi', 'a');
      h.add('X-Multi', 'b');
      var map = h.toMap();
      expect(map['X-Multi'], 'a;b');
    });

    test('headerLines formats correctly', () {
      var h = HttpHeaders();
      h.set('Host', 'example.com');
      h.set('Accept', '*/*');
      var lines = h.headerLines();
      expect(lines, contains('Host: example.com'));
      expect(lines, contains('Accept: */*'));
    });
  });

  group('HttpHeaders case handling', () {
    test('preserves original header name casing', () {
      var h = HttpHeaders();
      h.set('Content-Type', 'text/html');
      expect(h.getOriginalName('content-type'), 'Content-Type');
    });

    test('add with different casing uses latest name', () {
      var h = HttpHeaders();
      h.add('x-custom', 'value1');
      h.add('X-Custom', 'value2');
      expect(h.getList('x-custom')?.length, 2);
    });
  });

  group('HttpHeaders clear', () {
    test('clear removes all headers', () {
      var h = HttpHeaders();
      h.set('A', '1');
      h.set('B', '2');
      h.clear();
      expect(h.get('A'), null);
      expect(h.get('B'), null);
    });
  });

  group('HttpHeaders addAll', () {
    test('addAll merges headers from another instance', () {
      var h1 = HttpHeaders();
      h1.set('X-Foo', 'bar');

      var h2 = HttpHeaders();
      h2.set('X-Baz', 'qux');

      h1.addAll(h2);
      expect(h1.get('X-Baz'), 'qux');
      expect(h1.get('X-Foo'), 'bar');
    });

    test('addAll with null is safe', () {
      var h = HttpHeaders();
      h.addAll(null);
      expect(h.contentLength, 0);
    });
  });
}
