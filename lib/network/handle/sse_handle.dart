import 'dart:typed_data';

import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/parse/chunked_decoder.dart';
import 'package:proxypin/network/http/sse.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/util/logger.dart';

/// SSE (text/event-stream) handler: forwards raw bytes and emits parsed message frames.
///
/// For HTTP/1.1, SSE responses are almost always sent with
/// `Transfer-Encoding: chunked`. The bytes arriving on this handler are still
/// chunk-encoded, so we strip the framing with [ChunkedDecoder] before feeding
/// [SseDecoder] — otherwise chunk-size lines and inter-chunk `\r\n` would
/// desync the SSE line/event parser and drop events.
///
/// We still forward the original (chunk-encoded) bytes to the peer channel
/// verbatim so the client sees an unchanged framing.
class SseChannelHandler extends ChannelHandler<Uint8List> {
  final SseDecoder decoder = SseDecoder();
  final ChunkedDecoder? _chunkDecoder;

  final Channel proxyChannel;
  final HttpMessage message; // HttpResponse on server->client, HttpRequest on client->server

  SseChannelHandler(this.proxyChannel, this.message)
      : _chunkDecoder = message.headers.isChunked ? ChunkedDecoder() : null;

  @override
  Future<void> channelRead(ChannelContext channelContext, Channel channel, Uint8List msg) async {
    // Always forward the raw bytes first (keep original chunk framing intact).
    proxyChannel.writeBytes(msg);

    try {
      final Uint8List payload = _chunkDecoder != null ? _chunkDecoder!.feed(msg) : msg;
      if (payload.isEmpty) return;

      final frames = decoder.feed(payload);
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
