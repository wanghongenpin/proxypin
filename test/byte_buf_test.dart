import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/util/byte_buf.dart';

void main() {
  group('ByteBuf construction', () {
    test('empty buffer has zero length', () {
      var buf = ByteBuf();
      expect(buf.length, 0);
      expect(buf.isReadable(), false);
      expect(buf.readableBytes(), 0);
    });

    test('constructor with bytes sets writer index', () {
      var buf = ByteBuf([1, 2, 3, 4]);
      expect(buf.length, 4);
      expect(buf.readerIndex, 0);
      expect(buf.writerIndex, 4);
      expect(buf.isReadable(), true);
    });
  });

  group('ByteBuf read operations', () {
    test('readByte returns sequential bytes', () {
      var buf = ByteBuf([0x41, 0x42, 0x43]);
      expect(buf.readByte(), 0x41);
      expect(buf.readByte(), 0x42);
      expect(buf.readByte(), 0x43);
      expect(buf.isReadable(), false);
    });

    test('readShort reads big-endian short', () {
      var buf = ByteBuf([0x00, 0xFF]);
      expect(buf.readShort(), 255);
    });

    test('readShort reads 0x0100 as 256', () {
      var buf = ByteBuf([0x01, 0x00]);
      expect(buf.readShort(), 256);
    });

    test('readInt reads big-endian int', () {
      var buf = ByteBuf([0x00, 0x00, 0x01, 0x00]);
      expect(buf.readInt(), 256);
    });

    test('readBytes returns a sublist and advances reader', () {
      var buf = ByteBuf([10, 20, 30, 40, 50]);
      var read = buf.readBytes(3);
      expect(read, Uint8List.fromList([10, 20, 30]));
      expect(buf.readerIndex, 3);
      expect(buf.readableBytes(), 2);
    });

    test('readAvailableBytes reads all remaining', () {
      var buf = ByteBuf([1, 2, 3]);
      buf.readByte();
      var rest = buf.readAvailableBytes();
      expect(rest, Uint8List.fromList([2, 3]));
      expect(buf.isReadable(), false);
    });

    test('skipBytes advances reader index', () {
      var buf = ByteBuf([1, 2, 3, 4, 5]);
      buf.skipBytes(3);
      expect(buf.readerIndex, 3);
      expect(buf.readByte(), 4);
    });

    test('get returns byte at index without advancing', () {
      var buf = ByteBuf([10, 20, 30]);
      expect(buf.get(1), 20);
      expect(buf.readerIndex, 0);
    });
  });

  group('ByteBuf write operations', () {
    test('add appends bytes', () {
      var buf = ByteBuf();
      buf.add([1, 2, 3]);
      buf.add([4, 5]);
      expect(buf.length, 5);
      expect(buf.bytes, Uint8List.fromList([1, 2, 3, 4, 5]));
    });

    test('add triggers capacity expansion', () {
      var buf = ByteBuf([1]);
      buf.add(List.filled(100, 0));
      expect(buf.length, 101);
    });
  });

  group('ByteBuf clear operations', () {
    test('clear resets all indices', () {
      var buf = ByteBuf([1, 2, 3]);
      buf.readByte();
      buf.clear();
      expect(buf.length, 0);
      expect(buf.readerIndex, 0);
      expect(buf.writerIndex, 0);
    });

    test('clearRead compacts buffer', () {
      var buf = ByteBuf([1, 2, 3, 4, 5]);
      buf.readBytes(3);
      buf.clearRead();
      expect(buf.readerIndex, 0);
      expect(buf.writerIndex, 2);
      expect(buf.bytes, Uint8List.fromList([4, 5]));
    });

    test('clearRead on fully read buffer clears', () {
      var buf = ByteBuf([1, 2]);
      buf.readBytes(2);
      buf.clearRead();
      expect(buf.length, 0);
      expect(buf.readerIndex, 0);
    });
  });

  group('ByteBuf misc', () {
    test('truncate limits readable bytes', () {
      var buf = ByteBuf([1, 2, 3, 4, 5]);
      buf.truncate(3);
      expect(buf.readableBytes(), 3);
    });

    test('truncate throws on insufficient data', () {
      var buf = ByteBuf([1, 2]);
      expect(() => buf.truncate(5), throwsException);
    });

    test('dup creates independent copy', () {
      var buf = ByteBuf([1, 2, 3]);
      var copy = buf.dup();
      copy.readByte();
      expect(copy.readerIndex, 1);
      expect(buf.readerIndex, 0);
    });
  });
}
