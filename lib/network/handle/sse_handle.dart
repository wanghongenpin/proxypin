import 'dart:typed_data';

import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/sse.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/util/logger.dart';

/// SSE (text/event-stream) handler: forwards raw bytes and emits parsed message frames.
class SseChannelHandler extends ChannelHandler<Uint8List> {
  final SseDecoder decoder = SseDecoder();

  final Channel proxyChannel;
  final HttpMessage message; // HttpResponse on server->client, HttpRequest on client->server

  SseChannelHandler(this.proxyChannel, this.message);

  @override
  Future<void> channelRead(ChannelContext channelContext, Channel channel, Uint8List msg) async {
    // Always forward the raw bytes first
    proxyChannel.writeBytes(msg);

    try {
      final frames = decoder.feed(msg);
      for (final WebSocketFrame frame in frames) {
        frame.isFromClient = message is HttpRequest;
        message.messages.add(frame);
        channelContext.listener?.onMessage(channel, message, frame);
        logger.d(
            "[${channelContext.clientChannel?.id}] sse channelRead ${frame.payloadLength} ${frame.payloadDataAsString}");
      }
    } catch (e, stackTrace) {
      log.e("sse decode error", error: e, stackTrace: stackTrace);
    }
  }
}

