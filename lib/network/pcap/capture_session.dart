import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:proxypin/network/pcap/packet.dart';
import 'package:proxypin/network/pcap/pcap.dart';
import 'package:proxypin/utils/query/query.dart';

/// 一条会话流（按 协议 + 双端地址端口 聚合）
class NetFlow {
  final int id;
  final TransportProtocol protocol;

  /// 发起方（首个包的源）
  final String clientIp;
  final int? clientPort;
  final String serverIp;
  final int? serverPort;

  final DateTime firstTime;
  DateTime lastTime;

  final List<Packet> packets = [];
  int upPackets = 0;
  int downPackets = 0;
  int upBytes = 0;
  int downBytes = 0;

  /// 应用层协议（首个识别到的）
  String? appProtocol;

  /// 域名：TLS SNI / HTTP Host / DNS 查询名 / DNS 反查
  String? name;

  /// 来源应用
  int? uid;
  String? appName;
  String? appPackage;
  bool ownerResolved = false;

  bool seenSyn = false;
  bool seenFin = false;
  bool seenRst = false;

  NetFlow(this.id, this.protocol, this.clientIp, this.clientPort, this.serverIp, this.serverPort, this.firstTime)
      : lastTime = firstTime;

  int get totalPackets => upPackets + downPackets;

  int get totalBytes => upBytes + downBytes;

  Duration get duration => lastTime.difference(firstTime);

  String get client => Packet.endpoint(clientIp, clientPort);

  String get server => Packet.endpoint(serverIp, serverPort);

  String get protocolName =>
      appProtocol ??
      switch (protocol) {
        TransportProtocol.tcp => 'TCP',
        TransportProtocol.udp => 'UDP',
        TransportProtocol.icmp => 'ICMP',
        TransportProtocol.icmpv6 => 'ICMPv6',
        TransportProtocol.other => 'OTHER',
      };

  String get state {
    if (protocol != TransportProtocol.tcp) return '';
    if (seenRst) return 'RST';
    if (seenFin) return 'FIN';
    return seenSyn ? 'OPEN' : 'MID';
  }

  /// 首个带摘要的包信息
  String? get info {
    for (final p in packets) {
      if (p.info != null && p.appProtocol != null) return p.info;
    }
    return null;
  }
}

/// 原始抓包会话：解析 pcap 流、聚合 NetFlow，并限制内存占用
class CaptureSession extends ChangeNotifier {
  /// 内存中最多保留的包数 / 字节数（文件中仍是完整数据）
  final int maxPackets;
  final int maxBytes;

  final PcapStreamParser _parser = PcapStreamParser();
  PacketDecoder? _decoder;

  final List<Packet> packets = [];
  final List<NetFlow> flows = [];
  final Map<String, NetFlow> _flowIndex = {};

  /// DNS 解析结果：IP -> 域名
  final Map<String, String> dnsNames = {};

  /// 包所属的流
  Expando<NetFlow> _flowOf = Expando('flow');

  NetFlow? flowOf(Packet p) => _flowOf[p];

  int _storedBytes = 0;
  int totalPackets = 0;
  int totalBytes = 0;
  int droppedPackets = 0;

  /// 新流回调（用于异步查询所属应用）
  void Function(NetFlow flow)? onNewFlow;

  CaptureSession({this.maxPackets = 200000, this.maxBytes = 96 * 1024 * 1024});

  int? get linkType => _parser.header?.linkType;

  bool get memoryFull => droppedPackets > 0;

  void clear() {
    packets.clear();
    flows.clear();
    _flowIndex.clear();
    dnsNames.clear();
    _flowOf = Expando('flow');
    _storedBytes = 0;
    totalPackets = 0;
    totalBytes = 0;
    droppedPackets = 0;
    notifyListeners();
  }

  /// 喂入 pcap 字节流（任意分片），返回新解析的包数
  int feed(List<int> chunk, {bool notify = true}) {
    final records = _parser.feed(chunk);
    if (records.isEmpty) return 0;
    _decoder ??= PacketDecoder(_parser.header!.linkType);
    for (final r in records) {
      totalPackets++;
      totalBytes += r.originalLength;
      if (packets.length >= maxPackets || _storedBytes + r.data.length > maxBytes) {
        droppedPackets++;
        continue;
      }
      final p = _decoder!.decode(totalPackets, r);
      packets.add(p);
      _storedBytes += r.data.length;
      _addToFlow(p);
    }
    if (notify) notifyListeners();
    return records.length;
  }

  void _addToFlow(Packet p) {
    if (!p.isIp) return;
    final a = '${p.src}|${p.srcPort}';
    final b = '${p.dst}|${p.dstPort}';
    final key = '${p.protocol.index}|${a.compareTo(b) < 0 ? '$a|$b' : '$b|$a'}';
    var flow = _flowIndex[key];
    var isNew = false;
    if (flow == null) {
      var clientIp = p.src!, clientPort = p.srcPort, serverIp = p.dst!, serverPort = p.dstPort;
      // 首包是 SYN-ACK 或来自知名端口时，反转方向
      final synAck = p.protocol == TransportProtocol.tcp && p.tcpFlags & 0x12 == 0x12;
      if (synAck || _isWellKnown(p.srcPort) && !_isWellKnown(p.dstPort)) {
        clientIp = p.dst!;
        clientPort = p.dstPort;
        serverIp = p.src!;
        serverPort = p.srcPort;
      }
      flow = NetFlow(flows.length + 1, p.protocol, clientIp, clientPort, serverIp, serverPort, p.time);
      flow.name = dnsNames[serverIp];
      _flowIndex[key] = flow;
      flows.add(flow);
      isNew = true;
    }

    final up = p.src == flow.clientIp && p.srcPort == flow.clientPort;
    if (up) {
      flow.upPackets++;
      flow.upBytes += p.length;
    } else {
      flow.downPackets++;
      flow.downBytes += p.length;
    }
    flow.lastTime = p.time;
    flow.packets.add(p);
    _flowOf[p] = flow;

    if (p.protocol == TransportProtocol.tcp) {
      if (p.tcpFlags & 0x02 != 0) flow.seenSyn = true;
      if (p.tcpFlags & 0x01 != 0) flow.seenFin = true;
      if (p.tcpFlags & 0x04 != 0) flow.seenRst = true;
    }

    if (p.appProtocol != null) {
      flow.appProtocol ??= p.appProtocol;
      _extractName(flow, p);
    }
    if (isNew) onNewFlow?.call(flow);
  }

  void _extractName(NetFlow flow, Packet p) {
    final info = p.info;
    switch (p.appProtocol) {
      case 'TLS':
        if (info != null && info.contains('SNI=')) flow.name = info.substring(info.indexOf('SNI=') + 4);
      case 'HTTP':
        if (info != null && info.endsWith(')') && info.contains('  (')) {
          flow.name ??= info.substring(info.lastIndexOf('  (') + 3, info.length - 1);
        }
      case 'DNS':
      case 'mDNS':
        final payload = p.payload;
        flow.name ??= Dns.queryName(payload);
        final ans = Dns.answers(payload);
        if (ans != null) {
          for (final ip in ans.$2) {
            dnsNames[ip] = ans.$1;
            // 回填已存在、尚无域名的流
            for (final f in flows) {
              if (f.serverIp == ip && f.name == null) f.name = ans.$1;
            }
          }
        }
    }
  }

  static bool _isWellKnown(int? port) => port != null && port < 1024;

  /// 生成只包含指定包的 pcap 文件内容
  Uint8List exportPcap(Iterable<Packet> selected) {
    final out = BytesBuilder(copy: false);
    out.add(PcapStreamParser.buildGlobalHeader(linkType ?? LinkType.raw));
    final sorted = selected.toList()..sort((a, b) => a.index.compareTo(b.index));
    for (final p in sorted) {
      out.add(PcapStreamParser.buildRecord(p.record));
    }
    return out.takeBytes();
  }
}

/// 原始抓包列表的查询字段
class FlowQuery {
  FlowQuery._();

  static bool _proto(NetFlow f, QueryTerm t) {
    for (final v in t.values) {
      final lower = v.toLowerCase();
      if (f.protocolName.toLowerCase() == lower) return true;
      if (lower == 'tcp' && f.protocol == TransportProtocol.tcp) return true;
      if (lower == 'udp' && f.protocol == TransportProtocol.udp) return true;
      if (lower == 'icmp' && (f.protocol == TransportProtocol.icmp || f.protocol == TransportProtocol.icmpv6)) return true;
      if ((lower == 'ipv6' || lower == 'ip6') && f.serverIp.contains(':')) return true;
      if ((lower == 'ipv4' || lower == 'ip4') && !f.serverIp.contains(':')) return true;
    }
    return false;
  }

  static bool _is(NetFlow f, QueryTerm t) {
    for (final v in t.values) {
      final hit = switch (v.toLowerCase()) {
        'open' => f.protocol == TransportProtocol.tcp && !f.seenFin && !f.seenRst,
        'closed' => f.seenFin || f.seenRst,
        'reset' || 'rst' => f.seenRst,
        'syn' => f.seenSyn,
        'oneway' => f.upPackets == 0 || f.downPackets == 0,
        'large' => f.totalBytes > 1024 * 1024,
        'named' => f.name != null,
        _ => false,
      };
      if (hit) return true;
    }
    return false;
  }

  static final QuerySchema<NetFlow> schema = QuerySchema<NetFlow>(
    textTest: (f, t) => t.matchAnyText([f.name, f.clientIp, f.serverIp, f.appName, f.appPackage, f.protocolName, f.info]),
    fields: [
      QueryField(['proto', 'protocol'], _proto,
          description: 'tcp/udp/icmp/dns/tls/http/quic/ipv4/ipv6', examples: ['proto:dns', 'proto:tcp', '-proto:quic']),
      QueryField(['host', 'name', 'domain'], (f, t) => t.matchText(f.name),
          description: '域名（SNI / Host / DNS）', examples: ['host:*.google.com']),
      QueryField(['ip'], (f, t) => t.matchAnyText([f.clientIp, f.serverIp]), description: '任一端 IP', examples: ['ip:8.8.8.8']),
      QueryField(['src'], (f, t) => t.matchText(f.clientIp), description: '发起方 IP'),
      QueryField(['dst'], (f, t) => t.matchText(f.serverIp), description: '目标 IP', examples: ['dst:/^10\\./']),
      QueryField(['port'], (f, t) => t.matchNumber(f.serverPort) || t.matchNumber(f.clientPort),
          description: '任一端端口', examples: ['port:443', 'port:1-1024']),
      QueryField(['dport'], (f, t) => t.matchNumber(f.serverPort), description: '目标端口', examples: ['dport:53']),
      QueryField(['sport'], (f, t) => t.matchNumber(f.clientPort), description: '源端口'),
      QueryField(['app', 'process'], (f, t) => t.matchAnyText([f.appName, f.appPackage, f.uid?.toString()]),
          description: '来源应用名 / 包名 / uid', examples: ['app:chrome']),
      QueryField(['bytes', 'size'], (f, t) => t.matchNumber(f.totalBytes), description: '总字节，单位 k/m', examples: ['bytes>1m']),
      QueryField(['packets', 'pkts'], (f, t) => t.matchNumber(f.totalPackets), description: '包数', examples: ['packets>100']),
      QueryField(['time', 'duration'], (f, t) => t.matchNumber(f.duration.inMilliseconds, parser: QueryTerm.parseDurationMs),
          description: '持续时间', examples: ['time>10s']),
      QueryField(['info'], (f, t) => f.packets.any((p) => t.matchText(p.info)), description: '任一包的摘要信息'),
      QueryField(['is', 'state'], _is,
          description: 'open/closed/reset/syn/oneway/large/named', examples: ['is:reset', 'is:oneway']),
    ],
  );

  static const List<String> quickFilters = [
    'proto:dns',
    'proto:tls',
    'proto:http',
    'proto:udp',
    '-proto:dns',
    'is:reset',
    'bytes>100k',
    'port:443',
  ];
}
