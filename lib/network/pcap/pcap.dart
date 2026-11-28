import 'dart:typed_data';

/// libpcap 文件格式流式解析（tcpdump -w - 输出）
///
/// https://www.tcpdump.org/manpages/pcap-savefile.5.html
class PcapRecord {
  /// 抓包时间（微秒精度）
  final DateTime time;

  /// 线路上的原始长度
  final int originalLength;

  /// 链路层帧数据（可能被 snaplen 截断）
  final Uint8List data;

  PcapRecord(this.time, this.originalLength, this.data);
}

class PcapHeader {
  final int versionMajor;
  final int versionMinor;
  final int snapLen;
  final int linkType;
  final bool nanosecond;
  final Endian endian;

  PcapHeader(this.versionMajor, this.versionMinor, this.snapLen, this.linkType, this.nanosecond, this.endian);
}

class PcapFormatException implements Exception {
  final String message;

  PcapFormatException(this.message);

  @override
  String toString() => 'PcapFormatException: $message';
}

/// 增量解析：可按任意边界喂入数据
class PcapStreamParser {
  static const int globalHeaderLength = 24;
  static const int recordHeaderLength = 16;

  /// 单条记录上限，超过视为数据损坏
  static const int maxRecordLength = 256 * 1024;

  PcapHeader? header;
  final BytesBuilder _pending = BytesBuilder(copy: false);
  Uint8List _buffer = Uint8List(0);
  int _offset = 0;

  List<PcapRecord> feed(List<int> chunk) {
    if (chunk.isNotEmpty) {
      if (_offset < _buffer.length) {
        _pending.add(Uint8List.sublistView(_buffer, _offset));
      }
      _pending.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
      _buffer = _pending.takeBytes();
      _offset = 0;
    }

    final records = <PcapRecord>[];
    if (header == null) {
      if (_buffer.length - _offset < globalHeaderLength) return records;
      header = _parseGlobalHeader(ByteData.sublistView(_buffer, _offset, _offset + globalHeaderLength));
      _offset += globalHeaderLength;
    }

    final h = header!;
    while (_buffer.length - _offset >= recordHeaderLength) {
      final bd = ByteData.sublistView(_buffer, _offset, _offset + recordHeaderLength);
      final tsSec = bd.getUint32(0, h.endian);
      final tsFrac = bd.getUint32(4, h.endian);
      final inclLen = bd.getUint32(8, h.endian);
      final origLen = bd.getUint32(12, h.endian);
      if (inclLen > maxRecordLength) {
        throw PcapFormatException('record too large: $inclLen');
      }
      if (_buffer.length - _offset - recordHeaderLength < inclLen) break;

      final start = _offset + recordHeaderLength;
      final data = Uint8List.fromList(Uint8List.sublistView(_buffer, start, start + inclLen));
      final micros = tsSec * 1000000 + (h.nanosecond ? tsFrac ~/ 1000 : tsFrac);
      records.add(PcapRecord(DateTime.fromMicrosecondsSinceEpoch(micros), origLen, data));
      _offset = start + inclLen;
    }
    return records;
  }

  static PcapHeader _parseGlobalHeader(ByteData bd) {
    final magicBE = bd.getUint32(0, Endian.big);
    Endian endian;
    bool nano;
    switch (magicBE) {
      case 0xa1b2c3d4:
        endian = Endian.big;
        nano = false;
      case 0xd4c3b2a1:
        endian = Endian.little;
        nano = false;
      case 0xa1b23c4d:
        endian = Endian.big;
        nano = true;
      case 0x4d3cb2a1:
        endian = Endian.little;
        nano = true;
      default:
        throw PcapFormatException('bad magic 0x${magicBE.toRadixString(16)}');
    }
    return PcapHeader(bd.getUint16(4, endian), bd.getUint16(6, endian), bd.getUint32(16, endian),
        bd.getUint32(20, endian) & 0x0FFFFFFF, nano, endian);
  }

  /// 生成 pcap 文件头（用于导出筛选结果）
  static Uint8List buildGlobalHeader(int linkType, {int snapLen = 262144}) {
    final bd = ByteData(globalHeaderLength);
    bd.setUint32(0, 0xa1b2c3d4, Endian.little);
    bd.setUint16(4, 2, Endian.little);
    bd.setUint16(6, 4, Endian.little);
    bd.setUint32(16, snapLen, Endian.little);
    bd.setUint32(20, linkType, Endian.little);
    return bd.buffer.asUint8List();
  }

  static Uint8List buildRecord(PcapRecord r) {
    final bd = ByteData(recordHeaderLength);
    final micros = r.time.microsecondsSinceEpoch;
    bd.setUint32(0, micros ~/ 1000000, Endian.little);
    bd.setUint32(4, micros % 1000000, Endian.little);
    bd.setUint32(8, r.data.length, Endian.little);
    bd.setUint32(12, r.originalLength, Endian.little);
    final out = BytesBuilder(copy: false)
      ..add(bd.buffer.asUint8List())
      ..add(r.data);
    return out.takeBytes();
  }
}

/// 常用链路类型
class LinkType {
  static const int nullLoopback = 0;
  static const int ethernet = 1;
  static const int raw = 101;
  static const int rawAlt = 12;
  static const int linuxSll = 113;
  static const int ipv4 = 228;
  static const int ipv6 = 229;
  static const int linuxSll2 = 276;
}
