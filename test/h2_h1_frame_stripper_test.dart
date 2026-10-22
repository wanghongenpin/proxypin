import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/channel/channel_context.dart';

List<int> _frame(int type, int flags, int stream, List<int> body) => [
      body.length >> 16,
      (body.length >> 8) & 255,
      body.length & 255,
      type,
      flags,
      (stream >> 24) & 127,
      (stream >> 16) & 255,
      (stream >> 8) & 255,
      stream & 255,
      ...body,
    ];

const _preface = 'PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n';

void main() {
  test('strip keeps only DATA payloads and drops preface and control frames', () {
    var stripper = H2ToH1FrameStripper();
    var input = [
      ...ascii.encode(_preface),
      ..._frame(4, 0, 0, [0, 4, 0, 1, 0, 0]), // SETTINGS
      ..._frame(7, 0, 0, [0, 0, 0, 1]), // WINDOW_UPDATE
      ..._frame(0, 0, 1, utf8.encode('hello ')), // DATA stream 1
      ..._frame(6, 0, 0, [1, 2, 3, 4, 5, 6, 7, 8]), // PING
      ..._frame(0, 1, 1, utf8.encode('world')), // DATA stream 1 END_STREAM
    ];

    var out = stripper.strip(input);
    expect(utf8.decode(out), 'hello world');
  });

  test('strip works when frames arrive split across calls', () {
    var stripper = H2ToH1FrameStripper();
    var dataFrame = _frame(0, 0, 3, utf8.encode('payload-bytes'));

    // 第一片：前言的一部分
    expect(stripper.strip(ascii.encode(_preface).sublist(0, 10)), isEmpty);
    // 第二片：前言剩余 + SETTINGS + DATA 的一部分
    var part2 = [
      ...ascii.encode(_preface).sublist(10),
      ..._frame(4, 0, 0, []),
      ...dataFrame.sublist(0, 12),
    ];
    expect(stripper.strip(part2), isEmpty);
    // 第三片：DATA 剩余
    var out = stripper.strip(dataFrame.sublist(12));
    expect(utf8.decode(out), 'payload-bytes');
  });

  test('strip without preface (forward starts mid-connection)', () {
    var stripper = H2ToH1FrameStripper();
    var out = stripper.strip([
      ..._frame(6, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0]), // PING
      ..._frame(0, 0, 5, utf8.encode('abc')),
    ]);
    expect(utf8.decode(out), 'abc');
  });

  test('empty DATA frame with END_STREAM produces no output', () {
    var stripper = H2ToH1FrameStripper();
    expect(stripper.strip(_frame(0, 1, 1, [])), isEmpty);
  });
}
