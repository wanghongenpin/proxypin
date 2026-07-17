/*
 * Copyright 2025 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 */

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:proxypin/network/util/url_pattern.dart';

/// 弱网模拟配置管理
///
/// 数据模型：
/// - 一组「预设」(NetworkConditionProfile)：内置只读 + 用户自建；
/// - URL 规则列表：每条规则 = `url + profileId + enabled`，命中即用绑定的预设参数；
/// - 规则为空时视为不启用弱网（enabled=false 时也不启用）。
///
/// @author wanghongen
class NetworkConditionManager extends ChangeNotifier {
  static NetworkConditionManager? _instance;

  /// 全局启用开关
  bool enabled = false;

  /// URL 规则列表：每条绑定一个预设 id。列表为空 = 不启用。
  List<NetworkConditionRule> rules = [];

  /// 用户自建预设（会持久化）
  List<NetworkConditionProfile> customProfiles = [];

  final File _storageFile;

  NetworkConditionManager._(this._storageFile);

  static const _defaultBuiltinId = 'g4';

  static Future<NetworkConditionManager> get instance async {
    if (_instance == null) {
      var file = await _configFile();
      _instance = NetworkConditionManager._(file);
      await _instance!._load();
    }
    return _instance!;
  }

  static Future<File> _configFile() async {
    var directory = await getApplicationSupportDirectory().then((it) => it.path);
    var file = File('$directory${Platform.pathSeparator}network_condition.json');
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return file;
  }

  /// 所有可选预设 = 内置 + 自建
  List<NetworkConditionProfile> get allProfiles => [
        ...NetworkConditionProfile.builtin,
        ...customProfiles,
      ];

  NetworkConditionProfile? findProfile(String id) {
    for (final p in allProfiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 默认预设：新建规则时用作初始选择。
  NetworkConditionProfile get defaultProfile =>
      NetworkConditionProfile.builtin.firstWhere((p) => p.id == _defaultBuiltinId);

  Future<void> _load() async {
    var json = await _storageFile.readAsString();
    if (json.isEmpty) return;
    try {
      var config = jsonDecode(json) as Map<String, dynamic>;
      enabled = config['enabled'] == true;

      customProfiles.clear();
      final profilesRaw = config['customProfiles'];
      if (profilesRaw is List) {
        for (var e in profilesRaw) {
          customProfiles.add(NetworkConditionProfile.fromJson(e as Map<String, dynamic>));
        }
      }

      // 迁移老 currentProfileId + 顶层参数（如果配置里还有的话）到一个 "旧全局" profile，
      // 供旧规则默认引用。
      String? legacyGlobalProfileId;
      final legacyPresetId = config['profileId']?.toString() ?? config['preset']?.toString();
      final hasLegacyGlobalFields = config.containsKey('uploadKbps') || config.containsKey('downloadKbps');
      if (legacyPresetId == 'custom' && hasLegacyGlobalFields) {
        final p = NetworkConditionProfile(
          id: _newCustomId(),
          name: '自定义',
          uploadKbps: (config['uploadKbps'] as num?)?.toInt(),
          downloadKbps: (config['downloadKbps'] as num?)?.toInt(),
          requestLatencyMs: (config['requestLatencyMs'] as num?)?.toInt() ?? 0,
          responseLatencyMs: (config['responseLatencyMs'] as num?)?.toInt() ?? 0,
          jitterMs: (config['jitterMs'] as num?)?.toInt() ?? 0,
          lossRate: (config['lossRate'] as num?)?.toDouble() ?? 0.0,
          offline: config['offline'] == true,
        );
        customProfiles.add(p);
        legacyGlobalProfileId = p.id;
      } else if (legacyPresetId != null && findProfile(legacyPresetId) != null) {
        legacyGlobalProfileId = legacyPresetId;
      }

      rules.clear();
      final list = config['rules'];
      if (list is List) {
        for (var e in list) {
          rules.add(_ruleFromJson(e as Map<String, dynamic>, fallbackProfileId: legacyGlobalProfileId));
        }
      }

      // 老配置里 rules 为空但顶层有全局参数 —— 在新模型里表现为 "无规则=不启用"。
      // 若之前用户依赖全局限速，需要显式建一条通配规则；这里为老用户自动生成一条 URL=* 的规则。
      if (rules.isEmpty && legacyGlobalProfileId != null && (config['enabled'] == true)) {
        rules.add(NetworkConditionRule(enabled: true, url: '*', profileId: legacyGlobalProfileId));
      }

      final needFlush = hasLegacyGlobalFields || legacyPresetId != null;
      if (needFlush) await flushConfig();
    } catch (_) {
      // ignore corrupted config
    }
  }

  /// 老规则可能带有自己的字段覆盖（uploadKbps 等），也可能已经是新格式（profileId）。
  NetworkConditionRule _ruleFromJson(Map<String, dynamic> json, {String? fallbackProfileId}) {
    final profileId = json['profileId']?.toString();
    if (profileId != null && findProfile(profileId) != null) {
      return NetworkConditionRule(
        enabled: json['enabled'] != false,
        url: json['url']?.toString() ?? '',
        profileId: profileId,
      );
    }
    // 老规则：字段可能自己带覆盖参数 —— 生成一条 "规则-XX" 自建 profile 承载它们
    final hasOverrides = json.containsKey('uploadKbps') ||
        json.containsKey('downloadKbps') ||
        json.containsKey('requestLatencyMs') ||
        json.containsKey('responseLatencyMs') ||
        json.containsKey('jitterMs') ||
        json.containsKey('lossRate') ||
        json.containsKey('offline');
    if (hasOverrides) {
      final p = NetworkConditionProfile(
        id: _newCustomId(),
        name: '规则-${customProfiles.length + 1}',
        uploadKbps: (json['uploadKbps'] as num?)?.toInt(),
        downloadKbps: (json['downloadKbps'] as num?)?.toInt(),
        requestLatencyMs: (json['requestLatencyMs'] as num?)?.toInt() ?? 0,
        responseLatencyMs: (json['responseLatencyMs'] as num?)?.toInt() ?? 0,
        jitterMs: (json['jitterMs'] as num?)?.toInt() ?? 0,
        lossRate: (json['lossRate'] as num?)?.toDouble() ?? 0.0,
        offline: json['offline'] == true,
      );
      customProfiles.add(p);
      return NetworkConditionRule(
        enabled: json['enabled'] != false,
        url: json['url']?.toString() ?? '',
        profileId: p.id,
      );
    }
    // 没有覆盖字段：绑定到全局旧 profile 或默认预设
    return NetworkConditionRule(
      enabled: json['enabled'] != false,
      url: json['url']?.toString() ?? '',
      profileId: fallbackProfileId ?? _defaultBuiltinId,
    );
  }

  Future<void> flushConfig() async {
    await _storageFile.writeAsString(jsonEncode(toJson()));
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'rules': rules.map((e) => e.toJson()).toList(),
        'customProfiles': customProfiles.map((e) => e.toJson()).toList(),
      };

  /// 增/改一个自建预设。
  Future<void> upsertCustomProfile(NetworkConditionProfile p) async {
    final idx = customProfiles.indexWhere((e) => e.id == p.id);
    if (idx == -1) {
      customProfiles.add(p);
    } else {
      customProfiles[idx] = p;
    }
    await flushConfig();
  }

  /// 删除一个自建预设；任何绑定它的规则回落到默认预设。
  Future<void> deleteCustomProfile(String id) async {
    customProfiles.removeWhere((e) => e.id == id);
    for (final r in rules) {
      if (r.profileId == id) r.profileId = _defaultBuiltinId;
    }
    await flushConfig();
  }

  /// 生成自建 profile id。
  static String _newCustomId() {
    final r = Random();
    return 'custom-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${r.nextInt(1 << 20).toRadixString(36)}';
  }

  static String newCustomId() => _newCustomId();

  /// 解析当前 URL 生效的弱网参数。
  /// - enabled=false 或规则列表为空 或没命中任何规则，返回 null（不启用）。
  NetworkConditionEffective? resolve(String url) {
    if (!enabled || rules.isEmpty) return null;
    for (final r in rules) {
      if (r.match(url)) {
        final p = findProfile(r.profileId) ?? defaultProfile;
        return NetworkConditionEffective(
          uploadKbps: p.uploadKbps,
          downloadKbps: p.downloadKbps,
          requestLatencyMs: p.requestLatencyMs,
          responseLatencyMs: p.responseLatencyMs,
          jitterMs: p.jitterMs,
          lossRate: p.lossRate,
          offline: p.offline,
        );
      }
    }
    return null;
  }
}

/// 弱网参数快照：由 [NetworkConditionManager.resolve] 生成，
/// 表示对某个 URL 最终生效的一组参数。
class NetworkConditionEffective {
  final int? uploadKbps;
  final int? downloadKbps;
  final int requestLatencyMs;
  final int responseLatencyMs;
  final int jitterMs;
  final double lossRate;
  final bool offline;

  const NetworkConditionEffective({
    this.uploadKbps,
    this.downloadKbps,
    this.requestLatencyMs = 0,
    this.responseLatencyMs = 0,
    this.jitterMs = 0,
    this.lossRate = 0.0,
    this.offline = false,
  });
}

/// 弱网预设：一组带宽/延迟/丢包参数快照。
///
/// - 内置预设通过 [builtin] 提供，[isBuiltin] 为 true，name 是 l10n key；
/// - 自建预设由用户创建，name 是用户输入的原始字符串。
class NetworkConditionProfile {
  final String id;
  String name;
  final bool isBuiltin;

  int? uploadKbps;
  int? downloadKbps;
  int requestLatencyMs;
  int responseLatencyMs;
  int jitterMs;
  double lossRate;
  bool offline;

  NetworkConditionProfile({
    required this.id,
    required this.name,
    this.isBuiltin = false,
    this.uploadKbps,
    this.downloadKbps,
    this.requestLatencyMs = 0,
    this.responseLatencyMs = 0,
    this.jitterMs = 0,
    this.lossRate = 0.0,
    this.offline = false,
  });

  NetworkConditionProfile copy() => NetworkConditionProfile(
        id: id,
        name: name,
        isBuiltin: isBuiltin,
        uploadKbps: uploadKbps,
        downloadKbps: downloadKbps,
        requestLatencyMs: requestLatencyMs,
        responseLatencyMs: responseLatencyMs,
        jitterMs: jitterMs,
        lossRate: lossRate,
        offline: offline,
      );

  factory NetworkConditionProfile.fromJson(Map<String, dynamic> json) {
    return NetworkConditionProfile(
      id: json['id']?.toString() ?? NetworkConditionManager._newCustomId(),
      name: json['name']?.toString() ?? '',
      isBuiltin: false, // 只有内置常量表里的才是内置
      uploadKbps: (json['uploadKbps'] as num?)?.toInt(),
      downloadKbps: (json['downloadKbps'] as num?)?.toInt(),
      requestLatencyMs: (json['requestLatencyMs'] as num?)?.toInt() ?? 0,
      responseLatencyMs: (json['responseLatencyMs'] as num?)?.toInt() ?? 0,
      jitterMs: (json['jitterMs'] as num?)?.toInt() ?? 0,
      lossRate: (json['lossRate'] as num?)?.toDouble() ?? 0.0,
      offline: json['offline'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'uploadKbps': uploadKbps,
        'downloadKbps': downloadKbps,
        'requestLatencyMs': requestLatencyMs,
        'responseLatencyMs': responseLatencyMs,
        'jitterMs': jitterMs,
        'lossRate': lossRate,
        'offline': offline,
      };

  /// 内置预设列表（顺序即下拉展示顺序）。
  /// `name` 是 l10n key，UI 拿去查表；自建预设的 name 则是用户输入的原始字符串。
  static final List<NetworkConditionProfile> builtin = [
    NetworkConditionProfile(
      id: 'weak',
      name: 'weakNetworkPresetWeak',
      isBuiltin: true,
      uploadKbps: 300,
      downloadKbps: 600,
      requestLatencyMs: 800,
      responseLatencyMs: 800,
      jitterMs: 200,
      lossRate: 0.03,
    ),
    NetworkConditionProfile(
      id: 'slow',
      name: 'weakNetworkPresetSlow',
      isBuiltin: true,
      uploadKbps: 1500,
      downloadKbps: 2000,
      requestLatencyMs: 300,
      responseLatencyMs: 300,
      jitterMs: 50,
    ),
    NetworkConditionProfile(
      id: 'g2',
      name: 'weakNetworkPreset2G',
      isBuiltin: true,
      uploadKbps: 50,
      downloadKbps: 100,
      requestLatencyMs: 500,
      responseLatencyMs: 500,
      jitterMs: 100,
      lossRate: 0.02,
    ),
    NetworkConditionProfile(
      id: 'g3',
      name: 'weakNetworkPreset3G',
      isBuiltin: true,
      uploadKbps: 400,
      downloadKbps: 750,
      requestLatencyMs: 200,
      responseLatencyMs: 200,
      jitterMs: 50,
      lossRate: 0.005,
    ),
    NetworkConditionProfile(
      id: 'g4',
      name: 'weakNetworkPreset4G',
      isBuiltin: true,
      uploadKbps: 3000,
      downloadKbps: 4000,
      requestLatencyMs: 70,
      responseLatencyMs: 70,
      jitterMs: 20,
    ),
    NetworkConditionProfile(
      id: 'g5',
      name: 'weakNetworkPreset5G',
      isBuiltin: true,
      uploadKbps: 50000,
      downloadKbps: 100000,
      requestLatencyMs: 20,
      responseLatencyMs: 20,
      jitterMs: 5,
    ),
    NetworkConditionProfile(
      id: 'wifi',
      name: 'weakNetworkPresetWifi',
      isBuiltin: true,
      uploadKbps: 10000,
      downloadKbps: 30000,
      requestLatencyMs: 30,
      responseLatencyMs: 30,
      jitterMs: 10,
    ),
  ];
}

/// URL 规则：绑定一个预设 id，命中即使用该预设参数。
class NetworkConditionRule {
  bool enabled;
  String url;
  String profileId;

  RegExp? _urlReg;

  NetworkConditionRule({
    this.enabled = true,
    this.url = '',
    this.profileId = 'g4',
  });

  bool match(String matchUrl) {
    if (!enabled || url.trim().isEmpty) return false;
    _urlReg ??= UrlPattern.toRegExp(url);
    return _urlReg!.hasMatch(matchUrl);
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'url': url,
        'profileId': profileId,
      };

  void resetCache() => _urlReg = null;
}
