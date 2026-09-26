import 'dart:convert';
import 'dart:typed_data';

import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';

/// A complete MQTT control packet. The wire bytes are retained unchanged.
class MqttPacket {
  static const typeNames = [
    'RESERVED',
    'CONNECT',
    'CONNACK',
    'PUBLISH',
    'PUBACK',
    'PUBREC',
    'PUBREL',
    'PUBCOMP',
    'SUBSCRIBE',
    'SUBACK',
    'UNSUBSCRIBE',
    'UNSUBACK',
    'PINGREQ',
    'PINGRESP',
    'DISCONNECT',
    'AUTH',
  ];

  final Uint8List bytes;
  final bool fromClient;
  final int headerLength;
  final int remainingLength;

  MqttPacket(
    this.bytes,
    this.fromClient,
    this.headerLength,
    this.remainingLength,
  );

  /// Decode one already framed packet, such as a packet loaded from history.
  factory MqttPacket.fromBytes(Uint8List bytes, bool fromClient) {
    if (bytes.length < 2) throw const FormatException('Short MQTT packet');
    var index = 1;
    var multiplier = 1;
    var remaining = 0;
    while (true) {
      if (index >= bytes.length || index > 4) {
        throw const FormatException('Invalid MQTT remaining length');
      }
      final digit = bytes[index++];
      remaining += (digit & 0x7f) * multiplier;
      if ((digit & 0x80) == 0) break;
      multiplier *= 128;
    }
    if (index + remaining != bytes.length) {
      throw const FormatException('Incomplete MQTT packet');
    }
    return MqttPacket(bytes, fromClient, index, remaining);
  }

  int get type => bytes[0] >> 4;
  int get flags => bytes[0] & 0x0f;
  String get typeName => typeNames[type];
  String get direction => fromClient ? 'client-to-server' : 'server-to-client';

  int? get packetId {
    final offset = headerLength + (type == 3 ? 2 + (topicBytes?.length ?? 0) : 0);
    if (type == 3 && ((flags >> 1) & 3) == 0) return null;
    if (type != 3 && !{4, 5, 6, 7, 8, 9, 10, 11}.contains(type)) return null;
    if (offset + 2 > bytes.length) return null;
    return (bytes[offset] << 8) | bytes[offset + 1];
  }

  Uint8List? get topicBytes {
    if (type != 3 || headerLength + 2 > bytes.length) return null;
    final length = (bytes[headerLength] << 8) | bytes[headerLength + 1];
    final start = headerLength + 2;
    if (start + length > bytes.length) return null;
    return Uint8List.sublistView(bytes, start, start + length);
  }

  String? get topic {
    final raw = topicBytes;
    if (raw == null) return null;
    return utf8.decode(raw, allowMalformed: true);
  }

  int? get connackCode => type == 2 && remainingLength >= 2 ? bytes[headerLength + 1] : null;

  WebSocketFrame toMessage() => WebSocketFrame(
        fin: true,
        opcode: 2,
        mask: false,
        payloadLength: bytes.length,
        maskingKey: 0,
        payloadData: bytes,
      )..isFromClient = fromClient;

  /// One display record represents the MQTT connection. Packets are stored in
  /// its messages list, using the same history container as WebSocket frames.
  static HttpRequest connectionRecord(HostAndPort remote) {
    final host = remote.host.contains(':') && !remote.host.startsWith('[') ? '[${remote.host}]' : remote.host;
    final request = HttpRequest(
      HttpMethod.mqtt,
      'mqtts://$host:${remote.port}',
      protocolVersion: 'MQTT',
    )..hostAndPort = remote;
    return request;
  }
}

/// Stream framing is independent of socket chunk boundaries. Oversized packets
/// are forwarded by the relay but skipped here to bound capture memory.
class MqttPacketFramer {
  static const maxCapturedPacketLength = 4 * 1024 * 1024;
  final bool fromClient;
  final List<int> _pending = [];
  int _skipRemaining = 0;

  MqttPacketFramer(this.fromClient);

  List<MqttPacket> add(List<int> chunk) {
    final packets = <MqttPacket>[];
    var offset = 0;
    while (offset < chunk.length) {
      if (_skipRemaining > 0) {
        final skipped = _skipRemaining < chunk.length - offset ? _skipRemaining : chunk.length - offset;
        _skipRemaining -= skipped;
        offset += skipped;
        continue;
      }

      _pending.add(chunk[offset++]);
      if (_pending.length < 2) continue;

      var multiplier = 1;
      var remaining = 0;
      var index = 1;
      while (index < _pending.length && index <= 4) {
        final digit = _pending[index];
        remaining += (digit & 0x7f) * multiplier;
        index++;
        if ((digit & 0x80) == 0) break;
        multiplier *= 128;
      }
      if ((_pending[index - 1] & 0x80) != 0) {
        if (index == 5) {
          throw const FormatException(
            'MQTT remaining length exceeds four bytes',
          );
        }
        continue;
      }

      final packetLength = index + remaining;
      if (packetLength > maxCapturedPacketLength) {
        _skipRemaining = packetLength - _pending.length;
        _pending.clear();
        continue;
      }
      if (_pending.length == packetLength) {
        packets.add(
          MqttPacket(
            Uint8List.fromList(_pending),
            fromClient,
            index,
            remaining,
          ),
        );
        _pending.clear();
      }
    }
    return packets;
  }
}
