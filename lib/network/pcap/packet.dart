import 'dart:convert';
import 'dart:typed_data';

import 'package:proxypin/network/pcap/pcap.dart';

enum TransportProtocol { tcp, udp, icmp, icmpv6, other }

/// 解码后的数据包
class Packet {
  /// 在抓包会话中的序号（从 1 开始）
  final int index;
  final PcapRecord record;

  int ipVersion = 0;
  String? src;
  String? dst;
  int? srcPort;
  int? dstPort;
  TransportProtocol protocol = TransportProtocol.other;

  /// IP 协议号 / EtherType（非 IP 时）
  int protocolNumber = 0;

  /// TCP 标志位
  int tcpFlags = 0;
  int? tcpSeq;
  int? tcpAck;
  int ttl = 0;

  /// 传输层负载在 [record.data] 中的偏移与长度（截断后）
  int payloadOffset = 0;
  int payloadLength = 0;

  /// 链路层描述（非 IP 帧，例如 ARP）
  String? linkInfo;

  /// 应用层摘要（DNS 查询、TLS SNI、HTTP 请求行等）
  String? info;

  /// 应用层协议名（DNS、TLS、HTTP、QUIC...）
  String? appProtocol;

  Packet(this.index, this.record);

  DateTime get time => record.time;

  int get length => record.originalLength;

  Uint8List get payload => Uint8List.sublistView(record.data, payloadOffset, payloadOffset + payloadLength);

  bool get isIp => ipVersion != 0 && src != null && dst != null;

  String get protocolName {
    if (appProtocol != null) return appProtocol!;
    return switch (protocol) {
      TransportProtocol.tcp => 'TCP',
      TransportProtocol.udp => 'UDP',
      TransportProtocol.icmp => 'ICMP',
      TransportProtocol.icmpv6 => 'ICMPv6',
      TransportProtocol.other => linkInfo ?? (isIp ? 'IP($protocolNumber)' : 'ETH(0x${protocolNumber.toRadixString(16)})'),
    };
  }

  String get tcpFlagsText {
    if (protocol != TransportProtocol.tcp) return '';
    const names = ['FIN', 'SYN', 'RST', 'PSH', 'ACK', 'URG', 'ECE', 'CWR'];
    final out = <String>[];
    for (var i = 0; i < names.length; i++) {
      if (tcpFlags & (1 << i) != 0) out.add(names[i]);
    }
    return out.join(',');
  }

  static String endpoint(String? host, int? port) {
    if (host == null) return '-';
    if (port == null) return host;
    return host.contains(':') ? '[$host]:$port' : '$host:$port';
  }

  String get srcEndpoint => endpoint(src, srcPort);

  String get dstEndpoint => endpoint(dst, dstPort);

  /// 摘要行（类似 Wireshark Info 列）
  String get summary {
    if (info != null) return info!;
    if (protocol == TransportProtocol.tcp) {
      return '[$tcpFlagsText] len=$payloadLength';
    }
    if (protocol == TransportProtocol.udp) return 'len=$payloadLength';
    return linkInfo ?? '';
  }
}

/// 数据包解码器
class PacketDecoder {
  final int linkType;

  PacketDecoder(this.linkType);

  Packet decode(int index, PcapRecord record) {
    final p = Packet(index, record);
    final data = record.data;
    try {
      final (etherType, offset) = _linkLayer(data);
      p.protocolNumber = etherType;
      if (etherType == 0x0800 || (etherType == -1 && data.length > offset && data[offset] >> 4 == 4)) {
        _ipv4(p, data, offset);
      } else if (etherType == 0x86DD || (etherType == -1 && data.length > offset && data[offset] >> 4 == 6)) {
        _ipv6(p, data, offset);
      } else if (etherType == 0x0806) {
        p.linkInfo = 'ARP';
      }
      if (p.isIp) AppLayerDecoder.decode(p);
    } catch (_) {
      // 截断或畸形包：保留已解析的部分
    }
    return p;
  }

  /// 返回 (EtherType, 网络层偏移)；EtherType 为 -1 表示按 IP 版本号判断
  (int, int) _linkLayer(Uint8List d) {
    switch (linkType) {
      case LinkType.ethernet:
        var type = _u16(d, 12);
        var off = 14;
        while (type == 0x8100 || type == 0x88A8) {
          type = _u16(d, off + 2);
          off += 4;
        }
        return (type, off);
      case LinkType.linuxSll:
        return (_u16(d, 14), 16);
      case LinkType.linuxSll2:
        return (_u16(d, 0), 20);
      case LinkType.nullLoopback:
        return (-1, 4);
      case LinkType.ipv4:
        return (0x0800, 0);
      case LinkType.ipv6:
        return (0x86DD, 0);
      case LinkType.raw:
      case LinkType.rawAlt:
      default:
        return (-1, 0);
    }
  }

  void _ipv4(Packet p, Uint8List d, int off) {
    final ihl = (d[off] & 0x0F) * 4;
    final totalLen = _u16(d, off + 2);
    p.ipVersion = 4;
    p.ttl = d[off + 8];
    p.protocolNumber = d[off + 9];
    p.src = '${d[off + 12]}.${d[off + 13]}.${d[off + 14]}.${d[off + 15]}';
    p.dst = '${d[off + 16]}.${d[off + 17]}.${d[off + 18]}.${d[off + 19]}';
    final fragOffset = _u16(d, off + 6) & 0x1FFF;
    final end = (off + totalLen).clamp(0, d.length);
    if (fragOffset != 0) {
      p.info = 'IP fragment';
      return;
    }
    _transport(p, d, off + ihl, end, p.protocolNumber);
  }

  void _ipv6(Packet p, Uint8List d, int off) {
    p.ipVersion = 6;
    final payloadLen = _u16(d, off + 4);
    var next = d[off + 6];
    p.ttl = d[off + 7];
    p.src = _ipv6Text(d, off + 8);
    p.dst = _ipv6Text(d, off + 24);
    var cur = off + 40;
    final end = (cur + payloadLen).clamp(0, d.length);
    // 跳过扩展头：Hop-by-Hop(0) Routing(43) Fragment(44) DestOpts(60)
    while ((next == 0 || next == 43 || next == 60 || next == 44) && cur + 8 <= end) {
      final hdrLen = next == 44 ? 8 : (d[cur + 1] + 1) * 8;
      next = d[cur];
      cur += hdrLen;
    }
    p.protocolNumber = next;
    _transport(p, d, cur, end, next);
  }

  void _transport(Packet p, Uint8List d, int off, int end, int proto) {
    switch (proto) {
      case 6:
        p.protocol = TransportProtocol.tcp;
        p.srcPort = _u16(d, off);
        p.dstPort = _u16(d, off + 2);
        p.tcpSeq = _u32(d, off + 4);
        p.tcpAck = _u32(d, off + 8);
        final dataOff = (d[off + 12] >> 4) * 4;
        p.tcpFlags = d[off + 13];
        _setPayload(p, off + dataOff, end, d.length);
      case 17:
        p.protocol = TransportProtocol.udp;
        p.srcPort = _u16(d, off);
        p.dstPort = _u16(d, off + 2);
        _setPayload(p, off + 8, end, d.length);
      case 1:
        p.protocol = TransportProtocol.icmp;
        p.info = _icmpInfo(d[off], d[off + 1], false);
        _setPayload(p, off, end, d.length);
      case 58:
        p.protocol = TransportProtocol.icmpv6;
        p.info = _icmpInfo(d[off], d[off + 1], true);
        _setPayload(p, off, end, d.length);
      default:
        _setPayload(p, off, end, d.length);
    }
  }

  static void _setPayload(Packet p, int start, int end, int dataLength) {
    final s = start.clamp(0, dataLength);
    final e = end.clamp(s, dataLength);
    p.payloadOffset = s;
    p.payloadLength = e - s;
  }

  static String _icmpInfo(int type, int code, bool v6) {
    if (!v6) {
      return switch (type) {
        0 => 'Echo reply',
        8 => 'Echo request',
        3 => 'Destination unreachable (code $code)',
        11 => 'Time exceeded',
        _ => 'ICMP type $type code $code',
      };
    }
    return switch (type) {
      128 => 'Echo request',
      129 => 'Echo reply',
      1 => 'Destination unreachable (code $code)',
      133 => 'Router solicitation',
      134 => 'Router advertisement',
      135 => 'Neighbor solicitation',
      136 => 'Neighbor advertisement',
      _ => 'ICMPv6 type $type code $code',
    };
  }

  static String _ipv6Text(Uint8List d, int off) {
    final groups = List<int>.generate(8, (i) => _u16(d, off + i * 2));
    // 压缩最长的连续 0 段
    var bestStart = -1, bestLen = 0;
    for (var i = 0; i < 8;) {
      if (groups[i] == 0) {
        var j = i;
        while (j < 8 && groups[j] == 0) {
          j++;
        }
        if (j - i > bestLen && j - i > 1) {
          bestStart = i;
          bestLen = j - i;
        }
        i = j;
      } else {
        i++;
      }
    }
    String hex(int g) => g.toRadixString(16);
    if (bestStart < 0) return groups.map(hex).join(':');
    final left = groups.sublist(0, bestStart).map(hex).join(':');
    final right = groups.sublist(bestStart + bestLen).map(hex).join(':');
    return '$left::$right';
  }

  static int _u16(Uint8List d, int o) => (d[o] << 8) | d[o + 1];

  static int _u32(Uint8List d, int o) => (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];
}

/// 应用层识别：DNS、TLS ClientHello(SNI)、HTTP、QUIC
class AppLayerDecoder {
  static const _httpMethods = ['GET ', 'POST ', 'PUT ', 'DELETE ', 'HEAD ', 'OPTIONS ', 'PATCH ', 'CONNECT ', 'TRACE '];

  static void decode(Packet p) {
    final payload = p.payload;
    final sp = p.srcPort, dp = p.dstPort;
    if (p.protocol == TransportProtocol.udp) {
      if (sp == 53 || dp == 53 || sp == 5353 || dp == 5353) {
        p.appProtocol = sp == 5353 || dp == 5353 ? 'mDNS' : 'DNS';
        p.info = Dns.describe(payload);
      } else if ((sp == 443 || dp == 443) && payload.isNotEmpty && payload[0] & 0x80 != 0) {
        p.appProtocol = 'QUIC';
        p.info = 'QUIC long header';
      } else if (sp == 67 || dp == 67 || sp == 68 || dp == 68) {
        p.appProtocol = 'DHCP';
      } else if (sp == 123 || dp == 123) {
        p.appProtocol = 'NTP';
      }
      return;
    }
    if (p.protocol != TransportProtocol.tcp || payload.isEmpty) return;

    if (payload.length > 5 && payload[0] == 0x16 && payload[1] == 0x03) {
      final hs = payload[5];
      p.appProtocol = 'TLS';
      if (hs == 0x01) {
        final sni = Tls.sni(payload);
        p.info = sni == null ? 'Client Hello' : 'Client Hello, SNI=$sni';
      } else if (hs == 0x02) {
        p.info = 'Server Hello';
      } else {
        p.info = 'Handshake';
      }
      return;
    }
    if (payload.length > 5 && payload[0] == 0x17 && payload[1] == 0x03) {
      p.appProtocol = 'TLS';
      p.info = 'Application Data len=${p.payloadLength}';
      return;
    }

    final head = latin1.decode(payload.sublist(0, payload.length.clamp(0, 2048)), allowInvalid: true);
    if (head.startsWith('HTTP/1.')) {
      p.appProtocol = 'HTTP';
      p.info = head.split('\r\n').first;
      return;
    }
    if (_httpMethods.any(head.startsWith)) {
      p.appProtocol = 'HTTP';
      final lines = head.split('\r\n');
      final host = lines.firstWhere((l) => l.toLowerCase().startsWith('host:'), orElse: () => '');
      p.info = host.isEmpty ? lines.first : '${lines.first}  (${host.substring(5).trim()})';
    }
  }
}

class Tls {
  /// 从 TLS ClientHello 提取 SNI
  static String? sni(Uint8List d) {
    try {
      var o = 5; // record header
      if (d[o] != 0x01) return null;
      o += 4; // handshake header
      o += 2 + 32; // version + random
      o += 1 + d[o]; // session id
      o += 2 + ((d[o] << 8) | d[o + 1]); // cipher suites
      o += 1 + d[o]; // compression
      final extEnd = o + 2 + ((d[o] << 8) | d[o + 1]);
      o += 2;
      while (o + 4 <= extEnd && o + 4 <= d.length) {
        final type = (d[o] << 8) | d[o + 1];
        final len = (d[o + 2] << 8) | d[o + 3];
        o += 4;
        if (type == 0) {
          // server_name list
          final nameLen = (d[o + 3] << 8) | d[o + 4];
          return ascii.decode(d.sublist(o + 5, o + 5 + nameLen), allowInvalid: true);
        }
        o += len;
      }
    } catch (_) {}
    return null;
  }
}

class Dns {
  static const _types = {
    1: 'A',
    2: 'NS',
    5: 'CNAME',
    6: 'SOA',
    12: 'PTR',
    15: 'MX',
    16: 'TXT',
    28: 'AAAA',
    33: 'SRV',
    64: 'SVCB',
    65: 'HTTPS',
  };

  static String typeName(int t) => _types[t] ?? 'TYPE$t';

  /// DNS 报文摘要，例如 `Query A www.example.com` / `Response A www.example.com -> 1.2.3.4`
  static String? describe(Uint8List d) {
    try {
      if (d.length < 12) return null;
      final flags = (d[2] << 8) | d[3];
      final isResponse = flags & 0x8000 != 0;
      final rcode = flags & 0x0F;
      final qd = (d[4] << 8) | d[5];
      final an = (d[6] << 8) | d[7];
      var o = 12;
      String? qname;
      var qtype = 0;
      for (var i = 0; i < qd; i++) {
        final (name, next) = _readName(d, o);
        qname ??= name;
        qtype = (d[next] << 8) | d[next + 1];
        o = next + 4;
      }
      if (!isResponse) return 'Query ${typeName(qtype)} ${qname ?? ''}';

      final answers = <String>[];
      for (var i = 0; i < an && o < d.length; i++) {
        final (_, next) = _readName(d, o);
        final type = (d[next] << 8) | d[next + 1];
        final rdLen = (d[next + 8] << 8) | d[next + 9];
        final rd = next + 10;
        if (type == 1 && rdLen == 4) {
          answers.add('${d[rd]}.${d[rd + 1]}.${d[rd + 2]}.${d[rd + 3]}');
        } else if (type == 28 && rdLen == 16) {
          answers.add(PacketDecoder._ipv6Text(d, rd));
        } else if (type == 5) {
          answers.add('CNAME ${_readName(d, rd).$1}');
        }
        o = rd + rdLen;
      }
      final err = rcode == 0 ? '' : ' (rcode $rcode)';
      return 'Response ${typeName(qtype)} ${qname ?? ''}$err${answers.isEmpty ? '' : ' -> ${answers.join(', ')}'}';
    } catch (_) {
      return null;
    }
  }

  /// DNS 响应：返回 (查询域名, 解析出的 IP 列表)
  static (String, List<String>)? answers(Uint8List d) {
    try {
      if (d.length < 12 || (((d[2] << 8) | d[3]) & 0x8000) == 0) return null;
      final qd = (d[4] << 8) | d[5];
      final an = (d[6] << 8) | d[7];
      var o = 12;
      String? qname;
      for (var i = 0; i < qd; i++) {
        final (name, next) = _readName(d, o);
        qname ??= name;
        o = next + 4;
      }
      if (qname == null) return null;
      final ips = <String>[];
      for (var i = 0; i < an && o < d.length; i++) {
        final (_, next) = _readName(d, o);
        final type = (d[next] << 8) | d[next + 1];
        final rdLen = (d[next + 8] << 8) | d[next + 9];
        final rd = next + 10;
        if (type == 1 && rdLen == 4) ips.add('${d[rd]}.${d[rd + 1]}.${d[rd + 2]}.${d[rd + 3]}');
        if (type == 28 && rdLen == 16) ips.add(PacketDecoder._ipv6Text(d, rd));
        o = rd + rdLen;
      }
      return (qname, ips);
    } catch (_) {
      return null;
    }
  }

  /// DNS 查询的域名
  static String? queryName(Uint8List d) {
    try {
      if (d.length < 12 || ((d[4] << 8) | d[5]) == 0) return null;
      return _readName(d, 12).$1;
    } catch (_) {
      return null;
    }
  }

  static (String, int) _readName(Uint8List d, int offset) {
    final labels = <String>[];
    var o = offset;
    int? after;
    var jumps = 0;
    while (true) {
      final len = d[o];
      if (len == 0) {
        o += 1;
        break;
      }
      if (len & 0xC0 == 0xC0) {
        after ??= o + 2;
        o = ((len & 0x3F) << 8) | d[o + 1];
        if (++jumps > 20) break;
        continue;
      }
      labels.add(ascii.decode(d.sublist(o + 1, o + 1 + len), allowInvalid: true));
      o += 1 + len;
    }
    return (labels.join('.'), after ?? o);
  }
}
