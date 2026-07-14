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

  BodyReader(this.message) : _chunkedDecoder = message.headers.isChunked ? ChunkedDecoder() : null;

  Result readBody(Uint8List data) {
    if (_bodyBuffer.length > Codec.maxBodyLength) {
      _bodyBuffer.clear();
      throw ParserException('Body length exceeds ${Codec.maxBodyLength}');
    }

    if (message.headers.contentType == 'video/x-flv' || message.headers.contentType.startsWith("text/event-stream")) {
      //Directly forward without processing for now
      return Result(false, supportedParse: false, body: data);
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
