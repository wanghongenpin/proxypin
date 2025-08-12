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

import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/h2/setting.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/util/byte_buf.dart';
import 'package:proxypin/network/util/logger.dart';

import '../../util/byte_utils.dart';
import 'frame.dart';
import 'hpack/hpack.dart';

/// http编解码
abstract class Http2Codec<T extends HttpMessage> implements Codec<T, T> {
  static const maxFrameSize = 16384;

  static final List<int> connectionPrefacePRI = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".codeUnits;

  HPackDecoder decoder = HPackDecoder();

  final HPackEncoder _hpackEncoder = HPackEncoder();

  T createMessage(ChannelContext channelContext, FrameHeader frameHeader, Map<String, List<String>> headers);

  T? getMessage(ChannelContext channelContext, FrameHeader frameHeader);

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

        if (frameHeader.hasEndHeadersFlag &&
            channelContext.getStreamRequest(frameHeader.streamIdentifier)?.method == HttpMethod.head) {
          result.isDone = true;
        }

        break;
      case FrameType.data:
        //处理DATA帧
        _handleDataFrame(channelContext, frameHeader, ByteBuf(framePayload));
        result.isDone = frameHeader.hasEndStreamFlag;
        break;
      case FrameType.settings:
        SettingHandler.handleSettingsFrame(channelContext, frameHeader, ByteBuf(framePayload));
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

  List<Header> encodeHeaders(T message);

  @override
  Uint8List encode(ChannelContext channelContext, T data) {
    var bytesBuilder = BytesBuilder();
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

  DataFrame _handleDataFrame(ChannelContext channelContext, FrameHeader frameHeader, ByteBuf payload) {
    //  DATA 帧格式
    int padLength = 0;
    //如果帧头部有PADDED标志位，则需要读取PADDED长度
    if (frameHeader.hasPaddedFlag) {
      padLength = payload.readByte();
    }

    //读取数据
    int dataLength = payload.readableBytes() - padLength;
    var data = payload.readBytes(dataLength);
    var message = getMessage(channelContext, frameHeader)!;
    if (message.body == null) {
      message.body = data;
    } else {
      message.body = List.from(message.body!)..addAll(data);
    }
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

      logger.d(
          "PRIORITY frame parsed: streamId:${frameHeader.streamIdentifier} streamDependency=$streamDependency, weight=$weight $exclusiveDependency");
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
      if (authority.contains(':')) {
        var parts = authority.split(':');
        host = parts[0];
        port = int.tryParse(parts[1]) ?? (scheme == 'https' ? 443 : 80);
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

    message.headers.forEach((key, values) {
      for (var value in values) {
        headers.add(Header.ascii(key.toLowerCase(), value));
      }
    });
    return headers;
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
