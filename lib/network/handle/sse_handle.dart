import 'dart:typed_data';

import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/h2/frame.dart';
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
  static const int _maxEncodedBody = 8 * 1024 * 1024;

  final SseDecoder decoder = SseDecoder();
  final ChunkedDecoder? _chunkDecoder;

  final Channel proxyChannel;
  final HttpMessage message; // HttpResponse on server->client, HttpRequest on client->server

  /// h1 -> h2 协议转换：事件流剥掉 chunk 分帧后包成 h2 DATA 帧写回客户端，
  /// 而不是原文转发 h1 字节。转换前言已通告大窗口，无需逐帧流控。
  final bool wrapHttp2Data;
  bool _endStreamSent = false;

  /// Dechunked payload when Content-Encoding is set. Plain event streams are
  /// parsed as they arrive and are not copied.
  final List<int>? _encoded;
  bool _encodedClosed = false;

  SseChannelHandler(this.proxyChannel, this.message, {this.wrapHttp2Data = false})
      : _chunkDecoder = message.headers.isChunked ? ChunkedDecoder() : null,
        _encoded = sseBodyIsEncoded(message.headers.contentEncoding) ? <int>[] : null;

  @override
  Future<void> channelRead(ChannelContext channelContext, Channel channel, Uint8List msg) async {
    final Uint8List payload = _chunkDecoder != null ? _chunkDecoder!.feed(msg) : msg;

    if (wrapHttp2Data) {
      await _writeDataFrames(payload, endStream: _chunkDecoder?.isDone == true);
    } else {
      // Always forward the raw bytes first (keep original chunk framing intact).
      proxyChannel.writeBytes(msg);
    }

    try {
      if (_encoded != null) {
        _captureEncoded(payload);
        // A chunked event stream usually keeps the TCP connection. The body
        // ends at the 0-chunk, which is the earliest a one-shot inflate can run.
        // A non-chunked body is finished in channelInactive.
        if (_chunkDecoder?.isDone == true) {
          _decodeEncoded(channelContext, channel);
        }
        return;
      }
      if (payload.isEmpty) return;

      _publish(channelContext, channel, decoder.feed(payload));
    } catch (e, stackTrace) {
      log.e("sse decode error", error: e, stackTrace: stackTrace);
    }
  }

  @override
  void channelInactive(ChannelContext channelContext, Channel channel) {
    // h2 转换：上游关闭意味着事件流结束，补发 END_STREAM 让客户端正常收尾
    if (wrapHttp2Data && !_endStreamSent) {
      _writeDataFrames(Uint8List(0), endStream: true);
    }
    if (_encoded != null) {
      _decodeEncoded(channelContext, channel);
      return;
    }
    try {
      _publish(channelContext, channel, decoder.flush());
    } catch (e, stackTrace) {
      log.e("sse decode error", error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _writeDataFrames(Uint8List payload, {bool endStream = false}) async {
    const maxFrame = 16384;
    var offset = 0;
    while (payload.length - offset > maxFrame) {
      await _writeDataFrame(payload.sublist(offset, offset + maxFrame), false);
      offset += maxFrame;
    }
    var last = payload.sublist(offset);
    if (last.isNotEmpty || endStream) {
      await _writeDataFrame(last, endStream);
    }
  }

  Future<void> _writeDataFrame(List<int> data, bool endStream) {
    _endStreamSent = _endStreamSent || endStream;
    var header =
        FrameHeader(data.length, FrameType.data, endStream ? FrameHeader.flagsEndStream : 0, message.streamId!);
    return proxyChannel.writeBytes(header.encode()..addAll(data));
  }

  void _captureEncoded(Uint8List payload) {
    if (payload.isEmpty || _encoded!.length >= _maxEncodedBody) return;
    final int room = _maxEncodedBody - _encoded!.length;
    if (payload.length <= room) {
      _encoded!.addAll(payload);
      return;
    }
    _encoded!.addAll(payload.take(room));
    log.w("sse encoded body truncated at $_maxEncodedBody bytes");
  }

  void _decodeEncoded(ChannelContext channelContext, Channel channel) {
    if (_encodedClosed || _encoded == null) return;
    _encodedClosed = true;
    final Uint8List body = Uint8List.fromList(_encoded!);
    decodeEncodedEventStream(body, message.headers.contentEncoding).then((frames) {
      try {
        _publish(channelContext, channel, frames);
      } catch (e, stackTrace) {
        log.e("sse decode error", error: e, stackTrace: stackTrace);
      }
    }, onError: (Object e, StackTrace stackTrace) {
      log.e("sse decode error", error: e, stackTrace: stackTrace);
    });
  }

  void _publish(ChannelContext channelContext, Channel channel, List<WebSocketFrame> frames) {
    for (final WebSocketFrame frame in frames) {
      frame.isFromClient = message is HttpRequest;
      message.messages.add(frame);
      channelContext.listener?.onMessage(channel, message, frame);
      logger.d(
          "[${channelContext.clientChannel?.id}] sse channelRead ${frame.payloadLength} ${frame.payloadDataAsString}");
    }
  }
}
