import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/pcap/capture_session.dart';
import 'package:proxypin/network/pcap/packet.dart';
import 'package:proxypin/network/pcap/pcap.dart';

// ---------- 构造测试帧（LINKTYPE_RAW，直接是 IP 包） ----------

List<int> ipv4(List<int> src, List<int> dst, int proto, List<int> l4) {
  final total = 20 + l4.length;
  return [0x45, 0, total >> 8, total & 0xff, 0, 0, 0x40, 0, 64, proto, 0, 0, ...src, ...dst, ...l4];
}

List<int> udp(int sp, int dp, List<int> payload) {
  final len = 8 + payload.length;
  return [sp >> 8, sp & 0xff, dp >> 8, dp & 0xff, len >> 8, len & 0xff, 0, 0, ...payload];
}

List<int> tcp(int sp, int dp, int flags, List<int> payload) =>
    [sp >> 8, sp & 0xff, dp >> 8, dp & 0xff, 0, 0, 0, 1, 0, 0, 0, 0, 0x50, flags, 0xff, 0xff, 0, 0, 0, 0, ...payload];

List<int> dnsName(String name) => [
      for (final l in name.split('.')) ...[l.length, ...l.codeUnits],
      0
    ];

List<int> dnsQuery(String name) => [0x12, 0x34, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0, ...dnsName(name), 0, 1, 0, 1];

List<int> dnsResponse(String name, List<int> ip) => [
      0x12, 0x34, 0x81, 0x80, 0, 1, 0, 1, 0, 0, 0, 0, ...dnsName(name), 0, 1, 0, 1, //
      0xc0, 12, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, ...ip
    ];

List<int> clientHello(String sni) {
  final name = sni.codeUnits;
  final sniExt = [0, 0, 0, name.length + 5, 0, name.length + 3, 0, name.length >> 8, name.length & 0xff, ...name];
  final body = [
    0x03, 0x03, ...List.filled(32, 7), 0, // version, random, session id
    0, 2, 0x13, 0x01, 1, 0, // cipher suites, compression
    sniExt.length >> 8, sniExt.length & 0xff, ...sniExt,
  ];
  final hs = [0x01, 0, body.length >> 8, body.length & 0xff, ...body];
  return [0x16, 0x03, 0x01, hs.length >> 8, hs.length & 0xff, ...hs];
}

Uint8List pcapOf(int linkType, List<List<int>> frames) {
  final b = BytesBuilder();
  b.add(PcapStreamParser.buildGlobalHeader(linkType));
  var t = DateTime.fromMillisecondsSinceEpoch(1700000000000);
  for (final f in frames) {
    t = t.add(const Duration(milliseconds: 5));
    b.add(PcapStreamParser.buildRecord(PcapRecord(t, f.length, Uint8List.fromList(f))));
  }
  return b.takeBytes();
}

const phone = [10, 0, 0, 2];
const dnsServer = [8, 8, 8, 8];
const web = [93, 184, 216, 34];

void main() {
  group('real tcpdump capture (-i any, LINUX_SLL2)', () {
    late Uint8List bytes;
    setUpAll(() => bytes = File('test/fixtures/any_sll2.pcap').readAsBytesSync());

    test('parses header and all records, even fed byte by byte', () {
      final parser = PcapStreamParser();
      final records = <PcapRecord>[];
      for (final b in bytes) {
        records.addAll(parser.feed([b]));
      }
      expect(parser.header!.linkType, LinkType.linuxSll2);
      expect(records.length, 13);
    });

    test('decodes TCP/UDP, HTTP and builds flows', () {
      final s = CaptureSession();
      s.feed(bytes);
      expect(s.packets.length, 13);
      final syn = s.packets.first;
      expect(syn.src, '127.0.0.1');
      expect(syn.dstPort, 18080);
      expect(syn.tcpFlagsText, 'SYN');
      final http = s.packets.firstWhere((p) => p.appProtocol == 'HTTP');
      expect(http.info, 'GET / HTTP/1.1  (test.local)');
      expect(s.packets.any((p) => p.info?.startsWith('HTTP/1.0 200') == true), isTrue);

      expect(s.flows.length, 2);
      final f = s.flows.first;
      expect(f.serverPort, 18080);
      expect(f.name, 'test.local');
      expect(f.totalPackets, 12);
      expect(f.state, 'FIN');
      expect(s.flows.last.protocol, TransportProtocol.udp);
    });

    test('export filtered packets roundtrips', () {
      final s = CaptureSession()..feed(bytes);
      final out = s.exportPcap(s.flows.first.packets);
      final again = CaptureSession()..feed(out);
      expect(again.linkType, LinkType.linuxSll2);
      expect(again.packets.length, 12);
      expect(again.packets.first.record.time, s.packets.first.record.time);
    });
  });

  group('protocol decoders', () {
    test('DNS query / response, IP -> name mapping', () {
      final s = CaptureSession();
      s.feed(pcapOf(LinkType.raw, [
        ipv4(phone, dnsServer, 17, udp(40000, 53, dnsQuery('www.example.com'))),
        ipv4(dnsServer, phone, 17, udp(53, 40000, dnsResponse('www.example.com', web))),
        ipv4(phone, web, 6, tcp(50000, 443, 0x02, [])),
      ]));
      expect(s.packets[0].info, 'Query A www.example.com');
      expect(s.packets[1].info, 'Response A www.example.com -> 93.184.216.34');
      expect(s.dnsNames['93.184.216.34'], 'www.example.com');
      final tcpFlow = s.flows.firstWhere((f) => f.protocol == TransportProtocol.tcp);
      expect(tcpFlow.name, 'www.example.com');
      expect(tcpFlow.client, '10.0.0.2:50000');
    });

    test('TLS ClientHello SNI', () {
      final s = CaptureSession();
      s.feed(pcapOf(LinkType.raw, [ipv4(phone, web, 6, tcp(50001, 443, 0x18, clientHello('api.github.com')))]));
      expect(s.packets.single.appProtocol, 'TLS');
      expect(s.packets.single.info, 'Client Hello, SNI=api.github.com');
      expect(s.flows.single.name, 'api.github.com');
    });

    test('SYN-ACK first packet still orients client correctly', () {
      final s = CaptureSession();
      s.feed(pcapOf(LinkType.raw, [ipv4(web, phone, 6, tcp(443, 50002, 0x12, []))]));
      expect(s.flows.single.clientIp, '10.0.0.2');
      expect(s.flows.single.serverPort, 443);
    });

    test('memory cap drops packets but counts them', () {
      final s = CaptureSession(maxPackets: 2);
      s.feed(pcapOf(LinkType.raw, List.generate(5, (i) => ipv4(phone, web, 17, udp(1000 + i, 9999, [1, 2, 3])))));
      expect(s.packets.length, 2);
      expect(s.totalPackets, 5);
      expect(s.droppedPackets, 3);
    });

    test('truncated packet does not throw', () {
      final s = CaptureSession();
      s.feed(pcapOf(LinkType.raw, [
        [0x45, 0, 0, 40, 0, 0]
      ]));
      expect(s.packets.single.protocol, TransportProtocol.other);
    });
  });

  group('FlowQuery', () {
    late CaptureSession s;
    setUp(() {
      s = CaptureSession();
      s.feed(pcapOf(LinkType.raw, [
        ipv4(phone, dnsServer, 17, udp(40000, 53, dnsQuery('www.example.com'))),
        ipv4(dnsServer, phone, 17, udp(53, 40000, dnsResponse('www.example.com', web))),
        ipv4(phone, web, 6, tcp(50001, 443, 0x18, clientHello('www.example.com'))),
        ipv4(web, phone, 6, tcp(443, 50001, 0x04, [])),
      ]));
      s.flows.last.appName = 'Chrome';
    });

    List<int> ids(String q) => s.flows.where(FlowQuery.schema.parse(q).matches).map((f) => f.id).toList();

    test('proto, port, host, app, state', () {
      expect(ids('proto:dns'), [1]);
      expect(ids('proto:tls'), [2]);
      expect(ids('-proto:dns'), [2]);
      expect(ids('dport:53'), [1]);
      expect(ids('host:*.example.com proto:tcp'), [2]);
      expect(ids('app:chrome'), [2]);
      expect(ids('is:reset'), [2]);
      expect(ids('ip:8.8.8.8 | is:reset'), [1, 2]);
    });
  });
}
