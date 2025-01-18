/*
 * Copyright 2023 Hongen Wang All rights reserved.
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

import 'package:proxypin/network/channel.dart';
import 'package:proxypin/network/host_port.dart';
import 'package:proxypin/network/http/body_reader.dart';
import 'package:proxypin/network/http/constants.dart';
import 'package:proxypin/network/http/h2/codec.dart';
import 'package:proxypin/network/http/http_parser.dart';
import 'package:proxypin/network/util/byte_buf.dart';

import '../../utils/compress.dart';
import 'http.dart';
import 'http_headers.dart';

class ParserException implements Exception {
  final String message;
  final String? source;

  ParserException(this.message, [this.source]);

  @override
  String toString() {
    return 'ParserException{message: $message source: $source}';
  }
}

enum State {
  readInitial,
  readHeader,
  body,
  done,
}

class DecoderResult<T> {
  bool isDone = true;
  T? data;

  //转发消息
  List<int>? forward;

  DecoderResult({this.isDone = true});
}

/// 解码
abstract interface class Decoder<T> {
  /// 解码 如果返回null说明数据不完整
  DecoderResult<T> decode(ChannelContext channelContext, ByteBuf byteBuf);
}

/// 编码
abstract interface class Encoder<T> {
  List<int> encode(T data);
}

/// 编解码器
abstract class Codec<D, E> implements Decoder<D>, Encoder<E> {
  static const int defaultMaxInitialLineLength = 1024000; // 1M
  static const int maxBodyLength = 4096000; // 4M
}

/// http编解码
abstract class HttpCodec<T extends HttpMessage> implements Codec<T, T> {
  final HttpParse _httpParse = HttpParse();
  Http2Codec<T>? _h2Codec;
  State _state = State.readInitial;

  late DecoderResult<T> result;

  BodyReader? bodyReader;

  T createMessage(List<String> reqLine);

  Http2Codec<T> getH2Codec() {
    return _h2Codec ??= (this is HttpRequestCodec ? Http2RequestDecoder() : Http2ResponseDecoder()) as Http2Codec<T>;
  }

  @override
  DecoderResult<T> decode(ChannelContext channelContext, ByteBuf data) {
    if (channelContext.serverChannel?.selectedProtocol == HttpConstants.h2) {
      return getH2Codec().decode(channelContext, data);
    }

    //请求行
    if (_state == State.readInitial) {
      init();
      var initialLine = _readInitialLine(data);
      if (initialLine.isEmpty) {
        return result;
      }
      result.data = createMessage(initialLine);
      _state = State.readHeader;
    }

    //请求头
    try {
      if (_state == State.readHeader) {
        _readHeader(data, result.data!);
      }

      //请求体
      if (_state == State.body) {
        bool resolveBody = channelContext.currentRequest?.method != HttpMethod.head;
        var bodyResult = resolveBody ? bodyReader!.readBody(data.readAvailableBytes()) : null;
        if (!resolveBody || bodyResult?.isDone == true) {
          _state = State.done;
          result.data!.body = bodyResult?.body;
        }
      }

      if (_state == State.done) {
        result.data!.body = _convertBody(result.data!.body);
        _state = State.readInitial;
        result.isDone = true;
        return result;
      }
    } catch (e) {
      _state = State.readInitial;
      rethrow;
    }

    return result;
  }

  void init() {
    bodyReader = null;
    result = DecoderResult(isDone: false);
  }

  void initialLine(BytesBuilder buffer, T message);

  @override
  List<int> encode(T message) {
    if (message.streamId != null) {
      return getH2Codec().encode(message);
    }

    BytesBuilder builder = BytesBuilder();
    //请求行
    initialLine(builder, message);

    List<int>? body = message.body;
    if (message.headers.isGzip && body != null) {
      body = gzipEncode(body);
    }

    //请求头
    bool isChunked = message.headers.isChunked;
    message.headers.remove(HttpHeaders.TRANSFER_ENCODING);

    if (body != null && (body.isNotEmpty || isChunked)) {
      message.headers.contentLength = body.length;
    } else if (message.contentLength != 0) {
      message.headers.remove(HttpHeaders.CONTENT_LENGTH);
    }

    message.headers.forEach((key, values) {
      for (var v in values) {
        builder
          ..add(key.codeUnits)
          ..addByte(HttpConstants.colon)
          ..addByte(HttpConstants.sp)
          ..add(v.codeUnits)
          ..addByte(HttpConstants.cr)
          ..addByte(HttpConstants.lf);
      }
    });
    builder.addByte(HttpConstants.cr);
    builder.addByte(HttpConstants.lf);

    //请求体
    builder.add(body ?? Uint8List(0));
    return builder.toBytes();
  }

  //读取起始行
  List<String> _readInitialLine(ByteBuf data) {
    int maxSize = min(data.readableBytes(), Codec.defaultMaxInitialLineLength);
    return _httpParse.parseInitialLine(data, maxSize);
  }

  //读取请求头
  void _readHeader(ByteBuf data, T message) {
    if (_httpParse.parseHeaders(data, message.headers)) {
      _state = State.body;
      bodyReader = BodyReader(message);
    }
  }

  //转换body
  List<int>? _convertBody(List<int>? bytes) {
    if (bytes == null) {
      return null;
    }
    if (result.data!.headers.isGzip) {
      bytes = gzipDecode(bytes);
    }
    return bytes;
  }
}

/// http请求编解码
class HttpRequestCodec extends HttpCodec<HttpRequest> {
  @override
  HttpRequest createMessage(List<String> reqLine) {
    HttpMethod httpMethod = HttpMethod.valueOf(reqLine[0]);
    return HttpRequest(httpMethod, reqLine[1], protocolVersion: reqLine[2]);
  }

  @override
  void initialLine(BytesBuilder buffer, HttpRequest message) {
    String uri = message.uri;

    //http scheme 输入地址和host不一致
    if (uri.startsWith(HostAndPort.httpScheme) &&
        (message.requestUri?.host != message.headers.host && message.headers.host?.contains(':') != true)) {
      uri = message.requestUri?.replace(host: message.headers.host).toString() ?? uri;
    }

    //请求行
    buffer
      ..add(message.method.name.codeUnits)
      ..addByte(HttpConstants.sp)
      ..add(uri.codeUnits)
      ..addByte(HttpConstants.sp)
      ..add(message.protocolVersion.codeUnits)
      ..addByte(HttpConstants.cr)
      ..addByte(HttpConstants.lf);
  }
}

/// http响应编解码
class HttpResponseCodec extends HttpCodec<HttpResponse> {
  @override
  HttpResponse createMessage(List<String> reqLine) {
    var httpStatus = HttpStatus(int.parse(reqLine[1]), reqLine[2]);
    return HttpResponse(httpStatus, protocolVersion: reqLine[0]);
  }

  @override
  void initialLine(BytesBuilder buffer, HttpResponse message) {
    //状态行
    buffer.add(message.protocolVersion.codeUnits);
    buffer.addByte(HttpConstants.sp);
    buffer.add(message.status.code.toString().codeUnits);
    buffer.addByte(HttpConstants.sp);
    buffer.add(message.status.reasonPhrase.codeUnits);
    buffer.addByte(HttpConstants.cr);
    buffer.addByte(HttpConstants.lf);
  }
}

class HttpServerCodec extends Codec<HttpRequest, HttpResponse> {
  HttpRequestCodec requestCodec = HttpRequestCodec();
  HttpResponseCodec responseCodec = HttpResponseCodec();

  @override
  DecoderResult<HttpRequest> decode(ChannelContext channelContext, ByteBuf byteBuf) {
    return requestCodec.decode(channelContext, byteBuf);
  }

  @override
  List<int> encode(HttpResponse data) {
    return responseCodec.encode(data);
  }
}

class HttpClientCodec extends Codec<HttpResponse, HttpRequest> {
  HttpRequestCodec requestCodec = HttpRequestCodec();
  HttpResponseCodec responseCodec = HttpResponseCodec();

  @override
  DecoderResult<HttpResponse> decode(ChannelContext channelContext, ByteBuf byteBuf) {
    return responseCodec.decode(channelContext, byteBuf);
  }

  @override
  List<int> encode(HttpRequest data) {
    return requestCodec.encode(data);
  }
}
