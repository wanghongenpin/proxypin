import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:path_provider/path_provider.dart';
import 'package:proxypin/native/raw_capture.dart';
import 'package:proxypin/network/pcap/capture_session.dart';
import 'package:proxypin/network/pcap/packet.dart';
import 'package:proxypin/ui/component/query_syntax_help.dart';
import 'package:proxypin/utils/query/query.dart';
import 'package:share_plus/share_plus.dart';

String formatBytes(num bytes) {
  if (bytes < 1024) return '${bytes.toInt()}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}K';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)}M';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)}G';
}

String formatTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
}

Color protocolColor(String proto, ColorScheme scheme) {
  return switch (proto) {
    'DNS' || 'mDNS' => const Color(0xFF54A396),
    'TLS' => const Color(0xFF7185D6),
    'HTTP' => const Color(0xFF57916F),
    'QUIC' => const Color(0xFF8A6DB8),
    'UDP' => const Color(0xFFCE8359),
    'ICMP' || 'ICMPv6' => const Color(0xFFAF6C94),
    _ => scheme.onSurfaceVariant,
  };
}

/// 原始抓包（Root + tcpdump）
class RawCapturePage extends StatefulWidget {
  const RawCapturePage({super.key});

  @override
  State<RawCapturePage> createState() => _RawCapturePageState();
}

class _RawCapturePageState extends State<RawCapturePage> {
  final capture = RawCapture.instance;
  final TextEditingController _queryController = TextEditingController();
  Query<NetFlow>? _query;
  bool _packetView = false;
  bool _starting = false;
  bool _autoScroll = true;
  final ScrollController _scroll = ScrollController();

  // 抓包参数
  String _iface = 'any';
  String _bpf = '';
  int _snapLen = 0;

  bool get isCN => Localizations.localeOf(context).languageCode == 'zh';

  String t(String zh, String en) => isCN ? zh : en;

  @override
  void initState() {
    super.initState();
    capture.addListener(_onUpdate);
    capture.refresh();
  }

  @override
  void dispose() {
    capture.removeListener(_onUpdate);
    _queryController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (!mounted) return;
    setState(() {});
    if (_autoScroll && capture.running && _scroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  void _onQueryChanged(String text) {
    setState(() {
      _query = text.trim().isEmpty ? null : FlowQuery.schema.parse(text);
    });
  }

  List<NetFlow> get _flows {
    final q = _query;
    final all = capture.session.flows;
    return q == null ? all : all.where(q.matches).toList();
  }

  List<Packet> get _packets {
    final q = _query;
    if (q == null) return capture.session.packets;
    final session = capture.session;
    final flows = _flows.toSet();
    return session.packets.where((p) {
      final f = session.flowOf(p);
      return f != null && flows.contains(f);
    }).toList();
  }

  Future<void> _toggle() async {
    if (capture.running) {
      await capture.stop();
      return;
    }
    final status = await capture.status();
    if (!mounted) return;
    if (!status.bundled) {
      FlutterToastr.show(t('当前设备架构(${status.abi})未内置 tcpdump', 'tcpdump not bundled for ${status.abi}'), context,
          duration: 3);
      return;
    }
    setState(() => _starting = true);
    final ok = await capture.start(iface: _iface, filter: _bpf, snapLen: _snapLen);
    if (!mounted) return;
    setState(() => _starting = false);
    if (!ok) {
      showDialog(
          context: context,
          builder: (_) => AlertDialog(
                title: Text(t('启动失败', 'Failed to start')),
                content: SelectableText(capture.lastError ?? ''),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
              ));
    }
  }

  Future<void> _settings() async {
    final interfaces = await capture.interfaces();
    if (!mounted) return;
    final bpf = TextEditingController(text: _bpf);
    var iface = interfaces.contains(_iface) ? _iface : 'any';
    var snap = _snapLen;
    await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialog) => AlertDialog(
                  title: Text(t('抓包参数', 'Capture options'), style: const TextStyle(fontSize: 16)),
                  scrollable: true,
                  content: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(t('网卡', 'Interface')),
                    DropdownButton<String>(
                        isExpanded: true,
                        value: iface,
                        items: interfaces.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (v) => setDialog(() => iface = v ?? 'any')),
                    const SizedBox(height: 10),
                    Text(t('BPF 过滤表达式（抓包时过滤，减少数据量）', 'BPF filter (applied by tcpdump)')),
                    const SizedBox(height: 6),
                    TextField(
                        controller: bpf,
                        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                        decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            hintText: 'tcp port 443 or udp port 53',
                            hintStyle: TextStyle(fontSize: 12))),
                    Wrap(spacing: 6, children: [
                      for (final ex in ['udp port 53', 'tcp', 'not port 443', 'host 1.1.1.1', 'icmp or icmp6'])
                        ActionChip(
                            label: Text(ex, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => bpf.text = ex),
                    ]),
                    const SizedBox(height: 10),
                    Text(t('每包截取长度（0 = 完整）', 'Snap length (0 = full)')),
                    DropdownButton<int>(
                        isExpanded: true,
                        value: snap,
                        items: const [0, 96, 256, 1500]
                            .map((e) => DropdownMenuItem(value: e, child: Text(e == 0 ? 'full' : '$e bytes')))
                            .toList(),
                        onChanged: (v) => setDialog(() => snap = v ?? 0)),
                  ]),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('取消', 'Cancel'))),
                    TextButton(
                        onPressed: () {
                          setState(() {
                            _iface = iface;
                            _bpf = bpf.text.trim();
                            _snapLen = snap;
                          });
                          Navigator.pop(ctx);
                        },
                        child: Text(t('确定', 'OK'))),
                  ],
                )));
  }

  Future<void> _export({required bool filtered, required bool share, bool pcapng = true}) async {
    if (capture.running && !filtered) {
      FlutterToastr.show(t('请先停止抓包再导出完整文件', 'Stop capture before exporting the full file'), context);
      return;
    }
    File? file;
    final dir = await getTemporaryDirectory();
    if (filtered) {
      final packets = _packetView ? _packets : _flows.expand((f) => f.packets).toList();
      if (packets.isEmpty) {
        if (mounted) FlutterToastr.show(t('没有可导出的数据', 'Nothing to export'), context);
        return;
      }
      file = await capture.exportPackets(packets, dir.path, pcapng: pcapng);
    } else {
      file = await capture.exportFull(dir.path, pcapng: pcapng);
    }
    if (file == null || !await file.exists()) {
      if (mounted) FlutterToastr.show(t('没有抓包文件', 'No capture file'), context);
      return;
    }
    final name = file.uri.pathSegments.last;
    if (share) {
      await SharePlus.instance.share(ShareParams(files: [
        XFile(file.path, mimeType: pcapng ? 'application/x-pcapng' : 'application/vnd.tcpdump.pcap')
      ]));
      return;
    }
    final saved = await FilePicker.saveFile(fileName: name, bytes: await file.readAsBytes());
    if (mounted && saved != null) FlutterToastr.show(t('已保存', 'Saved'), context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = capture.session;
    final flows = _packetView ? const <NetFlow>[] : _flows;
    final packets = _packetView ? _packets : const <Packet>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(t('原始抓包', 'Raw Capture'), style: const TextStyle(fontSize: 16)),
        centerTitle: true,
        actions: [
          IconButton(
              tooltip: t('抓包参数', 'Options'),
              icon: const Icon(Icons.settings_ethernet, size: 20),
              onPressed: capture.running ? null : _settings),
          PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (v) {
                switch (v) {
                  case 'share':
                    _export(filtered: false, share: true);
                  case 'save':
                    _export(filtered: false, share: false);
                  case 'shareFiltered':
                    _export(filtered: true, share: true);
                  case 'saveFiltered':
                    _export(filtered: true, share: false);
                  case 'sharePcap':
                    _export(filtered: false, share: true, pcapng: false);
                  case 'clear':
                    capture.clear();
                }
              },
              itemBuilder: (_) => [
                    PopupMenuItem(value: 'share', child: Text(t('分享完整 pcapng（含 TLS 密钥）', 'Share full pcapng (TLS keys)'))),
                    PopupMenuItem(value: 'save', child: Text(t('保存完整 pcapng（含 TLS 密钥）', 'Save full pcapng (TLS keys)'))),
                    PopupMenuItem(value: 'shareFiltered', child: Text(t('分享筛选结果 pcapng', 'Share filtered pcapng'))),
                    PopupMenuItem(value: 'saveFiltered', child: Text(t('保存筛选结果 pcapng', 'Save filtered pcapng'))),
                    PopupMenuItem(value: 'sharePcap', child: Text(t('分享原始 pcap（不含密钥）', 'Share raw pcap (no keys)'))),
                    PopupMenuItem(value: 'clear', child: Text(t('清空列表', 'Clear list'))),
                  ]),
        ],
      ),
      floatingActionButton: FloatingActionButton(
          onPressed: _starting ? null : _toggle,
          child: _starting
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(capture.running ? Icons.stop : Icons.play_arrow)),
      body: Column(children: [
        // 状态栏
        Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Wrap(spacing: 14, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 9, color: capture.running ? Colors.green : theme.disabledColor),
                const SizedBox(width: 5),
                Text(capture.running ? t('抓包中', 'Capturing') : t('已停止', 'Stopped'), style: const TextStyle(fontSize: 12)),
              ]),
              Text('${t('包', 'pkts')} ${s.totalPackets}', style: const TextStyle(fontSize: 12)),
              Text('${t('流', 'flows')} ${s.flows.length}', style: const TextStyle(fontSize: 12)),
              Text(formatBytes(s.totalBytes), style: const TextStyle(fontSize: 12)),
              Tooltip(
                  message: t('ProxyPin 上游 TLS 连接的会话密钥，导出 pcapng 时嵌入，Wireshark 可直接解密',
                      'Session keys of ProxyPin upstream TLS connections, embedded in exported pcapng'),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.key, size: 12, color: capture.tlsConnectionCount > 0 ? Colors.amber.shade700 : theme.disabledColor),
                    const SizedBox(width: 3),
                    Text('TLS ${capture.tlsConnectionCount}', style: const TextStyle(fontSize: 12)),
                  ])),
              Text('$_iface${_bpf.isEmpty ? '' : ' · $_bpf'}',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
              if (s.memoryFull)
                Text(t('内存缓存已满，后续包仅写入文件', 'Memory full, packets only saved to file'),
                    style: const TextStyle(fontSize: 12, color: Colors.orange)),
            ])),
        // 搜索
        Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
            child: Row(children: [
              Expanded(
                  child: SizedBox(
                      height: 38,
                      child: TextField(
                          controller: _queryController,
                          onChanged: _onQueryChanged,
                          style: const TextStyle(fontSize: 13),
                          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                          decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              prefixIcon: const Icon(Icons.search, size: 18),
                              suffixIcon: IconButton(
                                  icon: const Icon(Icons.tune, size: 18),
                                  onPressed: () => QuerySyntaxHelp.show(context,
                                      schema: FlowQuery.schema,
                                      controller: _queryController,
                                      onChanged: _onQueryChanged,
                                      quickFilters: FlowQuery.quickFilters)),
                              hintText: 'proto:dns  host:*.qq.com  app:chrome',
                              hintStyle: const TextStyle(fontSize: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))))),
              const SizedBox(width: 6),
              SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [
                    ButtonSegment(value: false, label: Text(t('流', 'Flows'), style: const TextStyle(fontSize: 12))),
                    ButtonSegment(value: true, label: Text(t('包', 'Pkts'), style: const TextStyle(fontSize: 12))),
                  ],
                  selected: {_packetView},
                  onSelectionChanged: (v) => setState(() => _packetView = v.first)),
            ])),
        Expanded(
            child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is UserScrollNotification) {
                    _autoScroll = n.metrics.pixels >= n.metrics.maxScrollExtent - 40;
                  }
                  return false;
                },
                child: (_packetView ? packets.isEmpty : flows.isEmpty)
                    ? _empty(theme)
                    : ListView.builder(
                        controller: _scroll,
                        itemCount: _packetView ? packets.length : flows.length,
                        itemExtent: _packetView ? 52 : 64,
                        itemBuilder: (context, i) =>
                            _packetView ? _packetTile(packets[i], theme) : _flowTile(flows[i], theme)))),
      ]),
    );
  }

  Widget _empty(ThemeData theme) {
    return Center(
        child: Padding(
            padding: const EdgeInsets.all(30),
            child: Text(
                capture.running
                    ? t('等待数据包…', 'Waiting for packets…')
                    : t('点击右下角开始。使用 Root 运行内置 tcpdump 抓取所有网卡流量（TCP/UDP/ICMP/DNS…），'
                        '可导出 pcap 用 Wireshark 分析。HTTPS 内容为密文，仅可见域名(SNI)等元数据。',
                        'Tap start. Runs the bundled tcpdump as root to capture all traffic (TCP/UDP/ICMP/DNS…). '
                        'Export pcap for Wireshark. HTTPS payload is encrypted; only metadata such as SNI is visible.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13))));
  }

  Widget _protoChip(String proto, ThemeData theme) {
    final color = protocolColor(proto, theme.colorScheme);
    return Container(
        width: 50,
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
        child: Text(proto,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis));
  }

  Widget _flowTile(NetFlow f, ThemeData theme) {
    final sub = TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant);
    return InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FlowDetailPage(flow: f))),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              _protoChip(f.protocolName, theme),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(f.name ?? f.server,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
                const SizedBox(height: 2),
                Text('${f.client} → ${f.server}', maxLines: 1, overflow: TextOverflow.ellipsis, style: sub),
                const SizedBox(height: 1),
                Text(
                    [
                      if (f.appName != null) f.appName!,
                      '${f.totalPackets} pkts',
                      '↑${formatBytes(f.upBytes)} ↓${formatBytes(f.downBytes)}',
                      if (f.state.isNotEmpty) f.state,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sub),
              ])),
              Text(formatTime(f.firstTime), style: sub),
            ])));
  }

  Widget _packetTile(Packet p, ThemeData theme) {
    final sub = TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant);
    return InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PacketDetailPage(packet: p))),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              SizedBox(width: 44, child: Text('${p.index}', style: sub)),
              _protoChip(p.protocolName, theme),
              const SizedBox(width: 8),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${p.srcEndpoint} → ${p.dstEndpoint}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                Text(p.summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: sub),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(formatTime(p.time), style: sub),
                Text('${p.length}B', style: sub),
              ]),
            ])));
  }
}

/// 单条流详情
class FlowDetailPage extends StatelessWidget {
  final NetFlow flow;

  const FlowDetailPage({super.key, required this.flow});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCN = Localizations.localeOf(context).languageCode == 'zh';
    String t(String zh, String en) => isCN ? zh : en;
    final sub = TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant);

    final rows = <(String, String)>[
      (t('协议', 'Protocol'), flow.protocolName),
      if (flow.name != null) (t('域名', 'Host'), flow.name!),
      (t('客户端', 'Client'), flow.client),
      (t('服务端', 'Server'), flow.server),
      if (flow.appName != null || flow.uid != null)
        (t('应用', 'App'), [flow.appName, flow.appPackage, if (flow.uid != null) 'uid ${flow.uid}'].whereType<String>().join('  ')),
      (t('开始', 'Start'), formatTime(flow.firstTime)),
      (t('持续', 'Duration'), '${flow.duration.inMilliseconds} ms'),
      (t('上行', 'Up'), '${flow.upPackets} pkts / ${formatBytes(flow.upBytes)}'),
      (t('下行', 'Down'), '${flow.downPackets} pkts / ${formatBytes(flow.downBytes)}'),
      if (flow.state.isNotEmpty) (t('状态', 'State'), flow.state),
    ];

    return Scaffold(
        appBar: AppBar(
            title: Text(flow.name ?? flow.server, style: const TextStyle(fontSize: 15)),
            actions: [
              IconButton(
                  tooltip: t('分享此流 pcapng（含 TLS 密钥）', 'Share flow pcapng (TLS keys)'),
                  icon: const Icon(Icons.share, size: 20),
                  onPressed: () async {
                    final dir = await getTemporaryDirectory();
                    final f = await RawCapture.instance.exportPackets(flow.packets, dir.path);
                    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
                  }),
            ]),
        body: ListView(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Column(children: [
                for (final r in rows)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 72, child: Text(r.$1, style: sub)),
                        Expanded(child: SelectableText(r.$2, style: const TextStyle(fontSize: 13))),
                      ])),
              ])),
          const Divider(height: 1),
          for (final p in flow.packets)
            ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(
                    p.src == flow.clientIp && p.srcPort == flow.clientPort ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 16,
                    color: p.src == flow.clientIp && p.srcPort == flow.clientPort ? Colors.blue : Colors.green),
                title: Text(p.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                subtitle: Text('#${p.index}  ${formatTime(p.time)}  ${p.length}B', style: sub),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PacketDetailPage(packet: p)))),
        ]));
  }
}

/// 单包详情：解码字段 + 负载文本 + 十六进制
class PacketDetailPage extends StatelessWidget {
  final Packet packet;

  const PacketDetailPage({super.key, required this.packet});

  static String hexDump(List<int> data, {int max = 64 * 1024}) {
    final sb = StringBuffer();
    final n = data.length.clamp(0, max);
    for (var i = 0; i < n; i += 16) {
      sb.write(i.toRadixString(16).padLeft(6, '0'));
      sb.write('  ');
      final ascii = StringBuffer();
      for (var j = 0; j < 16; j++) {
        if (i + j < n) {
          final b = data[i + j];
          sb.write(b.toRadixString(16).padLeft(2, '0'));
          ascii.write(b >= 0x20 && b < 0x7f ? String.fromCharCode(b) : '.');
        } else {
          sb.write('  ');
        }
        sb.write(j == 7 ? '  ' : ' ');
      }
      sb.write(' ');
      sb.writeln(ascii);
    }
    if (data.length > max) sb.writeln('... (${data.length - max} more bytes)');
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    final p = packet;
    final theme = Theme.of(context);
    final isCN = Localizations.localeOf(context).languageCode == 'zh';
    String t(String zh, String en) => isCN ? zh : en;
    final sub = TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant);
    const mono = TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.35);

    final rows = <(String, String)>[
      (t('序号', 'No.'), '${p.index}'),
      (t('时间', 'Time'), p.time.toIso8601String()),
      (t('长度', 'Length'), '${p.length} B (${t('已截取', 'captured')} ${p.record.data.length} B)'),
      (t('协议', 'Protocol'), p.protocolName),
      if (p.isIp) ('IP', 'IPv${p.ipVersion}  TTL ${p.ttl}'),
      (t('源', 'Source'), p.srcEndpoint),
      (t('目标', 'Destination'), p.dstEndpoint),
      if (p.protocol == TransportProtocol.tcp) ('TCP', '[${p.tcpFlagsText}] seq=${p.tcpSeq} ack=${p.tcpAck}'),
      (t('负载', 'Payload'), '${p.payloadLength} B'),
      if (p.info != null) (t('信息', 'Info'), p.info!),
    ];

    final payload = p.payload;
    final printable = payload.where((b) => b == 9 || b == 10 || b == 13 || (b >= 0x20 && b < 0x7f)).length;
    final isText = payload.isNotEmpty && printable / payload.length > 0.9;

    return Scaffold(
        appBar: AppBar(
            title: Text('#${p.index} ${p.protocolName}', style: const TextStyle(fontSize: 15)),
            actions: [
              IconButton(
                  tooltip: t('复制十六进制', 'Copy hex'),
                  icon: const Icon(Icons.copy, size: 19),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: hexDump(p.record.data)));
                    FlutterToastr.show(t('已复制', 'Copied'), context);
                  }),
            ]),
        body: ListView(padding: const EdgeInsets.all(14), children: [
          for (final r in rows)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 72, child: Text(r.$1, style: sub)),
                  Expanded(child: SelectableText(r.$2, style: const TextStyle(fontSize: 13))),
                ])),
          if (isText) ...[
            const SizedBox(height: 12),
            Text(t('负载文本', 'Payload text'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SelectableText(String.fromCharCodes(payload.take(16 * 1024)), style: mono),
          ],
          const SizedBox(height: 12),
          Text(t('完整帧（十六进制）', 'Frame (hex)'), style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SingleChildScrollView(
              scrollDirection: Axis.horizontal, child: SelectableText(hexDump(p.record.data), style: mono)),
        ]));
  }
}
