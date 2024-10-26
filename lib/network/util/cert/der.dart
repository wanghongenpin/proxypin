import 'dart:typed_data';
import 'dart:convert';
import 'package:proxypin/network/util/byte_buf.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/src//utils.dart';

class DerValue {
  /// Tag value indicating an ASN.1 "INTEGER" value.
  static const int tagInteger = 0x02;

  /// Tag value indicating an ASN.1 "OCTET STRING" value.
  static const int tagOctetString = 0x04;

  int tag;
  final Uint8List value;
  final ByteBuf buffer;
  late DerInputStream data;

  DerValue(this.tag, this.value, {ByteBuf? buffer}) : buffer = buffer ?? ByteBuf(value) {
    data = DerInputStream(this.buffer);
  }

  factory DerValue.fromBytes(Uint8List bytes) {
    return DerValue.getDerValue(ByteBuf(bytes));
  }

  factory DerValue.getDerValue(ByteBuf inStream) {
    var tag = inStream.read();
    int length = DerInputStream.getLength(inStream);
    var buffer = inStream.dup();
    buffer.truncate(length);

    var value = inStream.readBytes(length);

    return DerValue(tag, value, buffer: buffer);
  }

  Uint8List toByteArray() {
    DerOutputStream out = DerOutputStream();
    encode(out);
    return out.toByteArray();
  }

  void encode(DerOutputStream out) {
    out.writeByte(tag);
    out.writeLength(value.length);
    out.writeBytes(value);
  }

  /// Returns true iff the CONSTRUCTED bit is set in the type tag.
  bool isConstructed() {
    return ((tag & 0x020) == 0x020);
  }

  bool isConstructedTag(int constructedTag) {
    if (!isConstructed()) {
      return false;
    }
    return ((tag & 0x01f) == constructedTag);
  }

  Uint8List getOctetString() {
    if (tag != tagOctetString && !isConstructedTag(tagOctetString)) {
      throw Exception("DerValue.getOctetString, not an Octet String: $tag");
    }

    if (isConstructed()) {
      while (data.buffer.isReadable()) {
        return data.getOctetString();
      }
    }

    return value;
  }

  //get oid
  ASN1ObjectIdentifier getOID() {
    if (tag != 0x06) {
      throw Exception('DER input, Object Identifier tag error');
    }
    int length = value.length;
    int first = value[0] ~/ 40;
    int second = value[0] % 40;
    int oid = first * 40 + second;
    for (int i = 1; i < length; i++) {
      int byte = value[i];
      if (byte < 128) {
        oid = oid * 128 + byte;
      } else {
        oid = oid * 128 + (byte & 0x7F);
      }
    }
    return ASN1ObjectIdentifier.fromIdentifierString(oid.toString());
  }

  DerInputStream toDerInputStream() {
    return data;
  }

  @override
  String toString() {
    return 'DerValue(tag: $tag, value: ${base64.encode(value)})';
  }
}

class DerOutputStream {
  final BytesBuilder _builder = BytesBuilder();

  void writeByte(int byte) {
    _builder.addByte(byte);
  }

  void writeLength(int length) {
    if (length < 128) {
      _builder.addByte(length);
    } else {
      int numBytes = (length.bitLength + 7) >> 3;
      _builder.addByte(0x80 | numBytes);
      for (int i = numBytes - 1; i >= 0; i--) {
        _builder.addByte((length >> (8 * i)) & 0xFF);
      }
    }
  }

  void writeBytes(Uint8List bytes) {
    _builder.add(bytes);
  }

  Uint8List toByteArray() {
    return _builder.toBytes();
  }
}

class DerInputStream {
  final ByteBuf buffer;

  DerInputStream(this.buffer);

  factory DerInputStream.fromBytes(Uint8List data) {
    return DerInputStream(ByteBuf(data));
  }

  static int getLength(ByteBuf inStream) {
    int length = inStream.read();
    if (length & 0x80 == 0) {
      return length;
    }
    int numBytes = length & 0x7F;
    length = 0;
    for (int i = 0; i < numBytes; i++) {
      length = (length << 8) | inStream.read();
    }
    return length;
  }

  int getInteger() {
    if (buffer.read() != DerValue.tagInteger) {
      throw Exception("DER input, Integer tag error");
    }
    var length = getLength(buffer);
    return decodeBigInt(buffer.readBytes(length)).toInt();
  }

  List<DerValue> getSequence(int startLen) {
    int tag = buffer.read();
    if (tag != 0x30) {
      // SEQUENCE tag
      throw Exception('Sequence tag error');
    }

    int length = getLength(buffer);
    Uint8List sequenceData = buffer.readBytes(length);
    DerInputStream sequenceStream = DerInputStream.fromBytes(sequenceData);

    List<DerValue> values = [];
    while (sequenceStream.buffer.isReadable()) {
      int valueTag = sequenceStream.buffer.read();
      int valueLength = getLength(sequenceStream.buffer);
      Uint8List valueData = sequenceStream.buffer.readBytes(valueLength);
      values.add(DerValue(valueTag, valueData));
    }
    return values;
  }

  ASN1ObjectIdentifier getOID() {
    var oid = ASN1ObjectIdentifier.fromBytes(buffer.bytes);
    buffer.read();
    var length = getLength(buffer);
    buffer.skipBytes(length);
    return oid;
  }

  DerValue getDerValue() {
    return DerValue.getDerValue(buffer);
  }

  /// Returns an ASN.1 OCTET STRING from the input stream.
  Uint8List getOctetString() {
    if (buffer.read() != DerValue.tagOctetString) {
      throw Exception("DER input not an octet string");
    }

    int length = getLength(buffer);
    return buffer.readBytes(length);
  }
}

class DerIndefLenConverter {
  static const int LEN_LONG = 0x80; // bit 8 set
  static const int LEN_MASK = 0x7f; // bits 7 - 1

  late Uint8List data;
  late Uint8List newData;
  int newDataPos = 0, dataPos = 0, dataSize = 0, index = 0;
  int unresolved = 0;
  List<Object> ndefsList = [];
  int numOfTotalLenBytes = 0;

  static bool isEOC(Uint8List data, int pos) {
    return data[pos] == 0 && data[pos + 1] == 0;
  }

  static bool isLongForm(int lengthByte) {
    return (lengthByte & LEN_LONG) == LEN_LONG;
  }

  static bool isIndefinite(int lengthByte) {
    return (isLongForm(lengthByte) && ((lengthByte & LEN_MASK) == 0));
  }

  void parseTag() {
    if (isEOC(data, dataPos)) {
      int numOfEncapsulatedLenBytes = 0;
      var elem;
      int index;
      for (index = ndefsList.length - 1; index >= 0; index--) {
        elem = ndefsList[index];
        if (elem is int) {
          break;
        } else {
          numOfEncapsulatedLenBytes += (elem as Uint8List).length - 3;
        }
      }
      if (index < 0) {
        throw Exception("EOC does not have matching indefinite-length tag");
      }

      int sectionLen = dataPos - (elem as int) + numOfEncapsulatedLenBytes;
      Uint8List sectionLenBytes = getLengthBytes(sectionLen);
      ndefsList[index] = sectionLenBytes;
      unresolved--;

      numOfTotalLenBytes += (sectionLenBytes.length - 3);
    }
    dataPos++;
  }

  void writeTag() {
    while (dataPos < dataSize) {
      if (isEOC(data, dataPos)) {
        dataPos += 2;
      } else {
        newData[newDataPos++] = data[dataPos++];
        break;
      }
    }
  }

  int parseLength() {
    if (dataPos == dataSize) {
      return 0;
    }
    int lenByte = data[dataPos++] & 0xff;
    if (isIndefinite(lenByte)) {
      ndefsList.add(dataPos);
      unresolved++;
      return 0;
    }
    int curLen = 0;
    if (isLongForm(lenByte)) {
      lenByte &= LEN_MASK;
      if (lenByte > 4) {
        throw Exception("Too much data");
      }
      if ((dataSize - dataPos) < (lenByte + 1)) {
        return -1;
      }
      for (int i = 0; i < lenByte; i++) {
        curLen = (curLen << 8) + (data[dataPos++] & 0xff);
      }
      if (curLen < 0) {
        throw Exception("Invalid length bytes");
      }
    } else {
      curLen = (lenByte & LEN_MASK);
    }
    return curLen;
  }

  void writeLengthAndValue() {
    if (dataPos == dataSize) {
      return;
    }
    int curLen = 0;
    int lenByte = data[dataPos++] & 0xff;
    if (isIndefinite(lenByte)) {
      Uint8List lenBytes = ndefsList[index++] as Uint8List;
      newData.setRange(newDataPos, newDataPos + lenBytes.length, lenBytes);
      newDataPos += lenBytes.length;
    } else {
      if (isLongForm(lenByte)) {
        lenByte &= LEN_MASK;
        for (int i = 0; i < lenByte; i++) {
          curLen = (curLen << 8) + (data[dataPos++] & 0xff);
        }
        if (curLen < 0) {
          throw Exception("Invalid length bytes");
        }
      } else {
        curLen = (lenByte & LEN_MASK);
      }
      writeLength(curLen);
      writeValue(curLen);
    }
  }

  void writeLength(int curLen) {
    if (curLen < 128) {
      newData[newDataPos++] = curLen;
    } else if (curLen < (1 << 8)) {
      newData[newDataPos++] = 0x81;
      newData[newDataPos++] = curLen;
    } else if (curLen < (1 << 16)) {
      newData[newDataPos++] = 0x82;
      newData[newDataPos++] = (curLen >> 8);
      newData[newDataPos++] = curLen;
    } else if (curLen < (1 << 24)) {
      newData[newDataPos++] = 0x83;
      newData[newDataPos++] = (curLen >> 16);
      newData[newDataPos++] = (curLen >> 8);
      newData[newDataPos++] = curLen;
    } else {
      newData[newDataPos++] = 0x84;
      newData[newDataPos++] = (curLen >> 24);
      newData[newDataPos++] = (curLen >> 16);
      newData[newDataPos++] = (curLen >> 8);
      newData[newDataPos++] = curLen;
    }
  }

  Uint8List getLengthBytes(int curLen) {
    Uint8List lenBytes;
    int index = 0;

    if (curLen < 128) {
      lenBytes = Uint8List(1);
      lenBytes[index++] = curLen;
    } else if (curLen < (1 << 8)) {
      lenBytes = Uint8List(2);
      lenBytes[index++] = 0x81;
      lenBytes[index++] = curLen;
    } else if (curLen < (1 << 16)) {
      lenBytes = Uint8List(3);
      lenBytes[index++] = 0x82;
      lenBytes[index++] = (curLen >> 8);
      lenBytes[index++] = curLen;
    } else if (curLen < (1 << 24)) {
      lenBytes = Uint8List(4);
      lenBytes[index++] = 0x83;
      lenBytes[index++] = (curLen >> 16);
      lenBytes[index++] = (curLen >> 8);
      lenBytes[index++] = curLen;
    } else {
      lenBytes = Uint8List(5);
      lenBytes[index++] = 0x84;
      lenBytes[index++] = (curLen >> 24);
      lenBytes[index++] = (curLen >> 16);
      lenBytes[index++] = (curLen >> 8);
      lenBytes[index++] = curLen;
    }

    return lenBytes;
  }

  void writeValue(int curLen) {
    newData.setRange(newDataPos, newDataPos + curLen, data, dataPos);
    dataPos += curLen;
    newDataPos += curLen;
  }

  Uint8List? convertBytes(Uint8List indefData) {
    data = indefData;
    dataPos = 0;
    dataSize = data.length;

    while (dataPos < dataSize) {
      if (dataPos + 2 > dataSize) {
        return null;
      }
      parseTag();
      int len = parseLength();
      if (len < 0) {
        return null;
      }
      dataPos += len;
      if (dataPos < 0) {
        throw Exception("Data overflow");
      }
      if (unresolved == 0) {
        break;
      }
    }

    if (unresolved != 0) {
      return null;
    }

    int unused = dataSize - dataPos;
    dataSize = dataPos;

    newData = Uint8List(dataSize + numOfTotalLenBytes + unused);
    dataPos = 0;
    newDataPos = 0;
    index = 0;

    while (dataPos < dataSize) {
      writeTag();
      writeLengthAndValue();
    }
    newData.setRange(dataSize + numOfTotalLenBytes, newData.length, data, dataSize);

    return newData;
  }
}
