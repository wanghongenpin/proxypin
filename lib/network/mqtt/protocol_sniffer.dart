import 'dart:typed_data';

import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/channel_dispatcher.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/handle/relay_handle.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/mqtt/mqtt_relay_handler.dart';

enum ProtocolChoice { needMore, http, mqtt }

/// Inspects decrypted client bytes before choosing an application decoder.
/// MQTT is recognized by its CONNECT fixed header and protocol name, so no
/// service hostname or port list is needed.
class ProtocolSniffer extends ChannelHandler<Uint8List> {
  final HostAndPort remote;
  final String serverName;
  final Decoder httpDecoder;
  final Encoder httpEncoder;
  final ChannelHandler httpHandler;
  final List<int> _pending = [];
  bool _switching = false;

  ProtocolSniffer(
    this.remote,
    this.serverName,
    this.httpDecoder,
    this.httpEncoder,
    this.httpHandler,
  );

  static ProtocolChoice recognize(List<int> bytes) {
    if (bytes.isEmpty) return ProtocolChoice.needMore;
    if (bytes[0] != 0x10) return ProtocolChoice.http;
    if (bytes.length < 2) return ProtocolChoice.needMore;

    var index = 1;
    var multiplier = 1;
    var remaining = 0;
    while (true) {
      if (index >= bytes.length) return ProtocolChoice.needMore;
      if (index > 4) return ProtocolChoice.http;
      final digit = bytes[index++];
      remaining += (digit & 0x7f) * multiplier;
      if ((digit & 0x80) == 0) break;
      multiplier *= 128;
    }

    if (bytes.length < index + 2) return ProtocolChoice.needMore;
    final nameLength = (bytes[index] << 8) | bytes[index + 1];
    if (nameLength != 4 && nameLength != 6) return ProtocolChoice.http;
    if (remaining < 2 + nameLength + 4) return ProtocolChoice.http;
    if (bytes.length < index + 2 + nameLength + 2) return ProtocolChoice.needMore;
    final name = String.fromCharCodes(
      bytes.sublist(index + 2, index + 2 + nameLength),
    );
    final level = bytes[index + 2 + nameLength];
    final connectFlags = bytes[index + 3 + nameLength];
    final validVersion = (name == 'MQTT' && (level == 4 || level == 5)) || (name == 'MQIsdp' && level == 3);
    return validVersion && (connectFlags & 1) == 0 ? ProtocolChoice.mqtt : ProtocolChoice.http;
  }

  @override
  Future<void> channelRead(
    ChannelContext channelContext,
    Channel channel,
    Uint8List msg,
  ) async {
    _pending.addAll(msg);
    if (_switching) return;

    var choice = recognize(_pending);
    if (choice == ProtocolChoice.needMore && _pending.length <= 64 * 1024) {
      return;
    }
    if (choice == ProtocolChoice.needMore) choice = ProtocolChoice.http;
    _switching = true;

    if (choice == ProtocolChoice.http) {
      channel.dispatcher.handle(httpDecoder, httpEncoder, httpHandler);
    } else {
      var upstream = channelContext.serverChannel;
      var needsListen = upstream == null;
      upstream ??= await channelContext.connectServerChannel(
        remote,
        RelayHandler(channel),
      );
      if (!upstream.isSsl) {
        await upstream.startSecureSocket(
          channelContext,
          host: serverName,
          supportedProtocols: channel.selectedProtocol == null ? null : [channel.selectedProtocol!],
        );
        needsListen = true;
      }
      final codec = RawCodec();
      final captureTarget = remote.copyWith(host: serverName);
      final session = MqttCaptureSession(captureTarget);
      channel.dispatcher.channelHandle(
        codec,
        MqttRelayHandler(upstream, session, fromClient: true),
      );
      upstream.dispatcher.channelHandle(
        codec,
        MqttRelayHandler(channel, session, fromClient: false),
      );
      if (needsListen) upstream.listen(channelContext);
    }

    final firstBytes = Uint8List.fromList(_pending);
    _pending.clear();
    await channel.dispatcher.channelRead(channelContext, channel, firstBytes);
  }
}
