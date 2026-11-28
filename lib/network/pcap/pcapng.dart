import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:proxypin/network/pcap/pcap.dart';

/// pcapng 写入（小端）。
///
/// 通过 Decryption Secrets Block（DSB，secrets type = TLS Key Log `TLSK`）嵌入 TLS 会话密钥，
/// Wireshark / tshark 打开即可自动解密，无需另行配置 keylog 文件。
///
/// https://www.ietf.org/archive/id/draft-ietf-opsawg-pcapng-03.html
class PcapngWriter {
  static const int _shbType = 0x0A0D0D0A;
  static const int _idbType = 0x00000001;
  static const int _epbType = 0x00000006;
  static const int _dsbType = 0x0000000A;
  static const int _byteOrderMagic = 0x1A2B3C4D;

  /// Decryption Secrets 类型：TLS Key Log
  static const int secretsTlsKeyLog = 0x544c534b;

  /// 选项代码
  static const int _optEnd = 0;
  static const int _optComment = 1;
  static const int _shbUserAppl = 4;

  final BytesBuilder _out = BytesBuilder(copy: false);

  /// 写入段头 + 接口描述（时间精度默认微秒）
  PcapngWriter({required int linkType, int snapLen = 262144, String application = 'ProxyPin', String? comment}) {
    _writeSectionHeader(application, comment);
    _writeInterface(linkType, snapLen);
  }

  /// 嵌入 TLS 密钥（NSS Key Log 文本）。应在相关数据包之前写入。
  void addTlsKeyLog(String keyLog) {
    if (keyLog.trim().isEmpty) return;
    final secrets = utf8.encode(keyLog.endsWith('\n') ? keyLog : '$keyLog\n');
    final body = BytesBuilder(copy: false)
      ..add(_u32(secretsTlsKeyLog))
      ..add(_u32(secrets.length))
      ..add(secrets)
      ..add(_padding(secrets.length));
    _writeBlock(_dsbType, body.takeBytes());
  }

  void addRecord(PcapRecord r) {
    final micros = r.time.microsecondsSinceEpoch;
    final body = BytesBuilder(copy: false)
      ..add(_u32(0)) // interface id
      ..add(_u32((micros >> 32) & 0xFFFFFFFF))
      ..add(_u32(micros & 0xFFFFFFFF))
      ..add(_u32(r.data.length))
      ..add(_u32(r.originalLength))
      ..add(r.data)
      ..add(_padding(r.data.length));
    _writeBlock(_epbType, body.takeBytes());
  }

  /// 取出已写入的字节（可分段写入文件）
  Uint8List takeBytes() => _out.takeBytes();

  void _writeSectionHeader(String application, String? comment) {
    final body = BytesBuilder(copy: false)
      ..add(_u32(_byteOrderMagic))
      ..add(_u16(1)) // major
      ..add(_u16(0)) // minor
      ..add(_u64(-1)) // section length unknown
      ..add(_option(_shbUserAppl, utf8.encode(application)));
    if (comment != null) body.add(_option(_optComment, utf8.encode(comment)));
    body.add(_option(_optEnd, const []));
    _writeBlock(_shbType, body.takeBytes());
  }

  void _writeInterface(int linkType, int snapLen) {
    final body = BytesBuilder(copy: false)
      ..add(_u16(linkType))
      ..add(_u16(0)) // reserved
      ..add(_u32(snapLen));
    _writeBlock(_idbType, body.takeBytes());
  }

  void _writeBlock(int type, Uint8List body) {
    final total = 12 + body.length;
    _out
      ..add(_u32(type))
      ..add(_u32(total))
      ..add(body)
      ..add(_u32(total));
  }

  static Uint8List _option(int code, List<int> value) {
    final b = BytesBuilder(copy: false)
      ..add(_u16(code))
      ..add(_u16(value.length))
      ..add(value)
      ..add(_padding(value.length));
    return b.takeBytes();
  }

  static Uint8List _padding(int length) => Uint8List((4 - length % 4) % 4);

  static Uint8List _u16(int v) => (ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List();

  static Uint8List _u32(int v) => (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();

  static Uint8List _u64(int v) => (ByteData(8)..setInt64(0, v, Endian.little)).buffer.asUint8List();

  // ---------------- 转换 ----------------

  /// 把 pcap 文件流式转换为带密钥的 pcapng，避免大文件一次性读入内存。
  /// 返回写入的数据包数量。
  static Future<int> convertFile(File pcap, File output, {String? keyLog, String? comment}) async {
    final parser = PcapStreamParser();
    final sink = output.openWrite();
    PcapngWriter? writer;
    var count = 0;
    try {
      await for (final chunk in pcap.openRead()) {
        final records = parser.feed(chunk);
        if (writer == null && parser.header != null) {
          writer = PcapngWriter(linkType: parser.header!.linkType, snapLen: parser.header!.snapLen, comment: comment);
          if (keyLog != null) writer.addTlsKeyLog(keyLog);
        }
        for (final r in records) {
          writer!.addRecord(r);
          count++;
        }
        if (writer != null) sink.add(writer.takeBytes());
      }
      if (writer == null) throw PcapFormatException('empty pcap file');
    } finally {
      await sink.close();
    }
    return count;
  }

  /// 由内存中的记录生成 pcapng
  static Uint8List build(int linkType, Iterable<PcapRecord> records, {String? keyLog, String? comment}) {
    final writer = PcapngWriter(linkType: linkType, comment: comment);
    if (keyLog != null) writer.addTlsKeyLog(keyLog);
    for (final r in records) {
      writer.addRecord(r);
    }
    return writer.takeBytes();
  }
}
