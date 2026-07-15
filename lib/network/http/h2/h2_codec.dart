/*
 * Copyright 2023 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:math';
import 'dart:typed_data';
import 'dart:convert' show latin1;

import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/h2/setting.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/util/byte_buf.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/http/sse.dart';
import 'package:proxypin/network/http/websocket.dart';

import '../../util/byte_utils.dart';
import 'frame.dart';
import 'hpack/hpack.dart';

/// http编解码
abstract class Http2Codec<T extends HttpMessage> implements Codec<T, T> {
  static const maxFrameSize = 16384;
  static const int largeBodyThreshold = 4 * 1024 * 1024; // 4MB

  static final List<int> connectionPrefacePRI = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".codeUnits;

  HPackDecoder decoder = HPackDecoder();

  final HPackEncoder _hpackEncoder = HPackEncoder();

  T createMessage(ChannelContext channelContext, FrameHeader frameHeader, Map<String, List<String>> headers);

  T? getMessage(ChannelContext channelContext, FrameHeader frameHeader);

  // Per-stream SSE decoder instances keyed by HTTP/2 stream id
  final Map<int, SseDecoder> sseDecoders = {};

  // 大 body stream IDs - 这些 stream 的 DATA 帧直接转发不累积
  final Set<int> _largeBodyStreamIds = {};

  // HEADERS 帧记录了 END_STREAM=1 但还没 END_HEADERS 的 stream。
  // CONTINUATION 完成时用来判定"其实没 body"，避免激活 streaming 让远端空等。
  final Set<int> _headerEndStreamPending = {};

  @override
  DecoderResult<T> decode(ChannelContext channelContext, ByteBuf byteBuf, {bool resolveBody = true}) {
    DecoderResult<T> result = DecoderResult<T>();

    //Connection Preface PRI * HTTP/2.0
    if (byteBuf.get(byteBuf.readerIndex) == 0x50 &&
        byteBuf.get(byteBuf.readerIndex + 1) == 0x52 &&
        byteBuf.get(byteBuf.readerIndex + 2) == 0x49 &&
        isConnectionPrefacePRI(byteBuf)) {
      result.forward = byteBuf.readBytes(connectionPrefacePRI.length);
      // logger.d(
      //     "Connection Preface ${connectionPrefacePRI.length} ${String.fromCharCodes(result.forward!)} ${byteBuf.readableBytes()}");
      if (byteBuf.readableBytes() <= 0) {
        return result;
      }
    }

    List<int>? forward = result.forward == null ? null : List.of(result.forward!);

    while (byteBuf.isReadable()) {
      FrameHeader? frameHeader = FrameReader.readFrameHeader(byteBuf);
      // logger.d(
      //     "frameHeader streamId: ${frameHeader?.streamIdentifier} frame ${frameHeader?.type.name} ${frameHeader?.length} ${byteBuf.readableBytes()}");
      if (frameHeader == null) {
        result.forward = forward;
        result.isDone = false;
        return result;
      }

      List<int>? framePayload = FrameReader._readFramePayload(byteBuf, frameHeader.length);
      if (framePayload == null) {
        result.isDone = false;
        byteBuf.readerIndex -= FrameReader.headerLength;

        result.forward = forward;
        return result;
      }

      var parseResult = parseHttp2Packet(channelContext, frameHeader, framePayload);
      if (parseResult.forward != null) {
        forward ??= [];
        forward.addAll(parseResult.forward!);
      }

      if (parseResult.isDone) {
        parseResult.forward = forward;
        return parseResult;
      }
    }

    result.forward = forward;
    result.isDone = false;
    return result;
  }

  DecoderResult<T> parseHttp2Packet(ChannelContext channelContext, FrameHeader frameHeader, List<int> framePayload) {
    var result = DecoderResult<T>(isDone: false);

    // logger.d(
    //     "[${channelContext.clientChannel?.id}] ${this is Http2RequestDecoder ? 'request' : 'response'} streamId:${frameHeader.streamIdentifier} ${frameHeader.type} endHeaders: ${frameHeader.hasEndHeadersFlag} "
    //     "endStream: ${frameHeader.hasEndStreamFlag} ${frameHeader.length}");
    //根据帧类型进行处理
    switch (frameHeader.type) {
      case FrameType.headers:
        //处理HEADERS帧
        var headersFrame = _handleHeadersFrame(channelContext, frameHeader, ByteBuf(framePayload));
        result.isDone = frameHeader.hasEndStreamFlag && frameHeader.hasEndHeadersFlag;
        if (headersFrame.streamDependency != null) {
          headersFrame.headerBlockFragment = [];
          channelContext.put(frameHeader.streamIdentifier, headersFrame);
        }

        // 记录 END_STREAM，供后续 CONTINUATION 帧判 streaming 时参考
        if (frameHeader.hasEndStreamFlag && !frameHeader.hasEndHeadersFlag) {
          _headerEndStreamPending.add(frameHeader.streamIdentifier);
        }

        //handle special case for SSE
        var possibleMessage = getMessage(channelContext, frameHeader);
        if (possibleMessage is HttpResponse &&
            possibleMessage.headers.contentType.toLowerCase().startsWith('text/event-stream')) {
          result.forward = List.from(frameHeader.encode())..addAll(framePayload);
          result.data = possibleMessage;
          var currentRequest = channelContext.getStreamRequest(frameHeader.streamIdentifier);
          currentRequest?.response = possibleMessage;
          possibleMessage.request ??= channelContext.currentRequest;
          channelContext.listener?.onResponse(channelContext, possibleMessage);
          return result;
        }

        // 大 body 请求：HEADERS 帧一到就 emit request（body=null），让 handler
        // 立即建立远端连接、发送 headers；后续 DATA 帧由 forward 透传。
        // 需要 END_HEADERS 完成（避免 CONTINUATION 帧还没来），且 stream 不会
        // 立即结束（END_STREAM=0，说明还有 body）。
        if (frameHeader.hasEndHeadersFlag &&
            !frameHeader.hasEndStreamFlag &&
            _tryStartStreamingUpload(channelContext, frameHeader, possibleMessage, result)) {
          return result;
        }

        break;
      case FrameType.continuation:
        //处理CONTINUATION帧
        var message = getMessage(channelContext, frameHeader);
        if (message == null) {
          logger.e("CONTINUATION frame but no message found");
          result.forward = List.from(frameHeader.encode())..addAll(framePayload);
          return result;
        }

        Map<String, List<String>> headers = _parseHeaders(channelContext, framePayload);
        headers.forEach((key, values) => message.headers.addValues(key, values));
        message.packageSize = (message.packageSize ?? 0) + frameHeader.length;
        if (frameHeader.hasEndHeadersFlag &&
            channelContext.getStreamRequest(frameHeader.streamIdentifier)?.method == HttpMethod.head) {
          result.isDone = true;
        }

        // content-length 有可能落在 CONTINUATION 帧里，等 END_HEADERS 后再判一次。
        // 注意：CONTINUATION 帧 flags 里的 END_STREAM 不合法，必须查原始 HEADERS 帧的状态。
        if (frameHeader.hasEndHeadersFlag) {
          bool originalEndStream = _headerEndStreamPending.remove(frameHeader.streamIdentifier);
          if (originalEndStream) {
            // 原始 HEADERS 带 END_STREAM：headers 收全即请求完成，无 body
            result.isDone = true;
          } else if (_tryStartStreamingUpload(channelContext, frameHeader, message, result)) {
            return result;
          }
        }

        break;
      case FrameType.data:
        //处理DATA帧
        var message = getMessage(channelContext, frameHeader)!;
        bool isSseResponse =
            message is HttpResponse && message.headers.contentType.toLowerCase().startsWith('text/event-stream');
        if (isSseResponse) {
          _handleSseDataFrame(channelContext, frameHeader, message, ByteBuf(framePayload));
          result.forward = List.from(frameHeader.encode())..addAll(framePayload);
          return result;
        }

        // 大 body stream 直接转发 DATA 帧，不累积 body
        if (_largeBodyStreamIds.contains(frameHeader.streamIdentifier)) {
          result.forward = List.from(frameHeader.encode())..addAll(framePayload);
          if (frameHeader.hasEndStreamFlag) {
            _largeBodyStreamIds.remove(frameHeader.streamIdentifier);
          }
          return result;
        }

        _handleDataFrame(channelContext, frameHeader, message, ByteBuf(framePayload));
        result.isDone = frameHeader.hasEndStreamFlag;
        if (frameHeader.hasEndStreamFlag) {
          _largeBodyStreamIds.remove(frameHeader.streamIdentifier);
        }
        break;
      case FrameType.settings:
        SettingHandler.handleSettingsFrame(channelContext, frameHeader, ByteBuf(framePayload));
        result.forward = List.from(frameHeader.encode())..addAll(framePayload);
        return result;
      case FrameType.rstStream:
        // stream 中断：清理 streaming upload 标记，避免泄漏
        _headerEndStreamPending.remove(frameHeader.streamIdentifier);
        if (_largeBodyStreamIds.remove(frameHeader.streamIdentifier)) {
          logger.w(
              "[${channelContext.clientChannel?.id}] h2 streaming stream:${frameHeader.streamIdentifier} reset");
        }
        result.forward = List.from(frameHeader.encode())..addAll(framePayload);
        return result;
      case FrameType.goaway:
        var lastStreamId = readInt32(framePayload, 0);
        var errorCode = readInt32(framePayload, 4);
        var debugData = viewOrSublist(framePayload, 8, frameHeader.length - 8);
        logger.i(
            "[${channelContext.clientChannel?.id}] ${this is Http2RequestDecoder ? 'request' : 'response'} h2 goaway streamId: ${frameHeader.streamIdentifier} lastStreamId: $lastStreamId errorCode: $errorCode debugData: ${String.fromCharCodes(debugData)}");
        result.forward = List.from(frameHeader.encode())..addAll(framePayload);
        return result;
      default:
        //其他帧类型 原文转发
        result.forward = List.from(frameHeader.encode())..addAll(framePayload);
        return result;
    }

    if (result.isDone && frameHeader.streamIdentifier > 0) {
      result.data = getMessage(channelContext, frameHeader);
      result.data?.streamId = frameHeader.streamIdentifier;
      channelContext.currentRequest = channelContext.getStreamRequest(frameHeader.streamIdentifier);

      if (result.data is HttpResponse) {
        channelContext.removeStream(frameHeader.streamIdentifier);
      }
    }

    return result;
  }

  /// 尝试把当前 stream 标记为大 body streaming 上传。
  ///
  /// 前置条件（调用方保证）：headers 已收全（END_HEADERS=1），且客户端还会继续发 body。
  /// 满足 content-length 阈值时，填充 [result] 让 dispatcher 立即 emit request，
  /// 让 handler 建立远端连接、发送 headers；后续 DATA 帧由 forward 透传。
  bool _tryStartStreamingUpload(
      ChannelContext channelContext, FrameHeader frameHeader, HttpMessage? possibleMessage, DecoderResult<T> result) {
    if (this is! Http2RequestDecoder ||
        possibleMessage is! HttpRequest ||
        possibleMessage.contentLength <= largeBodyThreshold ||
        _largeBodyStreamIds.contains(frameHeader.streamIdentifier)) {
      return false;
    }

    _largeBodyStreamIds.add(frameHeader.streamIdentifier);
    possibleMessage.streamingBody = true;
    possibleMessage.streamId = frameHeader.streamIdentifier;
    logger.w(
        "[${channelContext.clientChannel?.id}] h2 streaming upload stream:${frameHeader.streamIdentifier} contentLength:${possibleMessage.contentLength}");
    result.data = possibleMessage as T;
    result.isDone = true;
    return true;
  }

  List<Header> encodeHeaders(T message);

  @override
  Uint8List encode(ChannelContext channelContext, T data) {
    var bytesBuilder = BytesBuilder();

    // 流式转发：body 由上层 forward 透传，encoder 只写 HEADERS 帧，
    // 且 endStream=false 保留 stream 让后续 DATA 帧进来。
    if (data.streamingBody) {
      var headers = encodeHeaders(data);
      logger.w("h2 streaming encode streamId:${data.streamId} headerCount:${headers.length}");
      writeHeadersFrame(bytesBuilder, channelContext, data.streamId!, headers, endStream: false);
      return bytesBuilder.takeBytes();
    }

    if (data.headers.getInt(HttpHeaders.CONTENT_LENGTH) != null) {
      data.headers.set(HttpHeaders.CONTENT_LENGTH.toLowerCase(), "${data.body?.length ?? 0}");
    }

    var emptyBody = data.body == null || data.body!.isEmpty;

    //headers
    var headers = encodeHeaders(data);

    writeHeadersFrame(bytesBuilder, channelContext, data.streamId!, headers, endStream: emptyBody);

    //body
    if (!emptyBody) {
      var payload = data.body!;
      while (payload.length > maxFrameSize) {
        var chunkSize = min(maxFrameSize, payload.length);
        var chunk = payload.sublist(0, chunkSize);
        payload = payload.sublist(chunkSize);
        _writeFrame(channelContext, bytesBuilder, FrameType.data, 0, data.streamId!, chunk);
      }

      _writeFrame(channelContext, bytesBuilder, FrameType.data, FrameHeader.flagsEndStream, data.streamId!, payload);
    }

    return bytesBuilder.takeBytes();
  }

  void writeHeadersFrame(
    BytesBuilder bytesBuilder,
    ChannelContext channelContext,
    int streamId,
    List<Header> headers, {
    StreamSetting? setting,
    bool endStream = true,
  }) {
    var fragment = _hpackEncoder.encode(headers);
    var maxSize = channelContext.setting?.maxFrameSize ?? maxFrameSize;

    if (fragment.length < maxSize) {
      int flags = FrameHeader.flagsEndHeaders;
      if (endStream) {
        flags |= FrameHeader.flagsEndStream;
      }
      _writeHeadersFrame(bytesBuilder, channelContext, flags, streamId, fragment);
    } else {
      var chunk = fragment.sublist(0, maxSize);
      fragment = fragment.sublist(maxSize);

      _writeHeadersFrame(bytesBuilder, channelContext, 0, streamId, chunk);

      while (fragment.length > maxSize) {
        var chunk = fragment.sublist(0, maxSize);
        fragment = fragment.sublist(maxSize);
        _writeFrame(channelContext, bytesBuilder, FrameType.continuation, 0, streamId, chunk);
      }

      _writeFrame(
          channelContext, bytesBuilder, FrameType.continuation, FrameHeader.flagsEndHeaders, streamId, fragment);

      if (endStream) {
        //如果没有body，发送一个空的DATA帧
        _writeFrame(channelContext, bytesBuilder, FrameType.data, FrameHeader.flagsEndStream, streamId, []);
      }
    }
  }

  void _writeHeadersFrame(
      BytesBuilder bytesBuilder, ChannelContext channelContext, int flags, int streamId, List<int> payload) {
    var streamPriority = channelContext.removeStreamDependency(streamId);
    if (streamPriority != null) {
      flags |= FrameHeader.flagsPriority;
      bool exclusive = streamPriority.exclusiveDependency;
      int streamDependency = streamPriority.streamDependency!;

      payload = [
        (exclusive ? 0x80 : 0) | (streamDependency & 0x7FFFFFFF) >> 24,
        (streamDependency & 0x00FF0000) >> 16,
        (streamDependency & 0x0000FF00) >> 8,
        (streamDependency & 0x000000FF),
        streamPriority.weight!,
        ...payload
      ];
    }

    // logger.d(
    //     "[${channelContext.clientChannel?.id}] ${this is Http2RequestDecoder ? 'request' : 'response'} _writeHeadersFrame streamId:$streamId  flags:$flags originFlags:${streamPriority?.header.flags} ${streamPriority} ${payload.length}");

    _writeFrame(channelContext, bytesBuilder, FrameType.headers, flags, streamId, payload);
  }

  void _writeFrame(ChannelContext channelContext, BytesBuilder bytesBuilder, FrameType type, int flags, int streamId,
      List<int> payload) {
    FrameHeader frameHeader = FrameHeader(payload.length, type, flags, streamId);
    // logger.d(
    //     "[${channelContext.clientChannel?.id}] ${this is Http2RequestDecoder ? 'request' : 'response'} _writeFrame streamId:${frameHeader.streamIdentifier}  ${frameHeader.type} flags:${frameHeader.flags} endHeaders: ${frameHeader.hasEndHeadersFlag} endStream: ${frameHeader.hasEndStreamFlag} ${payload.length}");

    bytesBuilder.add(frameHeader.encode());
    bytesBuilder.add(payload);
  }

  bool isConnectionPrefacePRI(ByteBuf data) {
    if (data.readableBytes() < 9) {
      return false;
    }
    for (int i = 0; i < connectionPrefacePRI.length; i++) {
      if (data.get(data.readerIndex + i) != connectionPrefacePRI[i]) {
        return false;
      }
    }
    return true;
  }

  void _handleSseDataFrame(
      ChannelContext channelContext, FrameHeader frameHeader, HttpMessage message, ByteBuf payload) {
    //  DATA 帧格式
    int padLength = 0;
    if (frameHeader.hasPaddedFlag) {
      padLength = payload.readByte();
    }
    int dataLength = payload.readableBytes() - padLength;
    var data = payload.readBytes(dataLength);
    // Incremental SSE parsing: do not accumulate full body to avoid large memory usage
    final decoder = sseDecoders.putIfAbsent(frameHeader.streamIdentifier, () => SseDecoder());
    final frames = decoder.feed(Uint8List.fromList(data));
    for (final WebSocketFrame frame in frames) {
      frame.isFromClient = false; // server -> client
      message.messages.add(frame);
      channelContext.listener?.onMessage(channelContext.clientChannel!, message, frame);
      logger.d(
          '[${channelContext.clientChannel?.id}] h2 sse streamId:${frameHeader.streamIdentifier} frame ${frame.payloadLength} ${frame.payloadDataAsString}');
    }

    if (frameHeader.hasEndStreamFlag) {
      sseDecoders.remove(frameHeader.streamIdentifier);
      channelContext.removeStream(frameHeader.streamIdentifier);
    }
  }

  DataFrame _handleDataFrame(
      ChannelContext channelContext, FrameHeader frameHeader, HttpMessage message, ByteBuf payload) {
    //  DATA 帧格式
    int padLength = 0;
    if (frameHeader.hasPaddedFlag) {
      padLength = payload.readByte();
    }

    //读取数据
    int dataLength = payload.readableBytes() - padLength;
    var data = payload.readBytes(dataLength);

    // Regular body accumulation.
    // 用 BytesBuilder 拼接，比 List.from(body!)..addAll(data) 少一次中间拷贝；
    // 整体累积仍是 O(N²)（每次 toBytes 分配 sum 大 buffer），但常数更小。
    if (message.body == null) {
      message.body = data;
    } else {
      final builder = BytesBuilder(copy: false)
        ..add(message.body!)
        ..add(data);
      message.body = builder.toBytes();
    }
    message.packageSize = (message.packageSize ?? 0) + frameHeader.length;
    return DataFrame(frameHeader, padLength, data);
  }

  HeadersFrame _handleHeadersFrame(ChannelContext channelContext, FrameHeader frameHeader, ByteBuf payload) {
    //  HEADERS 帧格式
    int padLength = 0;
    //如果帧头部有PADDED标志位，则需要读取PADDED长度
    if (frameHeader.hasPaddedFlag) {
      padLength = payload.readByte();
    }

    int? streamDependency;
    bool exclusiveDependency = false;
    int? weight;
    //如果帧头部有PRIORITY标志位，则需要读取优先级信息
    if (frameHeader.hasPriorityFlag) {
      if (payload.readableBytes() < 5) {
        throw Exception("Invalid PRIORITY frame: insufficient data");
      }

      // 读取依赖流 ID 和权重
      int dependency = payload.readInt();
      exclusiveDependency = (dependency & 0x80000000) != 0; // 检查最高位是否为 1
      streamDependency = dependency & 0x7FFFFFFF; // 获取低 31 位
      weight = payload.readByte(); // 读取权重

      // logger.d(
      //     "PRIORITY frame parsed: streamId:${frameHeader.streamIdentifier} streamDependency=$streamDependency, weight=$weight $exclusiveDependency");
    }

    var headerBlockLength = payload.length - payload.readerIndex - padLength;
    if (headerBlockLength < 0) {
      throw Exception("headerBlockLength < 0");
    }

    var blockFragment = payload.readBytes(headerBlockLength);

    //读取头部信息
    Map<String, List<String>> headers = _parseHeaders(channelContext, blockFragment);

    T message = createMessage(channelContext, frameHeader, headers);

    headers.forEach((key, values) {
      if (!key.startsWith(":")) {
        message.headers.addValues(key, values);
      }
    });

    message.streamId = frameHeader.streamIdentifier;
    message.packageSize = frameHeader.length;
    return HeadersFrame(frameHeader, padLength, exclusiveDependency, streamDependency, weight, blockFragment);
  }

  Map<String, List<String>> _parseHeaders(ChannelContext channelContext, List<int> payload) {
    if (channelContext.setting != null) {
      decoder.updateMaxReceivingHeaderTableSize(channelContext.setting!.headTableSize);
    }

    // Decode the headers
    List<Header> headers = decoder.decode(payload);

    // Convert the headers to a map
    Map<String, List<String>> headerMap = {};
    for (Header header in headers) {
      final name = header.nameString;
      final value = header.valueString;
      headerMap[name] ??= [];
      headerMap[name]!.add(value);
    }

    return headerMap;
  }
}

class Http2RequestDecoder extends Http2Codec<HttpRequest> {
  @override
  HttpRequest createMessage(ChannelContext channelContext, FrameHeader frameHeader, Map<String, List<String>> headers) {
    HttpMethod httpMethod = HttpMethod.valueOf(headers[":method"]!.first);

    var httpRequest =
        HttpRequest(httpMethod, headers[":path"]!.first, protocolVersion: headers[":version"]?.firstOrNull ?? "HTTP/2");

    String? authority = headers[":authority"]?.firstOrNull;
    String? scheme = headers[":scheme"]?.firstOrNull;

    if (authority == null || scheme == null) {
      logger.e("Invalid HTTP/2 request headers: $headers");
    } else {
      // 解析 authority，提取主机和端口
      String host = authority;
      int port = (scheme == 'https' ? 443 : 80);

      if (authority.startsWith("[")) {
        int closeBracketIndex = authority.indexOf(']');
        if (closeBracketIndex != -1) {
          host = authority.substring(0, closeBracketIndex + 1);
          if (authority.length > closeBracketIndex + 1 && authority[closeBracketIndex + 1] == ':') {
            port = int.tryParse(authority.substring(closeBracketIndex + 2)) ?? port;
          }
        }
      } else {
        int lastColonIndex = authority.lastIndexOf(':');
        if (lastColonIndex != -1) {
          var p = int.tryParse(authority.substring(lastColonIndex + 1));
          if (p != null) {
            host = authority.substring(0, lastColonIndex);
            port = p;
          }
        }
      }
      httpRequest.hostAndPort = HostAndPort("$scheme://", host, port);
    }

    var old = channelContext.putStreamRequest(frameHeader.streamIdentifier, httpRequest);
    assert(old == null, "old request is not null");
    return httpRequest;
  }

  @override
  HttpRequest? getMessage(ChannelContext channelContext, FrameHeader frameHeader) {
    return channelContext.getStreamRequest(frameHeader.streamIdentifier);
  }

  @override
  List<Header> encodeHeaders(HttpRequest message) {
    var headers = <Header>[];
    var uri = message.requestUri!;
    headers.add(Header.ascii(":method", message.method.name));
    headers.add(Header.ascii(":scheme", uri.scheme));
    headers.add(Header.ascii(":authority", uri.host));
    headers.add(Header.ascii(":path", message.uri));

    // h2 禁止的 hop-by-hop headers (RFC 7540 §8.1.2.2)：
    // Cloudflare 等严格 upstream 收到会直接返回 400。
    const forbidden = {'connection', 'proxy-connection', 'keep-alive', 'transfer-encoding', 'upgrade', 'host'};

    message.headers.forEach((key, values) {
      final lower = key.toLowerCase();
      if (forbidden.contains(lower)) return;
      for (var value in values) {
        // 用 latin1 编码：h2 header value 是 opaque bytes，Cookie 或
        // Content-Disposition 里可能出现非 ASCII 字符，用 ascii.encode 会抛异常。
        // 但要剥离 NUL/CR/LF（h2 禁止），避免 header injection 或 upstream 解析错误。
        final valueBytes = _sanitizeHeaderValue(latin1.encode(value));
        headers.add(Header(latin1.encode(lower), valueBytes));
      }
    });
    return headers;
  }

  static Uint8List _sanitizeHeaderValue(Uint8List bytes) {
    for (final b in bytes) {
      if (b == 0x00 || b == 0x0A || b == 0x0D) {
        // 有非法字节才走 copy 路径
        return Uint8List.fromList(bytes.where((c) => c != 0x00 && c != 0x0A && c != 0x0D).toList());
      }
    }
    return bytes;
  }
}

class Http2ResponseDecoder extends Http2Codec<HttpResponse> {
  @override
  HttpResponse createMessage(
      ChannelContext channelContext, FrameHeader frameHeader, Map<String, List<String>> headers) {
    var httpResponse = HttpResponse(HttpStatus.valueOf(int.parse(headers[':status']!.first)),
        protocolVersion: headers[":version"]?.firstOrNull ?? 'HTTP/2');
    final requestId = channelContext.getStreamRequest(frameHeader.streamIdentifier)?.requestId;
    if (requestId != null) {
      httpResponse.requestId = requestId;
    }
    channelContext.putStreamResponse(frameHeader.streamIdentifier, httpResponse);
    return httpResponse;
  }

  @override
  HttpResponse? getMessage(ChannelContext channelContext, FrameHeader frameHeader) {
    return channelContext.getStreamResponse(frameHeader.streamIdentifier);
  }

  @override
  List<Header> encodeHeaders(HttpResponse message) {
    var headers = <Header>[];
    headers.add(Header.ascii(":status", message.status.code.toString()));
    message.headers.forEach((key, values) {
      for (var value in values) {
        headers.add(Header.ascii(key, value));
      }
    });
    return headers;
  }
}

class FrameReader {
  static int headerLength = 9;

  static List<int>? _readFramePayload(ByteBuf data, int length) {
    if (data.readableBytes() < length) {
      return null;
    }

    var readBytes = data.readBytes(length);
    data.clearRead();
    return readBytes;
  }

  static FrameHeader? readFrameHeader(ByteBuf data) {
    if (data.readableBytes() < headerLength) {
      return null;
    }

    int length = data.read() << 16 | data.read() << 8 | data.read();
    FrameType type = FrameType.values[data.read()];
    int flags = data.read();
    int streamIdentifier = data.readInt();

    return FrameHeader(length, type, flags, streamIdentifier);
  }
}
