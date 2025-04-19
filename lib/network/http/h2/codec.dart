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
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/h2/hpack.dart';
import 'package:proxypin/network/http/h2/setting.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/byte_buf.dart';

import 'frame.dart';

/// http编解码
abstract class Http2Codec<T extends HttpMessage> implements Codec<T, T> {
  static const maxFrameSize = 16384;

  static final List<int> connectionPrefacePRI = "PRI * HTTP/2.0".codeUnits;
  HPACKDecoder decoder = HPACKDecoder();
  HPACKEncoder encoder = HPACKEncoder();

  T createMessage(ChannelContext channelContext, FrameHeader frameHeader, Map<String, String> headers);

  T? getMessage(ChannelContext channelContext, FrameHeader frameHeader);

  @override
  DecoderResult<T> decode(ChannelContext channelContext, ByteBuf byteBuf, {bool resolveBody = true}) {
    //Connection Preface PRI * HTTP/2.0
    if (byteBuf.get(byteBuf.readerIndex) == 0x50 &&
        byteBuf.get(byteBuf.readerIndex + 1) == 0x52 &&
        byteBuf.get(byteBuf.readerIndex + 2) == 0x49 &&
        isConnectionPrefacePRI(byteBuf)) {
      DecoderResult<T> result = DecoderResult<T>();
      result.forward = byteBuf.readAvailableBytes();
      return result;
    }

    while (byteBuf.isReadable()) {
      DecoderResult<T> result = DecoderResult<T>(isDone: false);
      FrameHeader? frameHeader = FrameReader._readFrameHeader(byteBuf);
      if (frameHeader == null) {
        return result;
      }

      List<int>? framePayload = FrameReader._readFramePayload(byteBuf, frameHeader.length);
      if (framePayload == null) {
        byteBuf.readerIndex -= FrameReader.headerLength;
        return result;
      }

      result = parseHttp2Packet(channelContext, frameHeader, ByteBuf(framePayload));
      if (result.isDone) {
        return result;
      }
    }

    return DecoderResult<T>(isDone: false);
  }

  DecoderResult<T> parseHttp2Packet(ChannelContext channelContext, FrameHeader frameHeader, ByteBuf framePayload) {
    var result = DecoderResult<T>();
    // logger.d("streamId: ${frameHeader.streamIdentifier} ${frameHeader.type} endHeaders: ${frameHeader.hasEndHeadersFlag} "
    //     "endStream: ${frameHeader.hasEndStreamFlag}");
    //根据帧类型进行处理
    switch (frameHeader.type) {
      case FrameType.headers:
        //处理HEADERS帧
        _handleHeadersFrame(channelContext, frameHeader, framePayload);
        result.isDone = frameHeader.hasEndStreamFlag && frameHeader.hasEndHeadersFlag;
        break;
      case FrameType.continuation:
        //处理CONTINUATION帧
        var message = getMessage(channelContext, frameHeader);
        if (message == null) {
          result.forward = List.from(frameHeader.encode())..addAll(framePayload.readAvailableBytes());
          return result;
        }

        Map<String, String> headers = _parseHeaders(channelContext, framePayload.readBytes(frameHeader.length));
        headers.forEach((key, value) => message.headers.add(key, value));

        if (frameHeader.hasEndHeadersFlag &&
            channelContext.getStreamRequest(frameHeader.streamIdentifier)?.method == HttpMethod.head) {
          result.isDone = true;
        }
        break;
      case FrameType.data:
        //处理DATA帧
        _handleDataFrame(channelContext, frameHeader, framePayload);
        result.isDone = frameHeader.hasEndStreamFlag;
        break;
      case FrameType.settings:
        SettingHandler.handleSettingsFrame(channelContext, frameHeader, framePayload);
        result.forward = List.from(frameHeader.encode())..addAll(framePayload.bytes);
        return result;
      default:
        //其他帧类型 原文转发
        result.forward = List.from(frameHeader.encode())..addAll(framePayload.bytes);
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
  Uint8List encode(T data) {
    var bytesBuilder = BytesBuilder();

    //headers
    var headers = encodeHeaders(data);
    BytesBuilder headerBlock = BytesBuilder();
    bool firstFrame = true;
    for (var header in headers) {
      var encode = encoder.encode(header);
      //防止出现桢分片导致header分裂
      if (headerBlock.length + encode.length < maxFrameSize) {
        headerBlock.add(encode);
        continue;
      }
      FrameType frameType = firstFrame ? FrameType.headers : FrameType.continuation;
      int flags = frameType == FrameType.headers && data.body == null ? FrameHeader.flagsEndStream : 0;
      firstFrame = false;

      _writeFrame(bytesBuilder, frameType, flags, data.streamId!, headerBlock.takeBytes());
      headerBlock.add(encode);
    }

    FrameType frameType = firstFrame ? FrameType.headers : FrameType.continuation;
    int flags = frameType == FrameType.headers && data.body == null ? FrameHeader.flagsEndStream : 0;
    flags |= FrameHeader.flagsEndHeaders;

    _writeFrame(bytesBuilder, frameType, flags, data.streamId!, headerBlock.takeBytes());

    //body
    if (data.body != null) {
      var payload = data.body!;
      while (payload.length > maxFrameSize) {
        var chunkSize = min(maxFrameSize, payload.length);
        var chunk = payload.sublist(0, chunkSize);
        payload = payload.sublist(chunkSize);
        _writeFrame(bytesBuilder, FrameType.data, 0, data.streamId!, chunk);
      }

      _writeFrame(bytesBuilder, FrameType.data, FrameHeader.flagsEndStream, data.streamId!, payload);
    }

    return bytesBuilder.takeBytes();
  }

  void _writeFrame(BytesBuilder bytesBuilder, FrameType type, int flag, int streamId, List<int> payload) {
    FrameHeader frameHeader = FrameHeader(payload.length, type, flag, streamId);
    // logger.d("_writeFrame streamId: ${frameHeader.streamIdentifier}  ${frameHeader.type} endHeaders: ${frameHeader
    //         .hasEndHeadersFlag} endStream: ${frameHeader.hasEndStreamFlag}");
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
    frameHeader.length;
    int dataLength = payload.readableBytes() - padLength;
    var data = payload.readBytes(dataLength);
    var message = getMessage(channelContext, frameHeader)!;
    if (message.body == null) {
      message.body = data;
    } else {
      message.body = List.from(message.body!)..addAll(data);
    }
    // print("DataFrame ${message.bodyAsString}");
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
      //读取优先级信息
      int dependency = payload.readInt();
      exclusiveDependency = (dependency & 0x80000000) == 0x80000000;
      streamDependency = dependency & 0x7fffffff;
      weight = payload.readByte(); // weight
    }

    var headerBlockLength = payload.length - payload.readerIndex - padLength;
    if (headerBlockLength < 0) {
      throw Exception("headerBlockLength < 0");
    }

    var blockFragment = payload.readBytes(headerBlockLength);

    //读取头部信息
    Map<String, String> headers = _parseHeaders(channelContext, blockFragment);

    T message = createMessage(channelContext, frameHeader, headers);

    headers.forEach((key, value) {
      if (!key.startsWith(":")) {
        message.headers.add(key, value);
      }
    });

    return HeadersFrame(frameHeader, padLength, exclusiveDependency, streamDependency, weight, blockFragment);
  }

  Map<String, String> _parseHeaders(ChannelContext channelContext, List<int> payload) {
    if (channelContext.setting != null) {
      decoder.updateTableSize(channelContext.setting!.headTableSize);
    }

    // Decode the headers
    List<Header> headers = decoder.decode(payload);

    // Convert the headers to a map
    Map<String, String> headerMap = {};
    for (Header header in headers) {
      headerMap[header.name] = header.value;
    }

    return headerMap;
  }
}

class Http2RequestDecoder extends Http2Codec<HttpRequest> {
  @override
  HttpRequest createMessage(ChannelContext channelContext, FrameHeader frameHeader, Map<String, String> headers) {
    HttpMethod httpMethod = HttpMethod.valueOf(headers[":method"]!);
    var httpRequest = HttpRequest(httpMethod, headers[":path"]!, protocolVersion: headers[":version"] ?? "HTTP/2");
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
    headers.add(Header(":method", message.method.name));
    headers.add(Header(":scheme", uri.scheme));
    headers.add(Header(":authority", uri.host));
    headers.add(Header(":path", message.uri));

    message.headers.forEach((key, values) {
      for (var value in values) {
        headers.add(Header(key, value));
      }
    });
    return headers;
  }
}

class Http2ResponseDecoder extends Http2Codec<HttpResponse> {
  @override
  HttpResponse createMessage(ChannelContext channelContext, FrameHeader frameHeader, Map<String, String> headers) {
    var httpResponse = HttpResponse(HttpStatus.valueOf(int.parse(headers[':status']!)),
        protocolVersion: headers[":version"] ?? 'HTTP/2');
    httpResponse.requestId = channelContext.getStreamRequest(frameHeader.streamIdentifier)!.requestId;
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
    headers.add(Header(":status", message.status.code.toString()));
    message.headers.forEach((key, values) {
      for (var value in values) {
        headers.add(Header(key, value));
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

    return data.readBytes(length);
  }

  static FrameHeader? _readFrameHeader(ByteBuf data) {
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
