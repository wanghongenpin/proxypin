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

///类似于netty ByteBuf

class ByteBuf {
  late Uint8List _buffer;
  int readerIndex = 0;
  int writerIndex = 0;

  ByteBuf([List<int>? bytes]) {
    if (bytes != null) {
      _buffer = Uint8List.fromList(bytes);
      writerIndex = bytes.length;
    } else {
      _buffer = Uint8List(0); // Initial buffer size
    }
  }

  int get length => writerIndex;

  Uint8List get bytes => Uint8List.sublistView(_buffer, 0, writerIndex);

  void add(List<int> bytes) {
    _ensureCapacity(writerIndex + bytes.length);
    _buffer.setRange(writerIndex, writerIndex + bytes.length, bytes);
    writerIndex += bytes.length;
  }

  void clear() {
    readerIndex = 0;
    writerIndex = 0;
    _buffer = Uint8List(0);
  }

  ///释放已读的空间
  void clearRead() {
    if (readerIndex == writerIndex) {
      clear();
      return;
    }

    if (readerIndex > 0) {
      _buffer = Uint8List.sublistView(_buffer, readerIndex, writerIndex);
      writerIndex -= readerIndex;
      readerIndex = 0;
    }
  }

  bool isReadable() => readerIndex < writerIndex;

  int readableBytes() => writerIndex - readerIndex;

  Uint8List readAvailableBytes() => readBytes(readableBytes());

  Uint8List readBytes(int length) {
    Uint8List result = Uint8List.sublistView(_buffer, readerIndex, readerIndex + length);
    readerIndex += length;
    return result;
  }

  void skipBytes(int length) {
    readerIndex += length;
  }

  int read() => _buffer[readerIndex++];

  int readByte() => _buffer[readerIndex++];

  int readShort() {
    int value = (_buffer[readerIndex] << 8) | _buffer[readerIndex + 1];
    readerIndex += 2;
    return value;
  }

  int readInt() {
    int value = (_buffer[readerIndex] << 24) |
        (_buffer[readerIndex + 1] << 16) |
        (_buffer[readerIndex + 2] << 8) |
        _buffer[readerIndex + 3];
    readerIndex += 4;
    return value;
  }

  int get(int index) => _buffer[index];

  void truncate(int len) {
    if (len > readableBytes()) {
      throw Exception("Insufficient data");
    }

    writerIndex = readerIndex + len;
  }

  ByteBuf dup() {
    ByteBuf buf = ByteBuf();
    buf._buffer = Uint8List.fromList(_buffer);
    buf.readerIndex = readerIndex;
    buf.writerIndex = writerIndex;
    return buf;
  }

  void _ensureCapacity(int required) {
    if (_buffer.length < required) {
      int newSize = _buffer.length <= 1 ? required : _buffer.length * 2;
      while (newSize < required) {
        newSize *= 2;
      }
      Uint8List newBuffer = Uint8List(newSize);
      newBuffer.setRange(0, writerIndex, _buffer);
      _buffer = newBuffer;
    }
  }
}
