import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';

/// Converts a highlight theme map to CodeThemeData
CodeThemeData codeThemeFromHighlight(Map<String, TextStyle> highlightTheme) {
  return CodeThemeData(styles: highlightTheme);
}

/// Wraps a CodeField with the appropriate theme widget
Widget codeFieldWithTheme({
  required CodeField codeField,
  required Map<String, TextStyle> theme,
}) {
  return CodeTheme(
    data: codeThemeFromHighlight(theme),
    child: codeField,
  );
}

/// Common themes
Map<String, TextStyle> get atomOneDark => atomOneDarkTheme;

Map<String, TextStyle> get atomOneLight => atomOneLightTheme;

Map<String, TextStyle> get monokaiSublime => monokaiSublimeTheme;
