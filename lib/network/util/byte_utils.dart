import 'dart:typed_data';

List<int> viewOrSublist(List<int> data, int offset, int length) {
  if (data is Uint8List) {
    return Uint8List.view(data.buffer, data.offsetInBytes + offset, length);
  } else {
    return data.sublist(offset, offset + length);
  }
}

int readInt64(List<int> bytes, int offset) {
  var high = readInt32(bytes, offset);
  var low = readInt32(bytes, offset + 4);
  return high << 32 | low;
}

int readInt32(List<int> bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

int readInt24(List<int> bytes, int offset) {
  return (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2];
}

int readInt16(List<int> bytes, int offset) {
  return (bytes[offset] << 8) | bytes[offset + 1];
}

void setInt64(List<int> bytes, int offset, int value) {
  setInt32(bytes, offset, value >> 32);
  setInt32(bytes, offset + 4, value & 0xffffffff);
}

void setInt32(List<int> bytes, int offset, int value) {
  bytes[offset] = (value >> 24) & 0xff;
  bytes[offset + 1] = (value >> 16) & 0xff;
  bytes[offset + 2] = (value >> 8) & 0xff;
  bytes[offset + 3] = value & 0xff;
}

void setInt24(List<int> bytes, int offset, int value) {
  bytes[offset] = (value >> 16) & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
  bytes[offset + 2] = value & 0xff;
}

void setInt16(List<int> bytes, int offset, int value) {
  bytes[offset] = (value >> 8) & 0xff;
  bytes[offset + 1] = value & 0xff;
}
