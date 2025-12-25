import 'dart:convert';

import '../../../storage/path.dart';
import '../../util/logger.dart';

class ReportServerManager {
  static ReportServerManager? _instance;

  List<ReportServer> _list = [];

  ///单例
  static Future<ReportServerManager> get instance async {
    if (_instance == null) {
      _instance = ReportServerManager._internal();
      await _instance!.loadConfig();
    }
    return _instance!;
  }

  // Private constructor
  ReportServerManager._internal();

  /// Get configured report servers
  List<ReportServer> get servers => _list;

  Future<ReportServer?> matchServer(String url) async {
    final list = servers;
    for (var server in list) {
      if (server.match(url)) {
        return server;
      }
    }
    return null;
  }

  Future<void> add(ReportServer server) async {
    _list.add(server);
    await _flush();
  }

  Future<void> removeAt(int index) async {
    final list = servers;
    list.removeAt(index);
    await _flush();
  }

  Future<void> update(int index, ReportServer server) async {
    final list = servers;
    server.updateUrlReg();
    list[index] = server;
    await _flush();
  }

  Future<void> toggleEnabled(int index, bool enabled) async {
    final list = servers;
    list[index] = list[index].copyWith(enabled: enabled);
    await _flush();
  }

  Future<void> loadConfig() async {
    var list = <ReportServer>[];
    final file = await Paths.getPath("report_servers.json");
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(content) as List<dynamic>;
          list = decoded.map((e) => ReportServer.fromJson(e as Map<String, dynamic>)).toList();
        } catch (e, t) {
          logger.e('上报服务器配置解析失败', error: e, stackTrace: t);
        }
      }
    }

    _list = list;
  }

  Future<void> _flush() async {
    final file = await Paths.getPath("report_servers.json");
    final list = servers;
    await file.writeAsString(jsonEncode(list.map((e) => e.toJson()).toList()));
  }
}

class ReportServer {
  final String name;

  final String matchUrl;

  /// 服务器URL
  final String serverUrl;

  /// 是否启用
  final bool enabled;

  /// 压缩方式：none/gzip，默认 none
  final String? compression;

  RegExp _urlReg;

  ReportServer({
    required this.name,
    required this.matchUrl,
    required this.serverUrl,
    this.enabled = true,
    this.compression,
  }) : _urlReg = RegExp(matchUrl.replaceAll("*", ".*").replaceFirst('?', '\\?'));

  bool match(String url) {
    if (enabled) {
      return _urlReg.hasMatch(url);
    }
    return false;
  }

  void updateUrlReg() {
    _urlReg = RegExp(matchUrl.replaceAll("*", ".*").replaceFirst('?', '\\?'));
  }

  ReportServer copyWith({
    String? name,
    String? serverUrl,
    bool? enabled,
    String? matchUrl,
    String? matchType,
    String? compression,
    Map<String, String>? headers,
  }) {
    return ReportServer(
      name: name ?? this.name,
      matchUrl: matchUrl ?? this.matchUrl,
      serverUrl: serverUrl ?? this.serverUrl,
      enabled: enabled ?? this.enabled,
      compression: compression ?? this.compression,
    );
  }

  factory ReportServer.fromJson(Map<String, dynamic> json) {
    return ReportServer(
      name: json['name'] ?? '',
      matchUrl: json['matchUrl'] ?? '',
      serverUrl: json['serverUrl'] ?? '',
      enabled: json['enabled'] ?? true,
      compression: (json['compression'] ?? 'none') as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'matchUrl': matchUrl,
      'serverUrl': serverUrl,
      'enabled': enabled,
      'compression': compression,
    };
  }
}
