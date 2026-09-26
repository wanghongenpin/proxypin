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
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/random.dart';
import 'package:proxypin/storage/path.dart';
import 'package:proxypin/utils/lang.dart';

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

  /// {{name}} 匹配。name 允许字母数字、下划线、点、短横线;两侧允许空白。
  /// 首字符可选 `$` —— 用于标记"内置动态变量"(如 `{{$date}}` / `{{$guid}}`),
  /// `resolve()` 看到 `$` 前缀会直接走内置解析,确保用户不能 shadow 内置名。
  static final RegExp _tokenRe = RegExp(r'\{\{\s*(\$?[\w.\-]+)\s*\}\}');

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

  /// 重命名命名环境(仅改名,不动 variables)
  bool renameEnvironment(String id, String name) {
    final target = environments.firstWhere(
      (e) => e.id == id && !e.isGlobal,
      orElse: () => Environment(id: '', name: ''),
    );
    if (target.id.isEmpty || target.name == name) return false;
    target.name = name;
    notifyListeners();
    return true;
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
  ///
  /// 注意:调用方需自行处理"环境结构(存在/命名)已经实时落库,只需要同步 variables"
  /// 的场景 —— 此方法会整表替换。
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

  /// 脚本侧写入变量:优先写入激活环境,无激活时写入 Global。
  /// - 若该变量在激活环境已存在,原地更新;
  /// - 若只在 Global 存在,在激活环境新增一条覆盖(Global 不动);
  /// - 无激活环境时直接写 Global。
  /// value == null 视作删除。
  /// 返回 true 表示有实际变更。
  bool setVariableFromScript(String name, String? value) {
    final target = active ?? global;
    final existing = target.variables.firstWhere(
      (v) => v.key == name,
      orElse: () => EnvironmentVariable(key: '', value: ''),
    );

    if (value == null) {
      // 删除:仅从目标环境删除;若目标只有 global 中同名条目而 active 中没有,不动 global
      if (existing.key.isEmpty) return false;
      target.variables.remove(existing);
      notifyListeners();
      return true;
    }

    if (existing.key.isNotEmpty) {
      if (existing.value == value && existing.enabled) return false;
      existing.value = value;
      existing.enabled = true;
    } else {
      target.variables.add(EnvironmentVariable(key: name, value: value));
    }
    notifyListeners();
    return true;
  }

  /// 计算脚本运行后 env map 的差异并应用。返回是否有变更。
  /// [before] / [after] 是脚本运行前/后由 [flatMap] 展平的视图。
  bool applyScriptEnvChanges(Map<String, String> before, Map<dynamic, dynamic> after) {
    if (!enabled) return false;
    bool changed = false;
    // 新增/修改
    after.forEach((k, v) {
      if (k is! String) return;
      final newVal = v?.toString();
      if (newVal == null) return; // 视作删除,交给下面统一处理
      if (before[k] != newVal) {
        if (setVariableFromScript(k, newVal)) changed = true;
      }
    });
    // 删除:脚本里显式设 null/undefined 或 delete
    before.forEach((k, _) {
      final v = after[k];
      final present = after.containsKey(k) && v != null;
      if (!present) {
        if (setVariableFromScript(k, null)) changed = true;
      }
    });
    return changed;
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
  /// 以 `$` 开头的名字是内置动态变量,不在用户 env 中查找 —— 避免被同名用户变量 shadow。
  String? resolve(String name) {
    if (!enabled) return null;
    if (name.startsWith(r'$')) return null;
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

  /// 共享 `Random` —— 用 `Random()`(非 secure)够 `$randomString` / `$randomInt` 使用。
  /// UUID v4 单独用 `Random.secure()` 保证不可预测。
  static final Random _builtinRandom = Random();
  static final Random _secureRandom = Random.secure();

  /// 内置动态变量解析。无 `{{}}` 的 token 走 `render()` 走不到这里;`{{$xxx}}` 形式
  /// 才会调到。未知 `$xxx` 返回 null,让 `render()` 把它当字面量保留,方便发现拼错。
  ///
  /// 命名约定:`$` 前缀 + 小写英文单词。`$guid` / `$uuid` 双名同义。
  static String? resolveBuiltIn(String name) {
    if (!name.startsWith(r'$')) return null;
    switch (name) {
      case r'$date':
        return DateTime.now().dateFormat();
      case r'$datetime':
        return DateTime.now().format();
      case r'$timestamp':
        return (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      case r'$timestampMs':
        return DateTime.now().millisecondsSinceEpoch.toString();
      case r'$guid':
      case r'$uuid':
        return _uuidV4();
      case r'$randomString':
        return RandomUtil.randomString(8);
      case r'$randomInt':
        return _builtinRandom.nextInt(1000000).toString();
      default:
        return null;
    }
  }

  /// RFC 4122 v4 UUID —— 36 字符串,hex 段格式 `8-4-4-4-12`。
  /// 用 `Random.secure()` 保证唯一性 / 不可预测。
  static String _uuidV4() {
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// 暴露给 UI 展示 / 单测:所有内置变量名 + 简短说明。顺序即 UI 菜单展示顺序。
  static const List<MapEntry<String, String>> builtInVariables = [
    MapEntry(r'$date', 'yyyy-MM-dd'),
    MapEntry(r'$datetime', 'yyyy-MM-dd HH:mm:ss'),
    MapEntry(r'$timestamp', '1700000000'),
    MapEntry(r'$timestampMs', '1700000000000'),
    MapEntry(r'$guid', 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'),
    MapEntry(r'$uuid', 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'),
    MapEntry(r'$randomString', '8-char alphanumeric'),
    MapEntry(r'$randomInt', '0..999999'),
  ];

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
  /// `$` 前缀走 [resolveBuiltIn];非 `$` 走用户 env。
  /// `enabled=false` 时整体跳过替换(包括内置)—— 与"env 禁用 = 不替换"语义保持一致,
  /// 避免禁用 env 后 `{{$date}}` 还在静默生效的隐式行为。
  String render(String? input) {
    if (input == null || input.isEmpty) return input ?? '';
    if (!input.contains('{{')) return input;
    if (!enabled) return input;
    return input.replaceAllMapped(_tokenRe, (m) {
      final name = m.group(1)!;
      if (name.startsWith(r'$')) {
        return resolveBuiltIn(name) ?? m.group(0)!;
      }
      return resolve(name) ?? m.group(0)!;
    });
  }

  /// 便利入口:热路径拦截器统一调用,处理 null / empty / manager 未加载 / disabled 情况。
  /// - manager 未加载:仅解析内置(`{{$date}}` 等仍生效),用户 env 不可达。
  /// - manager 已加载:走 [render] 的完整逻辑(内置 + 用户 env,env disabled 时整体不替换)。
  /// 输入为 null 时返回 null,其余情况返回渲染后的字符串。
  static String? tryRender(String? input) {
    if (input == null || input.isEmpty || !input.contains('{{')) return input;
    final mgr = _instance;
    if (mgr == null) return _renderBuiltInsOnly(input);
    return mgr.render(input);
  }

  /// 不依赖单例的内置渲染。manager 还没加载时(冷启动)给热路径兜底;
  /// 这种场景下没有用户 env,只有内置变量可以解析。
  static String? _renderBuiltInsOnly(String input) {
    return input.replaceAllMapped(_tokenRe, (m) {
      final name = m.group(1)!;
      if (name.startsWith(r'$')) {
        return resolveBuiltIn(name) ?? m.group(0)!;
      }
      return m.group(0)!;
    });
  }
}
