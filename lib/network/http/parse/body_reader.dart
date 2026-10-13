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

import 'dart:typed_data';

import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';

import '../codec.dart';
import 'chunked_decoder.dart';

class Result {
  final bool isDone;
  final bool supportedParse;

  Uint8List? body;

  Result(this.isDone, {this.body, this.supportedParse = true});
}

class BodyReader {
  final HttpMessage message;

  final BytesBuilder _bodyBuffer = BytesBuilder();

  /// chunked 解码器，仅在 Transfer-Encoding: chunked 时创建；
  /// 内部自行处理 chunk-size 行、chunk 内容尾部 \r\n、chunk-extension、trailer
  /// headers 等跨 TCP 包边界的分片情况。
  final ChunkedDecoder? _chunkedDecoder;

  bool _done = false;

  /// 无 Content-Length、无 Transfer-Encoding: chunked、且非 flv/SSE 的响应，
  /// body 由连接关闭定界。此类 body 先缓冲，待上游关闭时经 [finish] 产出完整内容，
  /// 以便继续参与响应拦截器链（issue #956）。flv/SSE 仍走 unsupported 裸转。
  ///
  /// 惰性判定：不在构造器求值，而是首次读取 body 时计算——能走到 body 解析
  /// 本身就说明 headers 已解析完整（BodyReader 仅在 parseHeaders 完成后才被用于读 body）。
  bool? _closeDelimited;

  bool get closeDelimited => _closeDelimited ??= _isCloseDelimited();

  BodyReader(this.message) : _chunkedDecoder = message.headers.isChunked ? ChunkedDecoder() : null;

  bool _isCloseDelimited() {
    var msg = message;
    return msg is HttpResponse &&
        msg.status.code >= 200 &&
        msg.status.code != 204 &&
        msg.status.code != 304 &&
        msg.status.code != 205 &&
        msg.headers.get(HttpHeaders.CONTENT_LENGTH) == null &&
        !msg.headers.isChunked &&
        msg.headers.contentType != 'video/x-flv' &&
        !msg.headers.contentType.startsWith('text/event-stream');
  }

  Result readBody(Uint8List data) {
    if (_bodyBuffer.length > Codec.maxBodyLength) {
      _bodyBuffer.clear();
      throw ParserException('Body length exceeds ${Codec.maxBodyLength}');
    }

    if (message.headers.contentType == 'video/x-flv' || message.headers.contentType.startsWith("text/event-stream")) {
      //Directly forward without processing for now
      return Result(false, supportedParse: false, body: data);
    }

    if (closeDelimited) {
      // 超上限：放弃缓冲，回退 raw relay。上层 ChannelDispatcher 的 buffer
      // 仍保留完整原始字节（headers + body），可直接透传。
      if (_bodyBuffer.length + data.length > Codec.maxBodyLength) {
        _bodyBuffer.clear();
        return Result(false, supportedParse: false, body: data);
      }
      if (data.isNotEmpty) {
        _bodyBuffer.add(data);
      }
      // 未结束：body 长度未知，只有上游关闭连接才知道完整内容。
      return Result(false);
    }

    if (_chunkedDecoder != null) {
      _readChunked(data);
    } else {
      _readFixedLengthContent(data);
    }

    if (_done) {
      var body = _bodyBuffer.toBytes();
      _bodyBuffer.clear();
      return Result(true, body: body);
    }

    return Result(false);
  }

  /// 上游连接关闭时调用，产出缓冲中的完整 close-delimited body。
  Result finish() {
    if (!closeDelimited) {
      return Result(false);
    }
    _done = true;
    var body = _bodyBuffer.toBytes();
    _bodyBuffer.clear();
    return Result(true, body: body);
  }

  void _readFixedLengthContent(Uint8List data) {
    if (message.contentLength > 0) {
      _bodyBuffer.add(data);
    }

    if (message.contentLength == -1 || _bodyBuffer.length >= message.contentLength) {
      _done = true;
    }
  }

  void _readChunked(Uint8List data) {
    final Uint8List payload;
    try {
      payload = _chunkedDecoder!.feed(data);
    } on FormatException catch (e) {
      throw ParserException(e.message);
    }
    if (payload.isNotEmpty) {
      _bodyBuffer.add(payload);
    }
    if (_chunkedDecoder!.isDone) {
      _done = true;
    }
  }
}
