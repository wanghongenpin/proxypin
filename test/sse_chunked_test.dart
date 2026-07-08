import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/http/parse/chunked_decoder.dart';
import 'package:proxypin/network/http/sse.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('ChunkedDecoder', () {
    test('decodes single-shot chunked payload', () {
      final d = ChunkedDecoder();
      final out = d.feed(_b('5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n'));
      expect(utf8.decode(out), 'hello world');
      expect(d.isDone, isTrue);
    });

    test('handles bytes split at every possible boundary', () {
      final full = '5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n';
      for (int split = 1; split < full.length; split++) {
        final d = ChunkedDecoder();
        final b1 = d.feed(_b(full.substring(0, split)));
        final b2 = d.feed(_b(full.substring(split)));
        final joined = <int>[...b1, ...b2];
        expect(utf8.decode(joined), 'hello world', reason: 'split=$split');
        expect(d.isDone, isTrue, reason: 'split=$split');
      }
    });

    test('tolerates chunk extensions', () {
      final d = ChunkedDecoder();
      final out = d.feed(_b('5;foo=bar\r\nhello\r\n0\r\n\r\n'));
      expect(utf8.decode(out), 'hello');
      expect(d.isDone, isTrue);
    });

    test('ignores trailer headers before terminator', () {
      final d = ChunkedDecoder();
      final out = d.feed(_b('3\r\nabc\r\n0\r\nX-Foo: bar\r\n\r\n'));
      expect(utf8.decode(out), 'abc');
      expect(d.isDone, isTrue);
    });
  });

  group('SseDecoder over chunked stream', () {
    test('parses events that straddle chunk boundaries', () {
      // Two SSE events split across three HTTP chunks such that a chunk
      // boundary falls in the middle of the first event's `data:` line.
      final raw = '9\r\ndata: hel\r\nA\r\nlo world\n\n\r\nD\r\ndata: bye\n\n\r\n0\r\n\r\n';

      final chunk = ChunkedDecoder();
      final sse = SseDecoder();
      final payload = chunk.feed(_b(raw));
      final frames = sse.feed(payload);

      expect(frames, hasLength(2));
      expect(frames[0].payloadDataAsString, 'hel'
          'lo world'); // string concat for readability
      expect(frames[1].payloadDataAsString, 'bye');
    });

    test('handles socket packets that split inside a chunk-size line', () {
      // Realistic packetization: OS may deliver bytes broken anywhere.
      final chunk = ChunkedDecoder();
      final sse = SseDecoder();

      // Whole stream: one event `data: hello\n\n` in a 14-byte chunk.
      final whole = '${14.toRadixString(16)}\r\ndata: hello\n\n\r\n0\r\n\r\n';
      final frames = <int>[];
      // Feed byte-by-byte
      for (int i = 0; i < whole.length; i++) {
        final payload = chunk.feed(_b(whole[i]));
        if (payload.isNotEmpty) {
          for (final f in sse.feed(payload)) {
            frames.addAll(f.payloadData);
          }
        }
      }
      expect(utf8.decode(frames), 'hello');
      expect(chunk.isDone, isTrue);
    });
  });
}
