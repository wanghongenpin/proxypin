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
  void channelRead(ChannelContext channelContext, Channel channel, Uint8List msg) {
    proxyChannel.write(msg);
    WebSocketFrame? frame;
    try {
      frame = decoder.decode(msg);
    } catch (e) {
      log.e("websocket decode error", error: e);
    }
    if (frame == null) {
      return;
    }
    frame.isFromClient = message is HttpRequest;

    message.messages.add(frame);
    channelContext.listener?.onMessage(channel, message, frame);
    logger.d("socket channelRead ${frame.payloadLength} ${frame.fin} ${frame.payloadDataAsString}");
  }
}
