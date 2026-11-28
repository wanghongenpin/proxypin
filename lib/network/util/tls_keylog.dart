/// TLS 会话密钥收集（NSS Key Log 格式，即 SSLKEYLOGFILE）。
///
/// 仅能收集 ProxyPin 作为 TLS 客户端的连接（ProxyPin → 真实服务器），
/// Dart 的 `SecureSocket.secureServer` 未开放 keyLog，App → ProxyPin 一侧无法获取。
///
/// 只在启用期间（如原始抓包进行中）记录；未启用时 [callback] 返回 null，不给 TLS 增加任何开销。
class TlsKeyLog {
  TlsKeyLog._();

  static final TlsKeyLog instance = TlsKeyLog._();

  /// 最多保留的行数（TLS 1.3 每个连接 5 行，约 1KB）
  static const int maxLines = 100000;

  final List<String> _lines = [];
  final Set<String> _seen = {};
  bool _enabled = false;
  int dropped = 0;

  bool get enabled => _enabled;

  int get length => _lines.length;

  List<String> get lines => List.unmodifiable(_lines);

  /// 估算的连接数（每个连接都有一行 CLIENT_RANDOM 或 CLIENT_TRAFFIC_SECRET_0）
  int get connectionCount =>
      _lines.where((l) => l.startsWith('CLIENT_RANDOM ') || l.startsWith('CLIENT_TRAFFIC_SECRET_0 ')).length;

  /// 开始记录；[reset] 为 true 时清空之前的密钥
  void start({bool reset = true}) {
    if (reset) clear();
    _enabled = true;
  }

  void stop() {
    _enabled = false;
  }

  void clear() {
    _lines.clear();
    _seen.clear();
    dropped = 0;
  }

  /// 供 `SecureSocket.connect/secure(keyLog: ...)` 使用
  void Function(String line)? get callback => _enabled ? add : null;

  void add(String line) {
    final l = line.trim();
    if (l.isEmpty || l.startsWith('#')) return;
    if (!_seen.add(l)) return;
    if (_lines.length >= maxLines) {
      dropped++;
      return;
    }
    _lines.add(l);
  }

  /// NSS Key Log 文本
  String export() => _lines.isEmpty ? '' : '${_lines.join('\n')}\n';
}
