import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/http/websocket.dart';

/// Builds an unmasked (server-to-client) text frame. FIN=1, opcode=0x01.
Uint8List _textFrame(String text) {
  final payload = utf8.encode(text);
  final builder = BytesBuilder();
  builder.addByte(0x80 | 0x01); // FIN + text
  if (payload.length < 126) {
    builder.addByte(payload.length);
  } else if (payload.length <= 0xFFFF) {
    builder.addByte(126);
    builder.addByte((payload.length >> 8) & 0xff);
    builder.addByte(payload.length & 0xff);
  } else {
    builder.addByte(127);
    final len = payload.length;
    for (var i = 7; i >= 0; i--) {
      builder.addByte((len >> (i * 8)) & 0xff);
    }
  }
  builder.add(payload);
  return builder.toBytes();
}

void main() {
  final empty = Uint8List(0);

  test('decode returns single frame when only one frame is in the buffer', () {
    final decoder = WebSocketDecoder();
    final frame = decoder.decode(_textFrame('hello'));
    expect(frame, isNotNull);
    expect(frame!.payloadDataAsString, 'hello');

    // Buffer should be empty; a follow-up call with no new data returns null.
    expect(decoder.decode(empty), isNull);
  });

  test('decode preserves remaining frames when multiple arrive in one read', () {
    final decoder = WebSocketDecoder();
    final combined = BytesBuilder()
      ..add(_textFrame('hello'))
      ..add(_textFrame('world'))
      ..add(_textFrame('!'));

    final first = decoder.decode(combined.toBytes());
    expect(first, isNotNull);
    expect(first!.payloadDataAsString, 'hello');

    // Subsequent frames must be drainable from the buffer without new bytes.
    final second = decoder.decode(empty);
    expect(second, isNotNull);
    expect(second!.payloadDataAsString, 'world');

    final third = decoder.decode(empty);
    expect(third, isNotNull);
    expect(third!.payloadDataAsString, '!');

    // Buffer is now empty.
    expect(decoder.decode(empty), isNull);
  });

  test('decode returns null while a frame is split across reads, then completes it', () {
    final decoder = WebSocketDecoder();
    final full = _textFrame('hello world');
    final firstHalf = Uint8List.sublistView(full, 0, 4);
    final secondHalf = Uint8List.sublistView(full, 4);

    expect(decoder.decode(firstHalf), isNull);
    final frame = decoder.decode(secondHalf);
    expect(frame, isNotNull);
    expect(frame!.payloadDataAsString, 'hello world');
    expect(decoder.decode(empty), isNull);
  });

  test('decode drains frames that straddle read boundaries', () {
    final decoder = WebSocketDecoder();
    final a = _textFrame('alpha');
    final b = _textFrame('beta');

    // First read: all of frame A + first byte of frame B.
    final part1 = BytesBuilder()
      ..add(a)
      ..addByte(b[0]);
    final firstDecoded = decoder.decode(part1.toBytes());
    expect(firstDecoded, isNotNull);
    expect(firstDecoded!.payloadDataAsString, 'alpha');

    // Draining with empty bytes should not produce another frame yet — frame B
    // is incomplete.
    expect(decoder.decode(empty), isNull);

    // Second read: rest of frame B.
    final part2 = Uint8List.sublistView(b, 1);
    final secondDecoded = decoder.decode(part2);
    expect(secondDecoded, isNotNull);
    expect(secondDecoded!.payloadDataAsString, 'beta');
    expect(decoder.decode(empty), isNull);
  });

  test('decode handles 16-bit extended payload length frames back-to-back', () {
    final decoder = WebSocketDecoder();
    final big = 'x' * 200; // triggers 16-bit length header
    final combined = BytesBuilder()
      ..add(_textFrame(big))
      ..add(_textFrame('tail'));

    final first = decoder.decode(combined.toBytes());
    expect(first, isNotNull);
    expect(first!.payloadLength, 200);
    expect(first.payloadDataAsString, big);

    final second = decoder.decode(empty);
    expect(second, isNotNull);
    expect(second!.payloadDataAsString, 'tail');
    expect(decoder.decode(empty), isNull);
  });
}
