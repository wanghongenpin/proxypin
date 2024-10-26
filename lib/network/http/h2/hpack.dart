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

import 'dart:convert';
import 'dart:typed_data';

import 'package:proxypin/network/http/h2/huffman.dart';
import 'package:proxypin/network/util/byte_buf.dart';

class HPACKDecoder {
  // static const int _maxHeaderTableSize = 12288;
  static HuffmanDecoder huffmanDecoder = HuffmanDecoder();
  final IndexTable _indexTable = IndexTable();

  updateTableSize(int size) {
    _indexTable._maxSize = size;
  }

  List<Header> decode(List<int> bytes) {
    var headers = <Header>[];
    var payload = ByteBuf(bytes);
    while (payload.isReadable()) {
      var header = _decodeHeader(payload);
      if (header == null) continue;
      headers.add(header);
    }
    return headers;
  }

  Header? _decodeHeader(ByteBuf framePayload) {
    if (!framePayload.isReadable()) {
      return null;
    }

    int firstByte = framePayload.get(framePayload.readerIndex);
    if (firstByte & 0x80 == 0x80) {
      // Indexed Header Field
      int headerIndex = _decodeInteger(framePayload, 7);
      return _indexTable[headerIndex];
    } else if (firstByte & 0x40 == 0x40) {
      // Literal Header Field with Incremental Indexing
      int headerIndex = _decodeInteger(framePayload, 6);
      Header header = _readHeaderField(framePayload, headerIndex);
      _indexTable.add(header);
      return header;
    } else if (firstByte & 0x20 == 0x20) {
      // Dynamic Table Size Update
      int maxSize = _decodeInteger(framePayload, 5);
      _indexTable._maxSize = maxSize;
    } else if (firstByte & 0x10 == 0x10) {
      // Literal Header Field never Indexed
      int headerIndex = _decodeInteger(framePayload, 4);
      Header header = _readHeaderField(framePayload, headerIndex, neverIndexed: true);
      return header;
    } else {
      // Literal Header Field without Indexing
      int headerIndex = _decodeInteger(framePayload, 4);
      Header header = _readHeaderField(framePayload, headerIndex);
      return header;
    }
    return null;
  }

  Header _readHeaderField(ByteBuf data, int index, {bool neverIndexed = false}) {
    if (index > 0) {
      String name = _indexTable[index].name;
      String value = _decodeString(data, neverIndexed: neverIndexed);
      return Header(name, value);
    }

    String name = _decodeString(data);
    String value = _decodeString(data, neverIndexed: neverIndexed);
    return Header(name, value);
  }

  String _decodeString(ByteBuf data, {bool neverIndexed = false}) {
    int firstByte = data.get(data.readerIndex);
    bool huffmanEncoded = (firstByte & 0x80) == 0x80;
    int length = _decodeInteger(data, 7);

    Uint8List stringBytes = data.readBytes(length);
    if (huffmanEncoded) {
      // If the string is Huffman encoded, decode it using a Huffman decoder.
      return ascii.decode(huffmanDecoder.decode(stringBytes));
    } else {
      // If the string is not Huffman encoded, simply create a new string from the bytes.
      return ascii.decode(stringBytes);
    }
  }

  int _decodeInteger(ByteBuf data, int prefixLength) {
    int prefixMask = (1 << prefixLength) - 1;
    int value = data.read() & prefixMask;

    if (value < prefixMask) {
      return value;
    }

    int shift = 0;
    int b;
    do {
      b = data.read();
      value += (b & 127) << shift;
      shift += 7;
    } while ((b & 128) == 128);

    return value;
  }
}

class HPACKEncoder {
  final IndexTable _indexTable = IndexTable();
  static HuffmanEncoder huffmanEncoder = HuffmanEncoder();

  List<int> encodeList(List<Header> headers) {
    var bytesBuilder = BytesBuilder();

    for (var header in headers) {
      _encodeHeader(bytesBuilder, header);
    }

    return bytesBuilder.takeBytes();
  }

  List<int> encode(Header header) {
    var bytesBuilder = BytesBuilder();
    _encodeHeader(bytesBuilder, header);
    return bytesBuilder.takeBytes();
  }

  void _encodeHeader(BytesBuilder bytesBuilder, Header header) {
    var name = header.name;
    var value = header.value;
    var index = _getIndex(name, value);
    if (index != null) {
      _encodeInteger(bytesBuilder, 7, 0x80, index);
      return;
    }

    var nameIndex = _getIndex(name);
    if (nameIndex != null) {
      _encodeInteger(bytesBuilder, 4, 0, nameIndex);
    } else {
      bytesBuilder.addByte(0);
      _encodeString(bytesBuilder, name);
    }
    _encodeString(bytesBuilder, value);
  }

  int? _getIndex(String name, [String? value]) {
    for (var i = 1; i < _indexTable.length; i++) {
      var header = _indexTable[i];
      if (header.name == name && (value == null || header.value == value)) {
        return i;
      }
    }
    return null;
  }

  _encodeString(BytesBuilder bytesBuilder, String value) {
    var encoded = ascii.encode(value);

    var huffmanEncoded = huffmanEncoder.encode(encoded);
    if (huffmanEncoded.length < encoded.length) {
      _encodeInteger(bytesBuilder, 7, 0x80, huffmanEncoded.length);
      bytesBuilder.add(huffmanEncoded);
    } else {
      _encodeInteger(bytesBuilder, 7, 0x00, encoded.length);
      bytesBuilder.add(encoded);
    }
  }

  void _encodeInteger(BytesBuilder bytesBuilder, int prefixBits, int mask, int value) {
    assert(prefixBits <= 8);

    if (value < (1 << prefixBits) - 1) {
      bytesBuilder.addByte(value | mask);
    } else {
      bytesBuilder.addByte(((1 << prefixBits) - 1) | mask);
      value -= (1 << prefixBits) - 1;
      while (value >= 128) {
        bytesBuilder.addByte(value % 128 + 128);
        value ~/= 128;
      }
      bytesBuilder.addByte(value);
    }
  }
}

class Header {
  final String name;
  String value;

  Header(String name, this.value) : name = name.toLowerCase();

  @override
  String toString() {
    return '{name: $name, value: $value}';
  }
}

class IndexTable {
  static final List<Header> _staticTable = [
    Header('', ''),
    Header(':authority', ''),
    Header(':method', 'GET'),
    Header(':method', 'POST'),
    Header(':path', '/'),
    Header(':path', '/index.html'),
    Header(':scheme', 'http'),
    Header(':scheme', 'https'),
    Header(':status', '200'),
    Header(':status', '204'),
    Header(':status', '206'),
    Header(':status', '304'),
    Header(':status', '400'),
    Header(':status', '404'),
    Header(':status', '500'),
    Header('accept-charset', ''),
    Header('accept-encoding', 'gzip, deflate, br'),
    Header('accept-language', ''),
    Header('accept-ranges', ''),
    Header('accept', ''),
    Header('access-control-allow-origin', ''),
    Header('age', ''),
    Header('allow', ''),
    Header('authorization', ''),
    Header('cache-control', ''),
    Header('content-disposition', ''),
    Header('content-encoding', ''),
    Header('content-language', ''),
    Header('content-length', ''),
    Header('content-location', ''),
    Header('content-range', ''),
    Header('content-type', ''),
    Header('cookie', ''),
    Header('date', ''),
    Header('etag', ''),
    Header('expect', ''),
    Header('expires', ''),
    Header('from', ''),
    Header('host', ''),
    Header('if-match', ''),
    Header('if-modified-since', ''),
    Header('if-none-match', ''),
    Header('if-range', ''),
    Header('if-unmodified-since', ''),
    Header('last-modified', ''),
    Header('link', ''),
    Header('location', ''),
    Header('max-forwards', ''),
    Header('proxy-authenticate', ''),
    Header('proxy-authorization', ''),
    Header('range', ''),
    Header('referer', ''),
    Header('refresh', ''),
    Header('retry-after', ''),
    Header('server', ''),
    Header('set-cookie', ''),
    Header('strict-transport-security', ''),
    Header('transfer-encoding', ''),
    Header('user-agent', ''),
    Header('vary', ''),
    Header('via', ''),
    Header('www-authenticate', ''),
  ];

  //动态表
  final List<Header> _dynamicTable = [];

  int _maxSize = 4096;

  Header operator [](int index) {
    if (index < _staticTable.length) return _staticTable[index];
    if (index < _staticTable.length + _dynamicTable.length) {
      return _dynamicTable[index - _staticTable.length];
    }
    throw RangeError('Invalid index: $index');
  }

  add(Header header) {
    _dynamicTable.add(header);
    _maxSize -= sizeOf(header);
    while (_maxSize < 0) {
      _maxSize += sizeOf(_dynamicTable.removeAt(0));
    }
  }

  int get length => _staticTable.length + _dynamicTable.length;

  int sizeOf(Header header) => header.name.length + header.value.length + 32;
}
