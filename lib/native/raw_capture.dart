import 'dart:async';
import 'dart:io';


import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/network/pcap/capture_session.dart';
import 'package:proxypin/network/pcap/packet.dart';
import 'package:proxypin/network/pcap/pcap.dart';
import 'package:proxypin/network/pcap/pcapng.dart';
import 'package:proxypin/network/util/tls_keylog.dart';
import 'package:proxypin/network/util/logger.dart';

class RawCaptureStatus {
  final bool running;
  final String? file;
  final bool bundled;
  final bool hasSu;
  final String? abi;
  final int droppedForUi;

  RawCaptureStatus(this.running, this.file, this.bundled, this.hasSu, this.abi, this.droppedForUi);

  bool get available => bundled && hasSu;
}

/// Root 原始抓包（内置 tcpdump）控制器，全局单例，离开页面后抓包继续。
class RawCapture extends ChangeNotifier {
  static final RawCapture instance = RawCapture._();

  static const MethodChannel _channel = MethodChannel('com.proxy/rawCapture');
  static const EventChannel _events = EventChannel('com.proxy/rawCapture/events');

  RawCapture._();

  CaptureSession session = CaptureSession();
  bool running = false;
  String? file;
  String? lastError;

  StreamSubscription? _subscription;
  Timer? _notifyTimer;
  bool _dirty = false;

  static bool get supported => Platform.isAndroid;

  Future<RawCaptureStatus> status() async {
    final m = await _channel.invokeMapMethod<String, dynamic>('status') ?? {};
    return RawCaptureStatus(m['running'] == true, m['file'], m['bundled'] == true, m['hasSu'] == true, m['abi'],
        (m['droppedForUi'] as num?)?.toInt() ?? 0);
  }

  Future<bool> start({String iface = 'any', String filter = '', int snapLen = 0}) async {
    if (running) return true;
    lastError = null;
    session = CaptureSession()..onNewFlow = _resolveOwner;
    // 抓包期间记录 ProxyPin 上游 TLS 会话密钥，导出 pcapng 时嵌入
    TlsKeyLog.instance.start();
    _listen();
    final result = await _channel.invokeMapMethod<String, dynamic>(
        'start', {'iface': iface, 'filter': filter, 'snapLen': snapLen});
    if (result?['success'] != true) {
      lastError = result?['error']?.toString() ?? 'unknown error';
      TlsKeyLog.instance.stop();
      logger.w('raw capture start failed: $lastError');
      notifyListeners();
      return false;
    }
    file = result?['file'];
    running = true;
    notifyListeners();
    return true;
  }

  Future<void> stop() async {
    final path = await _channel.invokeMethod<String>('stop');
    file = path ?? file;
    running = false;
    TlsKeyLog.instance.stop();
    _flushNotify();
  }

  /// 同步原生侧状态（例如页面重建后）
  Future<void> refresh() async {
    final s = await status();
    if (s.running && _subscription == null) _listen();
    running = s.running;
    file = s.file ?? file;
    notifyListeners();
  }

  void clear() {
    session.clear();
    session.onNewFlow = _resolveOwner;
    notifyListeners();
  }

  void _listen() {
    _subscription ??= _events.receiveBroadcastStream().listen((event) {
      if (event is Uint8List) {
        try {
          session.feed(event, notify: false);
        } catch (e) {
          logger.e('pcap parse error', error: e);
        }
        _scheduleNotify();
      } else if (event is Map && event['event'] == 'stopped') {
        running = false;
        TlsKeyLog.instance.stop();
        if (event['error'] != null) lastError = event['error'].toString();
        file = event['file'] ?? file;
        _flushNotify();
      }
    }, onError: (e) => logger.e('raw capture stream error', error: e));
  }

  /// 抓包高峰时限制 UI 刷新频率
  void _scheduleNotify() {
    _dirty = true;
    _notifyTimer ??= Timer(const Duration(milliseconds: 400), _flushNotify);
  }

  void _flushNotify() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _dirty = false;
    notifyListeners();
  }

  bool get hasPendingUpdate => _dirty;

  // ------------- 应用归属 -------------

  final Map<String, Map?> _ownerCache = {};

  void _resolveOwner(NetFlow flow) {
    if (flow.protocol != TransportProtocol.tcp && flow.protocol != TransportProtocol.udp) {
      flow.ownerResolved = true;
      return;
    }
    _lookup(flow, retry: true);
  }

  Future<void> _lookup(NetFlow flow, {bool retry = false}) async {
    final proto = flow.protocol == TransportProtocol.tcp ? 'tcp' : 'udp';
    final key = '$proto:${flow.clientPort}:${flow.serverPort}';
    Map? owner = _ownerCache[key];
    if (owner == null && !_ownerCache.containsKey(key)) {
      try {
        owner = await _channel.invokeMapMethod('lookupOwner',
            {'proto': proto, 'srcPort': flow.clientPort ?? 0, 'dstPort': flow.serverPort ?? 0});
      } catch (_) {}
      if (owner != null || !retry) _ownerCache[key] = owner;
    }
    if (owner == null) {
      // 连接表有 1 秒缓存，新连接可能尚未出现，稍后重试一次
      if (retry) Timer(const Duration(milliseconds: 1500), () => _lookup(flow));
      flow.ownerResolved = !retry;
      return;
    }
    flow.uid = (owner['uid'] as num?)?.toInt();
    flow.appName = owner['name']?.toString();
    flow.appPackage = owner['packageName']?.toString();
    flow.ownerResolved = true;
    _scheduleNotify();
  }

  // ------------- 导出 -------------

  /// 本次抓包收集到的 TLS 密钥条数
  int get tlsKeyCount => TlsKeyLog.instance.length;

  int get tlsConnectionCount => TlsKeyLog.instance.connectionCount;

  String get _comment =>
      'Captured by ProxyPin. TLS keys embedded for ProxyPin upstream connections '
      '(ProxyPin -> server); app -> ProxyPin (127.0.0.1) legs cannot be decrypted.';

  String _name(String ext) => 'proxypin-${DateTime.now().millisecondsSinceEpoch}.$ext';

  /// 导出指定包（筛选结果 / 单条流）。[pcapng] 为 true 时嵌入 TLS 密钥
  Future<File> exportPackets(Iterable<Packet> packets, String directory, {bool pcapng = true}) async {
    final sorted = packets.toList()..sort((a, b) => a.index.compareTo(b.index));
    final Uint8List bytes;
    if (pcapng) {
      bytes = PcapngWriter.build(session.linkType ?? LinkType.raw, sorted.map((p) => p.record),
          keyLog: TlsKeyLog.instance.export(), comment: _comment);
    } else {
      bytes = session.exportPcap(sorted);
    }
    final f = File('$directory/${_name(pcapng ? 'pcapng' : 'pcap')}');
    await f.writeAsBytes(bytes);
    return f;
  }

  /// 导出完整抓包文件。pcapng 由原始 pcap 文件流式转换并嵌入密钥；否则直接返回原始 pcap
  Future<File?> exportFull(String directory, {bool pcapng = true}) async {
    final path = file;
    if (path == null || !await File(path).exists()) return null;
    if (!pcapng) return File(path);
    final out = File('$directory/${File(path).uri.pathSegments.last.replaceAll('.pcap', '')}.pcapng');
    await PcapngWriter.convertFile(File(path), out, keyLog: TlsKeyLog.instance.export(), comment: _comment);
    return out;
  }
}
