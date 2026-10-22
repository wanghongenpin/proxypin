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

import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/parse/body_reader.dart';
import 'package:proxypin/network/http/constants.dart';
import 'package:proxypin/network/http/h2/h2_codec.dart';
import 'package:proxypin/network/http/parse/http_parser.dart';
import 'package:proxypin/network/util/byte_buf.dart';

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
  bool supportedParse;

  //转发消息
  List<int>? forward;

  DecoderResult({this.isDone = true, this.supportedParse = true});
}

/// 解码
abstract interface class Decoder<T> {
  /// 解码 如果返回null说明数据不完整
  DecoderResult<T> decode(ChannelContext channelContext, ByteBuf byteBuf);
}

/// 支持在连接关闭时收尾 close-delimited（无 Content-Length / 无 chunked）
/// 响应体的解码器。此类响应 body 由连接关闭定界，解码器先缓冲，待对端关闭后
/// 由 [ChannelDispatcher.channelInactive] 调用本方法产出完整响应，
abstract interface class CloseDelimitedBodyFinalizer {
  DecoderResult? finishCloseDelimitedBody();
}

/// 编码
abstract interface class Encoder<T> {
  List<int> encode(ChannelContext channelContext, T data);
}

/// 编解码器
abstract class Codec<D, E> implements Decoder<D>, Encoder<E> {
  static const int defaultMaxInitialLineLength = 1024000; // 1M
  static const int maxBodyLength = 4096000; // 4M
}

/// http编解码
abstract class HttpCodec<T extends HttpMessage> implements Codec<T, T>, CloseDelimitedBodyFinalizer {
  final HttpParse _httpParse = HttpParse();
  Http2Codec<T>? _h2Codec;
  State _state = State.readInitial;

  late DecoderResult<T> result;

  BodyReader? bodyReader;

  /// 由客户端编解码器在编码 CONNECT 时置位：下一个响应是该 CONNECT 的
  /// "200 Connection established" 应答，没有 body。解码器在响应完成时自行
  /// 消费清除，不依赖调用方设置 currentRequest，也无需调用方还原。
  bool pendingConnectResponse = false;

  T createMessage(List<String> reqLine);

  Http2Codec<T> getH2Codec() {
    return _h2Codec ??= (this is HttpRequestCodec ? Http2RequestDecoder() : Http2ResponseDecoder()) as Http2Codec<T>;
  }

  @override
  DecoderResult<T> decode(ChannelContext channelContext, ByteBuf data) {
    // 按通道角色取协议：请求解码看客户端连接，响应解码看上游连接。
    // 不能用客户端协议解码上游字节——客户端协商 h2 不代表上游也是 h2
    // （h1-only 服务器/中间盒会回 HTTP/1.1，按 h2 帧解析会越界崩溃）。
    var protocol = this is HttpRequestCodec
        ? channelContext.clientChannel?.selectedProtocol
        : channelContext.serverChannel?.selectedProtocol;

    if (this is HttpRequestCodec &&
        _state == State.readInitial &&
        channelContext.clientChannel?.isSsl != true &&
        Http2Codec.hasConnectionPrefacePrefix(data)) {
      if (data.readableBytes() < Http2Codec.connectionPrefacePRI.length) {
        return DecoderResult<T>(isDone: false);
      }
      channelContext.isHttp2PriorKnowledge = true;
    }

    // 外部代理串联时，上游代理对 CONNECT 的应答（"HTTP/1.1 200 Connection established"）
    // 始终是 HTTP/1.1——即使客户端已协商 h2（此刻与真实服务器的 TLS 尚未建立）。
    // 若按客户端协议走 h2 解码，会把响应文本当作帧头解析（如 'P'=80 被当成帧类型）而越界崩溃。
    bool connectResponsePending = this is HttpResponseCodec && pendingConnectResponse;

    // h2 -> h1 协议转换期间，上游字节一律是 HTTP/1.1（h2c prior-knowledge 不进入转换）。
    bool translation = this is HttpResponseCodec && channelContext.isHttp2Translation;

    if (!connectResponsePending &&
        !translation &&
        (channelContext.isHttp2PriorKnowledge || protocol == HttpConstants.h2 || protocol == HttpConstants.h2_14)) {
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
        // HEAD 响应无 body；CONNECT 的 "200 Connection established" 应答也无
        // body。两种来源都要识别：
        //  - [pendingConnectResponse]：本端刚编码发出 CONNECT（如 App 内部重放走本地代理）；
        //  - currentRequest == CONNECT：ProxyPin 串联上游代理时解码上游的 200。
        // 这些响应必须走原有解析路径，不能按无 Content-Length 响应进 raw relay，否则 TLS 隧道被接管。
        bool isConnectResponse = pendingConnectResponse ||
            (this is HttpResponseCodec && channelContext.currentRequest?.method == HttpMethod.connect);

        bool resolveBody = channelContext.currentRequest?.method != HttpMethod.head && !isConnectResponse;
        var bodyResult = resolveBody ? bodyReader!.readBody(data.readAvailableBytes()) : null;
        if (!resolveBody || bodyResult?.isDone == true) {
          _state = State.done;
          result.data!.body = bodyResult?.body;
        }

        //If the body does not support parsing, forward directly
        if (bodyResult != null && !bodyResult.supportedParse) {
          result.supportedParse = false;
          result.forward = bodyResult.body;
          return result;
        }
      }

      if (_state == State.done) {
        result.data!.body = _convertBody(result.data!.body);
        _state = State.readInitial;
        pendingConnectResponse = false; // CONNECT 应答已读完，自动消费
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

  @override
  DecoderResult<T>? finishCloseDelimitedBody() {
    var reader = bodyReader;
    if (reader == null || _state != State.body) {
      return null;
    }
    var r = reader.finish();
    if (!r.isDone) {
      return null;
    }
    result.data!.body = _convertBody(r.body);
    result.forward = null;
    result.supportedParse = true;
    result.isDone = true;
    _state = State.readInitial;
    pendingConnectResponse = false;
    return result;
  }

  void initialLine(BytesBuilder buffer, T message);

  /// h2 -> h1 转换编码请求时，请求行版本要写成 HTTP/1.1，但不改动消息对象
  /// （抓包侧仍保留客户端真实的 HTTP/2 协议证据）。
  String? _encodeProtocolVersionOverride;

  String protocolVersionOf(T message) => _encodeProtocolVersionOverride ?? message.protocolVersion;

  @override
  List<int> encode(ChannelContext channelContext, T message) {
    // h2 -> h1 协议转换：客户端 ALPN 协商了 h2，但上游 TLS 未选择 h2。
    // 请求按 HTTP/1.1 编码发往上游。
    final bool translateH2ToH1 =
        this is HttpRequestCodec && message.protocolVersion == "HTTP/2" && channelContext.isHttp2Translation;
    // h1 -> h2：上游的 HTTP/1.1 响应按 h2 帧写回客户端（streamId 由响应处理器挂上）。
    final bool translateH1ToH2 = this is HttpResponseCodec &&
        message.protocolVersion != "HTTP/2" &&
        message.streamId != null &&
        channelContext.isHttp2Translation;

    if (message.protocolVersion == "HTTP/2" && !translateH2ToH1) {
      return getH2Codec().encode(channelContext, message);
    }
    if (translateH1ToH2) {
      return getH2Codec().encode(channelContext, message);
    }

    BytesBuilder builder = BytesBuilder();
    //请求行
    if (translateH2ToH1) _encodeProtocolVersionOverride = HttpMessage.http1Version;
    try {
      initialLine(builder, message);
    } finally {
      _encodeProtocolVersionOverride = null;
    }

    List<int>? body = message.body;

    //请求头
    bool isChunked = message.headers.isChunked;
    // Only drop chunked encoding when we actually have the full body to
    // re-frame as Content-Length. For streaming responses (body == null,
    // e.g. SSE/video handoff), keep Transfer-Encoding: chunked so the header
    // stays consistent with the chunk-framed bytes we relay afterwards.
    if (body != null) {
      message.headers.remove(HttpHeaders.TRANSFER_ENCODING);
    }

    if (body != null && (body.isNotEmpty || isChunked)) {
      message.headers.contentLength = body.length;
    } else if (body != null && message.contentLength != 0) {
      message.headers.remove(HttpHeaders.CONTENT_LENGTH);
    }

    // h2 请求没有 Host 头（主机在 :authority 里），HTTP/1.1 上游要求 Host。
    // 直接写入字节流，不改动消息对象（保持抓包数据原样）。
    if (translateH2ToH1 && message is HttpRequest && message.headers.host == null) {
      var hostAndPort = (message as HttpRequest).hostAndPort;
      if (hostAndPort != null) {
        var defaultPort = hostAndPort.scheme == HostAndPort.httpScheme ? 80 : 443;
        var authority = hostAndPort.port == defaultPort ? hostAndPort.host : '${hostAndPort.host}:${hostAndPort.port}';
        builder
          ..add(HttpHeaders.HOST.codeUnits)
          ..addByte(HttpConstants.colon)
          ..addByte(HttpConstants.sp)
          ..add(authority.codeUnits)
          ..addByte(HttpConstants.cr)
          ..addByte(HttpConstants.lf);
      }
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
      ..add(protocolVersionOf(message).codeUnits)
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
    buffer.add(protocolVersionOf(message).codeUnits);
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
  List<int> encode(ChannelContext channelContext, HttpResponse data) {
    return responseCodec.encode(channelContext, data);
  }
}

class HttpClientCodec extends Codec<HttpResponse, HttpRequest> implements CloseDelimitedBodyFinalizer {
  HttpRequestCodec requestCodec = HttpRequestCodec();
  HttpResponseCodec responseCodec = HttpResponseCodec();

  @override
  DecoderResult<HttpResponse> decode(ChannelContext channelContext, ByteBuf byteBuf) {
    return responseCodec.decode(channelContext, byteBuf);
  }

  @override
  DecoderResult? finishCloseDelimitedBody() {
    return responseCodec.finishCloseDelimitedBody();
  }

  @override
  List<int> encode(ChannelContext channelContext, HttpRequest data) {
    // 编码 CONNECT 后，下一个响应是无 body 的 "200 Connection established"，
    // 通知响应解码器内部标记，无需调用方设置/还原 currentRequest。
    if (data.method == HttpMethod.connect) {
      responseCodec.pendingConnectResponse = true;
    }
    return requestCodec.encode(channelContext, data);
  }
}
