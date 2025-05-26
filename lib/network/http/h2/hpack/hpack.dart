// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// HPACK specification. See here for more information:
///   https://tools.ietf.org/html/draft-ietf-httpbis-header-compression-10

import 'dart:convert' show ascii;
import 'dart:typed_data';

import '../../../util/byte_utils.dart';
import 'huffman.dart';
import 'huffman_table.dart';

/// Exception raised due to encoding/decoding errors.
class HPackDecodingException implements Exception {
  final String _message;

  HPackDecodingException(this._message);

  @override
  String toString() => 'HPackDecodingException: $_message';
}

/// A HPACK encoding/decoding context.
///
/// This is a statefull class, so encoding/decoding changes internal state.
class HPackContext {
  final HPackEncoder encoder = HPackEncoder();
  final HPackDecoder decoder = HPackDecoder();

  HPackContext({
    int maxSendingHeaderTableSize = 4096,
    int maxReceivingHeaderTableSize = 4096,
  }) {
    encoder.updateMaxSendingHeaderTableSize(maxSendingHeaderTableSize);
    decoder.updateMaxReceivingHeaderTableSize(maxReceivingHeaderTableSize);
  }
}

/// A HTTP/2 header.
class Header {
  final List<int> name;
  final List<int> value;
  final bool neverIndexed;

  Header(this.name, this.value, {this.neverIndexed = false});

  String get nameString => ascii.decode(name);

  String get valueString => ascii.decode(value);

  factory Header.ascii(String name, String value) {
    // Specs: `However, header field names MUST be converted to lowercase prior
    // to their encoding in HTTP/2. A request or response containing uppercase
    // header field names MUST be treated as malformed (Section 8.1.2.6).`
    return Header(ascii.encode(name.toLowerCase()), ascii.encode(value));
  }

}

/// A stateful HPACK decoder.
class HPackDecoder {
  int _maxHeaderTableSize = 4096;

  final IndexTable _table = IndexTable();

  void updateMaxReceivingHeaderTableSize(int newMaximumSize) {
    _maxHeaderTableSize = newMaximumSize;
  }

  List<Header> decode(List<int> data) {
    var offset = 0;

    int readInteger(int prefixBits) {
      assert(prefixBits <= 8 && prefixBits > 0);

      var byte = data[offset++] & ((1 << prefixBits) - 1);

      int integer;
      if (byte == ((1 << prefixBits) - 1)) {
        // Length encodeded.
        integer = 0;
        var shift = 0;
        while (true) {
          var done = (data[offset] & 0x80) != 0x80;
          integer += (data[offset++] & 0x7f) << shift;
          shift += 7;
          if (done) break;
        }
        integer += (1 << prefixBits) - 1;
      } else {
        // In place length.
        integer = byte;
      }

      return integer;
    }

    List<int> readStringLiteral() {
      var isHuffmanEncoding = (data[offset] & 0x80) != 0;
      var length = readInteger(7);

      var sublist = viewOrSublist(data, offset, length);
      offset += length;
      if (isHuffmanEncoding) {
        return http2HuffmanCodec.decode(sublist);
      } else {
        return sublist;
      }
    }

    Header readHeaderFieldInternal(int index, {bool neverIndexed = false}) {
      List<int> name, value;
      if (index > 0) {
        name = _table.lookup(index).name;
        value = readStringLiteral();
      } else {
        name = readStringLiteral();
        value = readStringLiteral();
      }
      return Header(name, value, neverIndexed: neverIndexed);
    }

    try {
      var headers = <Header>[];
      while (offset < data.length) {
        var byte = data[offset];
        var isIndexedField = (byte & 0x80) != 0;
        var isIncrementalIndexing = (byte & 0xc0) == 0x40;

        var isWithoutIndexing = (byte & 0xf0) == 0;
        var isNeverIndexing = (byte & 0xf0) == 0x10;
        var isDynamicTableSizeUpdate = (byte & 0xe0) == 0x20;

        if (isIndexedField) {
          var index = readInteger(7);
          var field = _table.lookup(index);
          headers.add(field);
        } else if (isIncrementalIndexing) {
          var field = readHeaderFieldInternal(readInteger(6));
          _table.addHeaderField(field);
          headers.add(field);
        } else if (isWithoutIndexing) {
          headers.add(readHeaderFieldInternal(readInteger(4)));
        } else if (isNeverIndexing) {
          headers.add(
            readHeaderFieldInternal(readInteger(4), neverIndexed: true),
          );
        } else if (isDynamicTableSizeUpdate) {
          var newMaxSize = readInteger(5);
          _table.updateMaxSize(newMaxSize);
        } else {
          throw HPackDecodingException('Invalid encoding of headers.');
        }
      }
      return headers;
      // ignore: avoid_catching_errors
    } on RangeError catch (e) {
      throw HPackDecodingException('$e');
    } on HuffmanDecodingException catch (e) {
      throw HPackDecodingException('$e');
    }
  }
}

/// A stateful HPACK encoder.
//  Currently we encode all headers:
//    - without huffman encoding
//    - without using the dynamic table
class HPackEncoder {
  void updateMaxSendingHeaderTableSize(int newMaximumSize) {
    // Once we start encoding via dynamic table we need to let the other
    // side know the maximum table size we're using.
  }

  List<int> encode(List<Header> headers) {
    var bytesBuilder = BytesBuilder();
    var currentByte = 0;

    void writeInteger(int prefixBits, int value) {
      assert(prefixBits <= 8);

      if (value < (1 << prefixBits) - 1) {
        currentByte |= value;
        bytesBuilder.addByte(currentByte);
      } else {
        // Length encodeded.
        currentByte |= (1 << prefixBits) - 1;
        value -= (1 << prefixBits) - 1;
        bytesBuilder.addByte(currentByte);
        var done = false;
        while (!done) {
          currentByte = value & 0x7f;
          value = value >> 7;
          done = value == 0;
          if (!done) currentByte |= 0x80;
          bytesBuilder.addByte(currentByte);
        }
      }
      currentByte = 0;
    }

    void writeStringLiteral(List<int> bytes) {
      // Support huffman encoding.
      currentByte = 0; // 1 would be huffman encoding
      writeInteger(7, bytes.length);
      bytesBuilder.add(bytes);
    }

    void writeLiteralHeaderWithoutIndexing(Header header) {
      bytesBuilder.addByte(0);
      writeStringLiteral(header.name);
      writeStringLiteral(header.value);
    }

    for (var header in headers) {
      writeLiteralHeaderWithoutIndexing(header);
    }

    return bytesBuilder.takeBytes();
  }
}

class IndexTable {
  static final List<Header?> _staticTable = [
    null,
    Header(ascii.encode(':authority'), const []),
    Header(ascii.encode(':method'), ascii.encode('GET')),
    Header(ascii.encode(':method'), ascii.encode('POST')),
    Header(ascii.encode(':path'), ascii.encode('/')),
    Header(ascii.encode(':path'), ascii.encode('/index.html')),
    Header(ascii.encode(':scheme'), ascii.encode('http')),
    Header(ascii.encode(':scheme'), ascii.encode('https')),
    Header(ascii.encode(':status'), ascii.encode('200')),
    Header(ascii.encode(':status'), ascii.encode('204')),
    Header(ascii.encode(':status'), ascii.encode('206')),
    Header(ascii.encode(':status'), ascii.encode('304')),
    Header(ascii.encode(':status'), ascii.encode('400')),
    Header(ascii.encode(':status'), ascii.encode('404')),
    Header(ascii.encode(':status'), ascii.encode('500')),
    Header(ascii.encode('accept-charset'), const []),
    Header(ascii.encode('accept-encoding'), ascii.encode('gzip, deflate')),
    Header(ascii.encode('accept-language'), const []),
    Header(ascii.encode('accept-ranges'), const []),
    Header(ascii.encode('accept'), const []),
    Header(ascii.encode('access-control-allow-origin'), const []),
    Header(ascii.encode('age'), const []),
    Header(ascii.encode('allow'), const []),
    Header(ascii.encode('authorization'), const []),
    Header(ascii.encode('cache-control'), const []),
    Header(ascii.encode('content-disposition'), const []),
    Header(ascii.encode('content-encoding'), const []),
    Header(ascii.encode('content-language'), const []),
    Header(ascii.encode('content-length'), const []),
    Header(ascii.encode('content-location'), const []),
    Header(ascii.encode('content-range'), const []),
    Header(ascii.encode('content-type'), const []),
    Header(ascii.encode('cookie'), const []),
    Header(ascii.encode('date'), const []),
    Header(ascii.encode('etag'), const []),
    Header(ascii.encode('expect'), const []),
    Header(ascii.encode('expires'), const []),
    Header(ascii.encode('from'), const []),
    Header(ascii.encode('host'), const []),
    Header(ascii.encode('if-match'), const []),
    Header(ascii.encode('if-modified-since'), const []),
    Header(ascii.encode('if-none-match'), const []),
    Header(ascii.encode('if-range'), const []),
    Header(ascii.encode('if-unmodified-since'), const []),
    Header(ascii.encode('last-modified'), const []),
    Header(ascii.encode('link'), const []),
    Header(ascii.encode('location'), const []),
    Header(ascii.encode('max-forwards'), const []),
    Header(ascii.encode('proxy-authenticate'), const []),
    Header(ascii.encode('proxy-authorization'), const []),
    Header(ascii.encode('range'), const []),
    Header(ascii.encode('referer'), const []),
    Header(ascii.encode('refresh'), const []),
    Header(ascii.encode('retry-after'), const []),
    Header(ascii.encode('server'), const []),
    Header(ascii.encode('set-cookie'), const []),
    Header(ascii.encode('strict-transport-security'), const []),
    Header(ascii.encode('transfer-encoding'), const []),
    Header(ascii.encode('user-agent'), const []),
    Header(ascii.encode('vary'), const []),
    Header(ascii.encode('via'), const []),
    Header(ascii.encode('www-authenticate'), const []),
  ];

  final List<Header> _dynamicTable = [];

  /// The maximum size the dynamic table can grow to before entries need to be
  /// evicted.
  int _maximumSize = 4096;

  /// The current size of the dynamic table.
  int _currentSize = 0;

  IndexTable();

  /// Updates the maximum size which the dynamic table can grow to.
  void updateMaxSize(int newMaxDynTableSize) {
    _maximumSize = newMaxDynTableSize;
    _reduce();
  }

  /// Lookup an item by index.
  Header lookup(int index) {
    if (index <= 0) {
      throw HPackDecodingException(
        'Invalid index (was: $index) for table lookup.',
      );
    }
    if (index < _staticTable.length) {
      return _staticTable[index]!;
    }
    index -= _staticTable.length;
    if (index < _dynamicTable.length) {
      return _dynamicTable[index];
    }
    throw HPackDecodingException(
      'Invalid index (was: $index) for table lookup.',
    );
  }

  /// Adds a new header field to the dynamic table - and evicts entries as
  /// necessary.
  void addHeaderField(Header header) {
    _dynamicTable.insert(0, header);
    _currentSize += _sizeOf(header);
    _reduce();
  }

  /// Removes as many entries as required to be within the limit of
  /// [_maximumSize].
  void _reduce() {
    while (_currentSize > _maximumSize) {
      var h = _dynamicTable.removeLast();
      _currentSize -= _sizeOf(h);
    }
  }

  /// Returns the "size" a [header] has.
  ///
  /// This is specified to be the number of octets of name/value plus 32.
  int _sizeOf(Header header) => header.name.length + header.value.length + 32;
}
