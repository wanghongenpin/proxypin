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
class ColorMapping {
  static final Map<String, Color> colors = {
    "Blue": Color(0xFF4A6CF7),
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

  static Color getColor(String colorName) {
    return colors[colorName] ?? Colors.blue;
  }

  static String getColorName(Color color) {
    return colors.entries.firstWhere((entry) => entry.value == color).key;
  }
}

class ThemeModel {
  ThemeMode mode;
  bool useMaterial3;
  String color = "Blue";

  ThemeModel({this.mode = ThemeMode.system, this.useMaterial3 = true});

  ThemeModel copy({ThemeMode? mode, bool? useMaterial3}) => ThemeModel(
        mode: mode ?? this.mode,
        useMaterial3: useMaterial3 ?? this.useMaterial3,
      );

  Color get themeColor => ColorMapping.colors[color] ?? Colors.blue;
}

class AppConfiguration {
  static const String version = "1.4.0";

  ValueNotifier<bool> globalChange = ValueNotifier(false);

  ThemeModel _theme = ThemeModel();
  Locale? _language;

  //是否显示更新内容公告
  bool upgradeNoticeV40 = true;

  /// 是否启用画中画
  ValueNotifier<bool> pipEnabled = ValueNotifier(Platform.isAndroid);

  /// 显示画中画图标
  ValueNotifier<bool> pipIcon = ValueNotifier(Platform.isAndroid);

  /// Headers展示模式: table(逐行) / text(原始文本)
  String headerViewMode = "table";

  /// 底部导航栏
  bool bottomNavigation = true;

  /// 内存清理
  int? memoryCleanupThreshold;

  ///自动已读
  bool autoReadEnabled = true;

  /// 清空抓包前确认
  bool clearConfirm = false;

  /// 抓包列表行密度：comfortable(宽松，默认) / compact(紧凑) / dense(极紧凑)
  String captureListDensity = "comfortable";

  /// 代码窗口字体族（请求体/响应体/脚本编辑器等），null 或空表示跟随界面字体
  String? editorFontFamily;

  /// 代码窗口字号
  double editorFontSize = 13;

  /// 整体界面字体（不含代码窗口），null/空表示跟随系统默认字体
  String? appFontFamily;

  /// 整体界面字号缩放（0.85 - 1.25，1.0 = 原样）
  double appFontScale = 1.0;

  /// 整体界面密度：comfortable(默认) / compact / dense
  String uiDensity = "comfortable";

  //桌面window大小
  Size? windowSize;

  //桌面window位置
  Offset? windowPosition;

  //Windows保存窗口位置时使用的DPI比例
  double? windowPositionScale;

  //左侧面板占比
  double panelRatio = 0.3;

  /// 关闭窗口时最小化到系统托盘
  bool? minimizeToTray;

  /// 是否启用 MCP 服务
  bool mcpEnabled = false;

  /// 导出给 AI 时是否脱敏 Authorization/Cookie
  bool mcpRedactEnabled = true;

  /// 移动端 LAN 模式的访问 token（桌面 loopback 不用，留空即可）
  String? mcpToken;

  /// MCP 服务监听端口。为 null/非法时使用默认端口 9127，
  /// 被占用时由服务回退到系统随机端口。
  int? mcpPort;

  /// 桌面端工具栏已固定的快捷功能 id 列表
  static const List<String> defaultToolbarPins = ['requestRewrite', 'requestMap', 'script'];

  final ValueNotifier<List<String>> toolbarPins = ValueNotifier(defaultToolbarPins);

  /// 抓包列表可选的密度
  static const List<String> captureDensities = ["comfortable", "compact", "dense"];

  /// 抓包列表行的尺寸参数：由 [captureListDensity] 推导
  CaptureRowMetrics get captureRowMetrics {
    switch (captureListDensity) {
      case "compact":
        return const CaptureRowMetrics(
            leftWithDomain: 10,
            leftIndent: 22,
            leftSelection: 4,
            right: 8,
            top: 3,
            bottom: 3,
            titleSize: 12.5,
            metaSize: 10.5,
            titleMaxLines: 1,
            showMeta: true,
            gap: 1,
            iconGap: 8,
            iconWidth: 16,
            iconSize: 14,
            imageSize: 16);
      case "dense":
        return const CaptureRowMetrics(
            leftWithDomain: 8,
            leftIndent: 18,
            leftSelection: 3,
            right: 6,
            top: 1.5,
            bottom: 1.5,
            titleSize: 12,
            metaSize: 10,
            titleMaxLines: 1,
            showMeta: false,
            gap: 0,
            iconGap: 6,
            iconWidth: 14,
            iconSize: 12,
            imageSize: 14);
      default:
        return const CaptureRowMetrics(
            leftWithDomain: 12,
            leftIndent: 26,
            leftSelection: 6,
            right: 10,
            top: 7,
            bottom: 7,
            titleSize: 13,
            metaSize: 11,
            titleMaxLines: 2,
            showMeta: true,
            gap: 3,
            iconGap: 10,
            iconWidth: 18,
            iconSize: 16,
            imageSize: 19);
    }
  }

  /// 整体界面密度 → Flutter 的 VisualDensity
  VisualDensity get visualDensity {
    switch (uiDensity) {
      case "compact":
        return const VisualDensity(horizontal: -1, vertical: -1);
      case "dense":
        return const VisualDensity(horizontal: -2, vertical: -2);
      default:
        return VisualDensity.standard;
    }
  }

  /// 修改显示类配置后立即重建界面并落盘
  void applyDisplaySetting(VoidCallback mutate) {
    mutate();
    globalChange.value = !globalChange.value;
    flushConfig();
  }

  AppConfiguration._();

  /// 单例
  static AppConfiguration? _instance;

  static Future<AppConfiguration> get instance async {
    if (_instance == null) {
      try {
        AppConfiguration configuration = AppConfiguration._();
        await configuration.initConfig();
        _instance = configuration;
      } catch (e) {
        logger.e("load config error: $e");
        _instance = AppConfiguration._();
      }
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
    var color = ColorMapping.colors[colorName];
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
      return File('$userHome${Platform.pathSeparator}.proxypin${Platform.pathSeparator}ui_config.json');
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

      upgradeNoticeV40 = config['upgradeNoticeV40'] ?? true;
      _language = config['language'] == null
          ? null
          : Locale.fromSubtags(languageCode: config['language'], scriptCode: config['languageScript']);
      pipEnabled.value = config['pipEnabled'] ?? true;
      pipIcon.value = config['pipIcon'] ?? false;
      headerViewMode = config['headerViewMode'] ?? "table";
      bottomNavigation = config['bottomNavigation'] ?? true;
      memoryCleanupThreshold = config['memoryCleanupThreshold'];
      autoReadEnabled = config['autoReadEnabled'] ?? true;
      clearConfirm = config['clearConfirm'] ?? false;

      var density = config['captureListDensity'];
      captureListDensity = density is String && captureDensities.contains(density) ? density : "comfortable";

      var fontFamily = config['editorFontFamily'];
      editorFontFamily = fontFamily is String && fontFamily.trim().isNotEmpty ? fontFamily.trim() : null;
      var fontSize = config['editorFontSize'];
      editorFontSize = fontSize is num && fontSize >= 8 && fontSize <= 32 ? fontSize.toDouble() : 13;

      var appFont = config['appFontFamily'];
      appFontFamily = appFont is String && appFont.trim().isNotEmpty ? appFont.trim() : null;
      var appScale = config['appFontScale'];
      appFontScale = appScale is num && appScale >= 0.85 && appScale <= 1.25 ? appScale.toDouble() : 1.0;
      var uiDensityValue = config['uiDensity'];
      uiDensity = uiDensityValue is String && captureDensities.contains(uiDensityValue) ? uiDensityValue : "comfortable";

      windowSize =
          config['windowSize'] == null ? null : Size(config['windowSize']['width'], config['windowSize']['height']);
      windowPosition = config['windowPosition'] == null
          ? null
          : Offset(config['windowPosition']['dx'], config['windowPosition']['dy']);
      final positionScale = config['windowPositionScale'];
      windowPositionScale = positionScale is num ? positionScale.toDouble() : null;
      if (config['panelRatio'] != null) {
        panelRatio = config['panelRatio'];
      }
      minimizeToTray = config['minimizeToTray'];

      mcpEnabled = config['mcpEnabled'] ?? false;
      mcpRedactEnabled = config['mcpRedactEnabled'] ?? true;
      mcpToken = config['mcpToken'] as String?;
      var port = config['mcpPort'];
      mcpPort = port is int && port > 0 && port <= 65535 ? port : null;
      var pins = config['toolbarPins'];
      if (pins is List) {
        toolbarPins.value = pins.map((e) => e.toString()).toList();
      }
    } catch (e) {
      logger.e(e);
    }
  }

  /// 是否正在写入
  bool _isWriting = false;

  /// 刷新配置文件
  Future<void> flushConfig() async {
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
      'upgradeNoticeV40': upgradeNoticeV40,
      "language": _language?.languageCode,
      "languageScript": _language?.scriptCode,
      "headerViewMode": headerViewMode,
      "autoReadEnabled": autoReadEnabled,
      "clearConfirm": clearConfirm,
      "captureListDensity": captureListDensity,
      "editorFontFamily": editorFontFamily,
      "editorFontSize": editorFontSize,
      "appFontFamily": appFontFamily,
      "appFontScale": appFontScale,
      "uiDensity": uiDensity,
      if (memoryCleanupThreshold != null) 'memoryCleanupThreshold': memoryCleanupThreshold,
      if (Platforms.isMobile()) 'pipEnabled': pipEnabled.value,
      if (Platforms.isMobile()) 'pipIcon': pipIcon.value ? true : null,
      if (Platforms.isMobile()) 'bottomNavigation': bottomNavigation,
      if (Platforms.isDesktop())
        "windowSize": windowSize == null ? null : {"width": windowSize?.width, "height": windowSize?.height},
      if (Platforms.isDesktop())
        "windowPosition": windowPosition == null ? null : {"dx": windowPosition?.dx, "dy": windowPosition?.dy},
      if (Platform.isWindows) 'windowPositionScale': windowPositionScale,
      if (Platforms.isDesktop()) 'panelRatio': panelRatio,
      if (Platforms.isDesktop()) 'minimizeToTray': minimizeToTray,
      if (Platforms.isDesktop()) 'toolbarPins': toolbarPins.value,
      // MCP 配置所有平台都写入
      'mcpEnabled': mcpEnabled,
      'mcpRedactEnabled': mcpRedactEnabled,
      if (mcpToken != null) 'mcpToken': mcpToken,
      if (mcpPort != null) 'mcpPort': mcpPort,
    };
  }
}

/// 抓包列表行的尺寸参数（由 [AppConfiguration.captureListDensity] 推导）
class CaptureRowMetrics {
  final double leftWithDomain;
  final double leftIndent;
  final double leftSelection;
  final double right;
  final double top;
  final double bottom;
  final double titleSize;
  final double metaSize;
  final int titleMaxLines;
  final bool showMeta;
  final double gap;
  final double iconGap;
  final double iconWidth;
  final double iconSize;
  final double imageSize;

  const CaptureRowMetrics({
    required this.leftWithDomain,
    required this.leftIndent,
    required this.leftSelection,
    required this.right,
    required this.top,
    required this.bottom,
    required this.titleSize,
    required this.metaSize,
    required this.titleMaxLines,
    required this.showMeta,
    required this.gap,
    required this.iconGap,
    required this.iconWidth,
    required this.iconSize,
    required this.imageSize,
  });

  EdgeInsets padding({required bool displayDomain, required bool selectedInSelectionMode}) {
    final left = selectedInSelectionMode ? leftSelection : (displayDomain ? leftWithDomain : leftIndent);
    return EdgeInsets.only(left: left, right: right, top: top, bottom: bottom);
  }
}
