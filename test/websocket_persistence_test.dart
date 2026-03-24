import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';

void main() {
  test('HttpRequest persists websocket messages', () {
    final request = HttpRequest(HttpMethod.get, 'https://example.com/ws');

    final frame = WebSocketFrame(
      fin: true,
      opcode: 0x01,
      mask: false,
      payloadLength: 5,
      maskingKey: 0,
      payloadData: Uint8List.fromList('hello'.codeUnits),
      time: DateTime.fromMillisecondsSinceEpoch(1710000000000),
    )
      ..isFromClient = true;

    request.messages.add(frame);

    final restored = HttpRequest.fromJson(request.toJson());
    expect(restored.messages.length, 1);
    expect(restored.messages.first.payloadDataAsString, 'hello');
    expect(restored.messages.first.isFromClient, isTrue);
    expect(restored.messages.first.time.millisecondsSinceEpoch, 1710000000000);
  });

  test('HttpResponse persists websocket messages', () {
    final response = HttpResponse(HttpStatus.ok);

    final frame = WebSocketFrame(
      fin: true,
      opcode: 0x02,
      mask: false,
      payloadLength: 3,
      maskingKey: 0,
      payloadData: Uint8List.fromList([1, 2, 3]),
      time: DateTime.fromMillisecondsSinceEpoch(1710000001000),
    )
      ..isFromClient = false;

    response.messages.add(frame);

    final restored = HttpResponse.fromJson(response.toJson());
    expect(restored.messages.length, 1);
    expect(restored.messages.first.isBinary, isTrue);
    expect(restored.messages.first.payloadData, [1, 2, 3]);
    expect(restored.messages.first.time.millisecondsSinceEpoch, 1710000001000);
  });
}
