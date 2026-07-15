import 'dart:typed_data';

import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/util/logger.dart';

/// websocket处理器
class WebSocketChannelHandler extends ChannelHandler<Uint8List> {
  final WebSocketDecoder decoder = WebSocketDecoder();

  final Channel proxyChannel;
  final HttpMessage message;

  WebSocketChannelHandler(this.proxyChannel, this.message);

  @override
  Future<void> channelRead(ChannelContext channelContext, Channel channel, Uint8List msg) async {
    proxyChannel.writeBytes(msg);

    // A single TCP read may carry multiple WebSocket frames (Nagle, TLS record
    // batching, OS coalescing). Drain the decoder until no more full frames
    // remain in its buffer; subsequent iterations pass empty bytes so we only
    // consume what is already buffered.
    Uint8List chunk = msg;
    while (true) {
      WebSocketFrame? frame;
      try {
        frame = decoder.decode(chunk);
      } catch (e, stackTrace) {
        log.e("websocket decode error", error: e, stackTrace: stackTrace);
        break;
      }
      if (frame == null) {
        break;
      }
      frame.isFromClient = message is HttpRequest;

      message.messages.add(frame);
      channelContext.listener?.onMessage(channel, message, frame);
      logger.d(
          "[${channelContext.clientChannel?.id}] websocket channelRead ${frame.payloadLength} ${frame.fin} ${frame.payloadDataAsString}");

      chunk = _empty;
    }
  }

  static final Uint8List _empty = Uint8List(0);
}
