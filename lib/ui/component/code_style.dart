import 'package:flutter/material.dart';
import 'package:proxypin/ui/configuration.dart';

/// 代码窗口（请求体/响应体/脚本编辑器/JSON 视图…）统一使用的字体样式。
///
/// 字体族与字号来自偏好设置里的「代码字体」，未设置时跟随界面字体，
/// 保证不填也能保持原有观感。
TextStyle codeTextStyle({double? size, Color? color, double? height, FontWeight? fontWeight}) {
  final config = AppConfiguration.current;
  final family = config?.editorFontFamily;
  return TextStyle(
    fontFamily: family == null || family.isEmpty ? null : family,
    fontSize: size ?? config?.editorFontSize ?? 13,
    height: height,
    color: color,
    fontWeight: fontWeight,
  );
}

/// 当前生效的代码字号（供需要单独计算的场景使用）
double get codeFontSize => AppConfiguration.current?.editorFontSize ?? 13;
