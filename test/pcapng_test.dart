import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/pcap/pcap.dart';
import 'package:proxypin/network/pcap/pcapng.dart';
import 'package:proxypin/network/util/tls_keylog.dart';

/// 解析 pcapng 的块序列：返回 (type, body)
List<(int, Uint8List)> blocks(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  final out = <(int, Uint8List)>[];
  var o = 0;
  while (o < bytes.length) {
    final type = bd.getUint32(o, Endian.little);
    final len = bd.getUint32(o + 4, Endian.little);
    expect(len % 4, 0, reason: 'block length must be 32-bit aligned');
    expect(bd.getUint32(o + len - 4, Endian.little), len, reason: 'trailing length mismatch');
    out.add((type, Uint8List.sublistView(bytes, o + 8, o + len - 4)));
    o += len;
  }
  return out;
}

bool get hasTshark {
  try {
    return Process.runSync('tshark', ['--version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

void main() {
  test('block layout: SHB, IDB, DSB(TLSK), EPBs', () {
    final records = [
      PcapRecord(DateTime.fromMicrosecondsSinceEpoch(1700000000123456), 3, Uint8List.fromList([1, 2, 3])),
      PcapRecord(DateTime.fromMicrosecondsSinceEpoch(1700000001000000), 8, Uint8List.fromList(List.filled(8, 9))),
    ];
    final bytes = PcapngWriter.build(LinkType.linuxSll2, records, keyLog: 'CLIENT_RANDOM aa bb');
    final b = blocks(bytes);
    expect(b.map((e) => e.$1).toList(), [0x0A0D0D0A, 1, 0x0A, 6, 6]);

    final shb = ByteData.sublistView(b[0].$2);
    expect(shb.getUint32(0, Endian.little), 0x1A2B3C4D);

    final idb = ByteData.sublistView(b[1].$2);
    expect(idb.getUint16(0, Endian.little), LinkType.linuxSll2);

    final dsb = ByteData.sublistView(b[2].$2);
    expect(dsb.getUint32(0, Endian.little), PcapngWriter.secretsTlsKeyLog);
    final len = dsb.getUint32(4, Endian.little);
    expect(String.fromCharCodes(b[2].$2.sublist(8, 8 + len)), 'CLIENT_RANDOM aa bb\n');

    final epb = ByteData.sublistView(b[3].$2);
    final ts = (epb.getUint32(4, Endian.little) << 32) | epb.getUint32(8, Endian.little);
    expect(ts, 1700000000123456);
    expect(epb.getUint32(12, Endian.little), 3);
    expect(b[3].$2.sublist(20, 23), [1, 2, 3]);
  });

  test('no keys -> no DSB', () {
    final bytes = PcapngWriter.build(LinkType.raw, const []);
    expect(blocks(bytes).map((e) => e.$1).toList(), [0x0A0D0D0A, 1]);
  });

  test('TlsKeyLog collects only while enabled, dedupes', () {
    final log = TlsKeyLog.instance;
    log.stop();
    expect(log.callback, isNull);
    log.start();
    log.callback!('CLIENT_RANDOM 01 02\n');
    log.callback!('CLIENT_RANDOM 01 02\n');
    log.callback!('CLIENT_TRAFFIC_SECRET_0 03 04\n');
    log.stop();
    expect(log.length, 2);
    expect(log.connectionCount, 2);
    expect(log.export(), 'CLIENT_RANDOM 01 02\nCLIENT_TRAFFIC_SECRET_0 03 04\n');
    log.clear();
  });

  group('real Dart TLS keyLog capture decrypts in tshark without external keylog', () {
    for (final (name, port) in [('tls13', 18443), ('tls12', 18444)]) {
      test(name, () async {
        final dir = await Directory.systemTemp.createTemp('pcapng');
        final out = File('${dir.path}/$name.pcapng');
        final count = await PcapngWriter.convertFile(File('test/fixtures/${name}_loopback.pcap'), out,
            keyLog: File('test/fixtures/${name}_loopback.keys').readAsStringSync());
        expect(count, greaterThan(10));

        final r = Process.runSync(
            'tshark', ['-r', out.path, '-d', 'tcp.port==$port,tls', '-q', '-z', 'follow,tls,ascii,0']);
        expect(r.stdout, contains('GET /secret-path HTTP/1.1'));
        expect(r.stdout, contains('X-Probe: proxypin-keylog-test'));
        await dir.delete(recursive: true);
      }, skip: hasTshark ? false : 'tshark not installed');
    }
  });
}
