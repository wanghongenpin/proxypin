/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:path_provider/path_provider.dart';

/// @author wanghongen
/// 2024/1/1
class ThemeModel {
  static final Map<String, Color> colors = {
    "Blue": Colors.blue,
    "Pink": Colors.pink,
    "Red": Colors.red,
    "Purple": Colors.deepPurple,
    "Green": Colors.green,
    "Teal": Colors.teal,
    "Cyan": Colors.cyan,
    "Orange": Colors.orange,
    "Yellow": Colors.yellow[900]!,
    "Grey": Colors.grey,
  };

  ThemeMode mode;
  bool useMaterial3;
  String color = "Blue";

  ThemeModel({this.mode = ThemeMode.system, this.useMaterial3 = true});

  ThemeModel copy({ThemeMode? mode, bool? useMaterial3}) => ThemeModel(
        mode: mode ?? this.mode,
        useMaterial3: useMaterial3 ?? this.useMaterial3,
      );

  Color get themeColor => colors[color] ?? Colors.blue;
}

class AppConfiguration {
  ValueNotifier<bool> globalChange = ValueNotifier(false);

  ThemeModel _theme = ThemeModel();
  Locale? _language;

  //是否显示更新内容公告
  bool upgradeNoticeV15 = true;

  /// 是否启用画中画
  ValueNotifier<bool> pipEnabled = ValueNotifier(Platform.isAndroid);

  /// 显示画中画图标
  ValueNotifier<bool> pipIcon = ValueNotifier(Platform.isAndroid);

  /// header默认展示
  bool headerExpanded = true;

  /// 底部导航栏
  bool bottomNavigation = true;

  /// 内存清理
  int? memoryCleanupThreshold;

  //桌面window大小
  Size? windowSize;

  //桌面window位置
  Offset? windowPosition;

  //左侧面板占比
  double panelRatio = 0.3;

  AppConfiguration._();

  /// 单例
  static AppConfiguration? _instance;

  static Future<AppConfiguration> get instance async {
    if (_instance == null) {
      AppConfiguration configuration = AppConfiguration._();
      await configuration.initConfig();
      _instance = configuration;
    }
    return _instance!;
  }

  static AppConfiguration? get current => _instance;

  ThemeMode get themeMode => _theme.mode;

  set themeMode(ThemeMode mode) {
    if (mode == _theme.mode) return;
    _theme.mode = mode;
    globalChange.value = !globalChange.value;
    flushConfig();
  }

  ///Material3
  bool get useMaterial3 => _theme.useMaterial3;

  set useMaterial3(bool value) {
    if (value == useMaterial3) return;
    _theme.useMaterial3 = value;
    globalChange.value = !globalChange.value;
    flushConfig();
  }

  Color get themeColor => _theme.themeColor;

  set setThemeColor(String colorName) {
    var color = ThemeModel.colors[colorName];
    if (color == null || color == themeColor) return;

    _theme.color = colorName;
    globalChange.value = !globalChange.value;
    flushConfig();
  }

  ///language
  Locale? get language => _language;

  set language(Locale? locale) {
    if (locale == _language) return;
    _language = locale;
    globalChange.value = !globalChange.value;
    flushConfig();
  }

  Future<File> get _path async {
    if (Platforms.isDesktop()) {
      var userHome = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      return File('$userHome/.proxypin/ui_config.json');
    }

    final directory = await getApplicationSupportDirectory();
    var file = File('${directory.path}${Platform.pathSeparator}ui_config.json');
    if (!await file.exists()) {
      await file.create();
    }
    return file;
  }

  /// 初始化配置
  Future<void> initConfig() async {
    // 读取配置文件
    var file = await _path;
    logger.d(file);
    var exits = await file.exists();
    if (!exits) {
      return;
    }
    var json = await file.readAsString();
    if (json.isEmpty) {
      return;
    }

    try {
      Map<String, dynamic> config = jsonDecode(json);
      var mode =
          ThemeMode.values.firstWhere((element) => element.name == config['mode'], orElse: () => ThemeMode.system);
      _theme = ThemeModel(mode: mode, useMaterial3: config['useMaterial3'] ?? true);
      _theme.color = config['themeColor'] ?? "Blue";

      upgradeNoticeV15 = config['upgradeNoticeV15'] ?? true;
      _language = config['language'] == null ? null : Locale.fromSubtags(languageCode: config['language']);
      pipEnabled.value = config['pipEnabled'] ?? true;
      pipIcon.value = config['pipIcon'] ?? false;
      headerExpanded = config['headerExpanded'] ?? true;
      bottomNavigation = config['bottomNavigation'] ?? true;
      memoryCleanupThreshold = config['memoryCleanupThreshold'];

      windowSize =
          config['windowSize'] == null ? null : Size(config['windowSize']['width'], config['windowSize']['height']);
      windowPosition = config['windowPosition'] == null
          ? null
          : Offset(config['windowPosition']['dx'], config['windowPosition']['dy']);
      if (config['panelRatio'] != null) {
        panelRatio = config['panelRatio'];
      }
    } catch (e) {
      logger.e(e);
    }
  }

  /// 是否正在写入
  bool _isWriting = false;

  /// 刷新配置文件
  flushConfig() async {
    if (_isWriting) return;
    _isWriting = true;

    var file = await _path;
    var exists = await file.exists();
    if (!exists) {
      file = await file.create(recursive: true);
    }

    var json = jsonEncode(toJson());
    await file.writeAsString(json);
    _isWriting = false;
  }

  Map<String, dynamic> toJson() {
    return {
      'mode': _theme.mode.name,
      'themeColor': _theme.color,
      'useMaterial3': _theme.useMaterial3,
      'upgradeNoticeV15': upgradeNoticeV15,
      "language": _language?.languageCode,
      "headerExpanded": headerExpanded,

      if (memoryCleanupThreshold != null) 'memoryCleanupThreshold': memoryCleanupThreshold,

      if (Platforms.isMobile()) 'pipEnabled': pipEnabled.value,
      if (Platforms.isMobile()) 'pipIcon': pipIcon.value ? true : null,
      if (Platforms.isMobile()) 'bottomNavigation': bottomNavigation,

      if (Platforms.isDesktop())
        "windowSize": windowSize == null ? null : {"width": windowSize?.width, "height": windowSize?.height},
      if (Platforms.isDesktop())
        "windowPosition": windowPosition == null ? null : {"dx": windowPosition?.dx, "dy": windowPosition?.dy},
      if (Platforms.isDesktop()) 'panelRatio': panelRatio,
    };
  }
}
