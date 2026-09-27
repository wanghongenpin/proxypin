import 'dart:typed_data';

import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/mqtt/mqtt_packet.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';

/// Relays decrypted MQTT bytes without changing packet contents or timing.
/// Parsing is only for capture, and a parse error cannot block traffic.
class MqttRelayHandler extends ChannelHandler<Uint8List> {
  final Channel peer;
  final MqttCaptureSession session;
  final MqttPacketFramer framer;
  bool captureEnabled = true;

  MqttRelayHandler(this.peer, this.session, {required bool fromClient}) : framer = MqttPacketFramer(fromClient);

  @override
  Future<void> channelRead(
    ChannelContext channelContext,
    Channel channel,
    Uint8List msg,
  ) async {
    await peer.writeBytes(msg);
    if (!captureEnabled) return;
    try {
      for (final packet in framer.add(msg)) {
        session.record(channelContext, channel, packet);
      }
    } catch (error, trace) {
      captureEnabled = false;
      logger.w(
        '[${channel.id}] MQTT capture disabled after parse error: $error',
        stackTrace: trace,
      );
    }
  }

  @override
  void channelInactive(ChannelContext channelContext, Channel channel) {
    peer.close();
  }
}

/// Shared by both relay directions, so one capture row owns the packet stream.
class MqttCaptureSession {
  final HttpRequest request;
  bool _announced = false;

  MqttCaptureSession(HostAndPort remote) : request = MqttPacket.connectionRecord(remote);

  void record(ChannelContext context, Channel channel, MqttPacket packet) {
    if (!_announced) {
      _announced = true;
      context.listener?.onRequest(context.clientChannel ?? channel, request);
    }
    final frame = packet.toMessage();
    request.messages.add(frame);
    context.listener?.onMessage(channel, request, frame);
  }
}
