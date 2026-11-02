import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/mqtt/mqtt_packet.dart';
import 'package:proxypin/network/mqtt/protocol_sniffer.dart';

void main() {
  test('sniffs MQTT CONNECT without a hostname rule', () {
    expect(ProtocolSniffer.recognize([0x10]), ProtocolChoice.needMore);
    expect(
      ProtocolSniffer.recognize([0x10, 0x0a, 0, 4, 0x4d]),
      ProtocolChoice.needMore,
    );
    expect(
      ProtocolSniffer.recognize([0x10, 0x0a, 0, 4, 0x4d, 0x51, 0x54, 0x54, 4, 2]),
      ProtocolChoice.mqtt,
    );
    expect(
      ProtocolSniffer.recognize([0x10, 0x0c, 0, 6, 0x4d, 0x51, 0x49, 0x73, 0x64, 0x70, 3, 2]),
      ProtocolChoice.mqtt,
    );
    expect(ProtocolSniffer.recognize([0x47, 0x45, 0x54]), ProtocolChoice.http);
    expect(
      ProtocolSniffer.recognize([0x10, 0x0a, 0, 4, 1, 2, 3, 4, 4, 2]),
      ProtocolChoice.http,
    );
  });

  test('frames packets across chunk boundaries and coalesced socket reads', () {
    final client = MqttPacketFramer(true);
    expect(client.add([0x10, 0x03, 1]), isEmpty);
    final packets = client.add([2, 3, 0xc0, 0x00]);
    expect(packets.map((packet) => packet.typeName), ['CONNECT', 'PINGREQ']);
    expect(packets.first.bytes, [0x10, 0x03, 1, 2, 3]);
    expect(packets.first.direction, 'client-to-server');
  });

  test('parses MQTT variable remaining length', () {
    final framer = MqttPacketFramer(false);
    final prefix = [0x30, 0x82, 0x01]; // 130 body bytes
    expect(framer.add(prefix), isEmpty);
    final packets = framer.add(List.filled(130, 0));
    expect(packets.single.remainingLength, 130);
    expect(packets.single.bytes.length, 133);
  });

  test('records publish topic, packet ID, and response code', () {
    final framer = MqttPacketFramer(false);
    final publish = framer.add([
      0x32,
      0x08,
      0,
      3,
      0x61,
      0x2f,
      0x62,
      0,
      7,
      0x78,
    ]).single;
    expect(publish.topic, 'a/b');
    expect(publish.packetId, 7);
    final record = MqttPacket.connectionRecord(
      HostAndPort.host('edge-mqtt.facebook.com', 443),
    );
    expect(
      record.requestUrl,
      'mqtts://edge-mqtt.facebook.com:443',
    );
    final message = publish.toMessage();
    record.messages.add(message);
    expect(message.isFromClient, false);
    expect(message.payloadData, publish.bytes);
    expect(MqttPacket.fromBytes(message.payloadData, message.isFromClient).topic, 'a/b');

    final connack = framer.add([0x20, 0x02, 0x00, 0x00]).single;
    expect(connack.connackCode, 0);
  });

  test('connection history retains packet order, bytes, and direction', () {
    final request = MqttPacket.connectionRecord(
      HostAndPort.host('mqtt.example', 443),
    );
    request.messages.addAll([
      MqttPacket.fromBytes(
        Uint8List.fromList([0xc0, 0x00]),
        true,
      ).toMessage(),
      MqttPacket.fromBytes(
        Uint8List.fromList([0xd0, 0x00]),
        false,
      ).toMessage(),
    ]);

    final restored = HttpRequest.fromJson(request.toJson());
    expect(restored.requestUrl, 'mqtts://mqtt.example:443');
    expect(restored.messages.length, 2);
    expect(restored.messages.map((message) => message.isFromClient), [true, false]);
    expect(restored.messages.map((message) => message.payloadData), [
      [0xc0, 0x00],
      [0xd0, 0x00],
    ]);
  });
}
