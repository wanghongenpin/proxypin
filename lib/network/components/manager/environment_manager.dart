/*
 * Copyright 2026 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 */

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/random.dart';
import 'package:proxypin/storage/path.dart';

/// 单个环境变量:key/value/enabled
class EnvironmentVariable {
  String key;
  String value;
  bool enabled;

  EnvironmentVariable({required this.key, required this.value, this.enabled = true});

  factory EnvironmentVariable.fromJson(Map<String, dynamic> json) => EnvironmentVariable(
        key: json['key'] ?? '',
        value: json['value'] ?? '',
        enabled: json['enabled'] != false,
      );

  Map<String, dynamic> toJson() => {'key': key, 'value': value, 'enabled': enabled};

  EnvironmentVariable copy() => EnvironmentVariable(key: key, value: value, enabled: enabled);
}

/// 一套环境(包含若干变量)。isGlobal=true 的环境始终存在且唯一。
class Environment {
  final String id;
  String name;
  bool isGlobal;
  List<EnvironmentVariable> variables;

  Environment({
    required this.id,
    required this.name,
    this.isGlobal = false,
    List<EnvironmentVariable>? variables,
  }) : variables = variables ?? [];

  factory Environment.fromJson(Map<String, dynamic> json) => Environment(
        id: json['id'] ?? RandomUtil.randomString(8),
        name: json['name'] ?? '',
        isGlobal: json['isGlobal'] == true,
        variables: (json['variables'] as List?)
                ?.map((e) => EnvironmentVariable.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isGlobal': isGlobal,
        'variables': variables.map((e) => e.toJson()).toList(),
      };

  Environment copy() => Environment(
        id: id,
        name: name,
        isGlobal: isGlobal,
        variables: variables.map((e) => e.copy()).toList(),
      );
}

/// 环境变量管理器
///
/// - 始终存在一个 `isGlobal=true` 的 Global 环境,不可删除。
/// - 用户可创建任意多个命名环境(Dev/Staging/Prod...)。
/// - [activeId] 指向当前激活的命名环境;未激活时只有 Global 生效。
/// - [render] 对任意字符串做 `{{name}}` 替换;未定义变量原样保留。
///
/// @author wanghongen
class EnvironmentManager extends ChangeNotifier {
  static const String _fileName = 'environments.json';

  /// {{name}} 匹配。name 允许字母数字、下划线、点、短横线;两侧允许空白
  static final RegExp _tokenRe = RegExp(r'\{\{\s*([\w.\-]+)\s*\}\}');

  static EnvironmentManager? _instance;

  static Future<EnvironmentManager> get instance async {
    if (_instance == null) {
      final mgr = EnvironmentManager._();
      await mgr._load();
      _instance = mgr;
    }
    return _instance!;
  }

  /// 已加载完成的单例。未加载时返回 null,调用方(如 rewrite 拦截器热路径)
  /// 可用此避免 await 开销;首次异步加载完成后即可用。
  static EnvironmentManager? get instanceOrNull => _instance;

  /// 主动预热,避免首个请求命中时才 IO
  static Future<void> preload() async {
    await instance;
  }

  EnvironmentManager._();

  static File? _configFile;

  static Future<File> _getConfigFile() async {
    if (_configFile != null) return _configFile!;
    final path = await Paths.homePath();
    var file = File('$path${Platform.pathSeparator}$_fileName');
    if (!await file.exists()) {
      await file.create();
    }
    _configFile = file;
    return file;
  }

  bool enabled = true;

  final List<Environment> environments = [];

  /// 当前激活的命名环境 id;null 表示只启用 Global
  String? activeId;

  /// 便利访问器
  Environment get global => environments.firstWhere((e) => e.isGlobal, orElse: () {
        final g = Environment(id: 'global', name: 'Global', isGlobal: true);
        environments.insert(0, g);
        return g;
      });

  Environment? get active {
    if (activeId == null) return null;
    try {
      return environments.firstWhere((e) => e.id == activeId && !e.isGlobal);
    } catch (_) {
      return null;
    }
  }

  List<Environment> get namedEnvironments => environments.where((e) => !e.isGlobal).toList();

  Future<void> _load() async {
    try {
      final file = await _getConfigFile();
      final content = await file.readAsString();
      if (content.isEmpty) {
        _ensureGlobal();
        return;
      }
      final config = jsonDecode(content) as Map<String, dynamic>;
      enabled = config['enabled'] != false;
      activeId = config['activeId'];
      environments.clear();
      final list = (config['environments'] as List?) ?? [];
      for (final e in list) {
        environments.add(Environment.fromJson(e as Map<String, dynamic>));
      }
      _ensureGlobal();
    } catch (e, s) {
      logger.e('EnvironmentManager load failed', error: e, stackTrace: s);
      _ensureGlobal();
    }
  }

  void _ensureGlobal() {
    if (!environments.any((e) => e.isGlobal)) {
      environments.insert(0, Environment(id: 'global', name: 'Global', isGlobal: true));
    }
  }

  Future<void> flushConfig() async {
    try {
      final file = await _getConfigFile();
      final json = jsonEncode({
        'enabled': enabled,
        'activeId': activeId,
        'environments': environments.map((e) => e.toJson()).toList(),
      });
      await file.writeAsString(json);
    } catch (e, s) {
      logger.e('EnvironmentManager flush failed', error: e, stackTrace: s);
    }
  }

  /// 添加/更新命名环境
  void upsertEnvironment(Environment env) {
    if (env.isGlobal) return; // 通过 global 直接改
    final idx = environments.indexWhere((e) => e.id == env.id);
    if (idx == -1) {
      environments.add(env);
    } else {
      environments[idx] = env;
    }
    notifyListeners();
  }

  void removeEnvironment(String id) {
    final removed = environments.firstWhere(
      (e) => e.id == id && !e.isGlobal,
      orElse: () => Environment(id: '', name: ''),
    );
    if (removed.id.isEmpty) return;
    environments.remove(removed);
    if (activeId == id) activeId = null;
    notifyListeners();
  }

  /// 用一份工作副本替换当前所有环境(用于 UI"保存"时的批量提交)。
  /// - 保证仍存在一个 isGlobal=true 的 Global 环境。
  /// - 若激活环境在新列表中不存在(或被降为 global),则清空 activeId。
  void applyFrom(List<Environment> workingCopy) {
    environments
      ..clear()
      ..addAll(workingCopy.map((e) => e.copy()));
    _ensureGlobal();
    if (activeId != null && !environments.any((e) => e.id == activeId && !e.isGlobal)) {
      activeId = null;
    }
    notifyListeners();
  }

  void setActive(String? id) {
    activeId = id;
    notifyListeners();
  }

  void setEnabled(bool value) {
    enabled = value;
    notifyListeners();
  }

  /// 解析单个变量。激活环境优先,回退到 Global。返回 null 表示未定义。
  String? resolve(String name) {
    if (!enabled) return null;
    final act = active;
    if (act != null) {
      for (final v in act.variables) {
        if (v.enabled && v.key == name) return v.value;
      }
    }
    for (final v in global.variables) {
      if (v.enabled && v.key == name) return v.value;
    }
    return null;
  }

  /// 展平当前生效变量(用于 script 注入)。同 key 时 active 覆盖 global。
  Map<String, String> flatMap() {
    if (!enabled) return const {};
    final map = <String, String>{};
    for (final v in global.variables) {
      if (v.enabled) map[v.key] = v.value;
    }
    final act = active;
    if (act != null) {
      for (final v in act.variables) {
        if (v.enabled) map[v.key] = v.value;
      }
    }
    return map;
  }

  /// 渲染 `{{name}}`。空 / 不含 `{{` 时直接返回原字符串,避免热路径正则开销。
  /// 未定义变量原样保留(便于用户发现拼写错误)。仅解析一层,不递归。
  String render(String? input) {
    if (input == null || input.isEmpty) return input ?? '';
    if (!input.contains('{{')) return input;
    if (!enabled) return input;
    return input.replaceAllMapped(_tokenRe, (m) {
      final v = resolve(m.group(1)!);
      return v ?? m.group(0)!;
    });
  }
}
