import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/http/parse/body_reader.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

HttpResponse _chunkedResponse() {
  final resp = HttpResponse(HttpStatus(200, 'OK'));
  resp.headers.set(HttpHeaders.TRANSFER_ENCODING, 'chunked');
  return resp;
}

HttpResponse _fixedResponse(int contentLength) {
  final resp = HttpResponse(HttpStatus(200, 'OK'));
  resp.headers.contentLength = contentLength;
  return resp;
}

void main() {
  group('BodyReader chunked', () {
    test('single-shot chunked body', () {
      final r = BodyReader(_chunkedResponse());
      final result = r.readBody(_b('5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n'));
      expect(result.isDone, isTrue);
      expect(utf8.decode(result.body!), 'hello world');
    });

    test('handles bytes split at every possible boundary', () {
      const full = '5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n';
      for (int split = 1; split < full.length; split++) {
        final r = BodyReader(_chunkedResponse());
        final r1 = r.readBody(_b(full.substring(0, split)));
        final r2 = r.readBody(_b(full.substring(split)));
        // Whichever call sees the terminator returns isDone=true with the full body.
        final Uint8List body = r2.isDone ? r2.body! : r1.body!;
        expect(r2.isDone || r1.isDone, isTrue, reason: 'split=$split');
        expect(utf8.decode(body), 'hello world', reason: 'split=$split');
      }
    });

    test('reproduces original bug: 0-terminator arrives alone', () {
      // The crash scenario from the issue: last data chunk arrives without
      // the terminator, and the next packet is just "0\r\n\r\n".
      final r = BodyReader(_chunkedResponse());
      final r1 = r.readBody(_b('b\r\nhello world\r\n'));
      expect(r1.isDone, isFalse);
      final r2 = r.readBody(_b('0\r\n\r\n'));
      expect(r2.isDone, isTrue);
      expect(utf8.decode(r2.body!), 'hello world');
    });

    test('byte-by-byte feeding', () {
      const full = '3\r\nabc\r\n5\r\n12345\r\n0\r\n\r\n';
      final r = BodyReader(_chunkedResponse());
      Result? last;
      for (int i = 0; i < full.length; i++) {
        last = r.readBody(_b(full[i]));
        if (last.isDone) break;
      }
      expect(last?.isDone, isTrue);
      expect(utf8.decode(last!.body!), 'abc12345');
    });

    test('tolerates chunk extensions', () {
      final r = BodyReader(_chunkedResponse());
      final result = r.readBody(_b('5;foo=bar\r\nhello\r\n0\r\n\r\n'));
      expect(result.isDone, isTrue);
      expect(utf8.decode(result.body!), 'hello');
    });

    test('ignores trailer headers before terminator', () {
      final r = BodyReader(_chunkedResponse());
      final result = r.readBody(_b('3\r\nabc\r\n0\r\nX-Foo: bar\r\n\r\n'));
      expect(result.isDone, isTrue);
      expect(utf8.decode(result.body!), 'abc');
    });

    test('invalid chunk size throws ParserException', () {
      final r = BodyReader(_chunkedResponse());
      expect(
        () => r.readBody(_b('zz\r\nhello\r\n')),
        throwsA(isA<ParserException>()),
      );
    });
  });

  group('BodyReader fixed length', () {
    test('reads full body in one call', () {
      final r = BodyReader(_fixedResponse(5));
      final result = r.readBody(_b('hello'));
      expect(result.isDone, isTrue);
      expect(utf8.decode(result.body!), 'hello');
    });

    test('accumulates across calls', () {
      final r = BodyReader(_fixedResponse(11));
      final r1 = r.readBody(_b('hello'));
      expect(r1.isDone, isFalse);
      final r2 = r.readBody(_b(' world'));
      expect(r2.isDone, isTrue);
      expect(utf8.decode(r2.body!), 'hello world');
    });
  });
}
