/*
 * Copyright 2026 Hongen Wang All rights reserved.
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

// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/component/search/finder.dart';
import 'package:proxypin/utils/css_formatter.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/http.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xml/xml.dart';

/// 文本编辑工具：CodeForge 编辑器 + 多语言高亮切换。
///
/// 跟 [JsonViewerPage] / [XmlViewerPage] 走相同的工具栏 + 控件套路；
/// 区别是 body 不带格式化（语言种类多，不是每种都通用），多了一个语言选择下拉。
///
/// @author Hongen Wang
class TextEditorPage extends StatefulWidget {
  final String? windowId;
  final String? initialText;

  const TextEditorPage({super.key, this.windowId, this.initialText});

  @override
  State<TextEditorPage> createState() => _TextEditorPageState();
}

/// 下拉里的语言项：显示名 + re_highlight Mode；Plain Text 用 null mode。
class _LangOption {
  final String label;
  final Mode? mode;

  const _LangOption(this.label, this.mode);
}

final List<_LangOption> _langs = [
  _LangOption('Plain Text', null),
  _LangOption('HTTP', langHttp),
  _LangOption('JSON', langJson),
  _LangOption('XML / HTML', langXml),
  _LangOption('JavaScript', langJavascript),
  _LangOption('TypeScript', langTypescript),
  _LangOption('CSS', langCss),
  _LangOption('SQL', langSql),
  _LangOption('YAML', langYaml),
  _LangOption('Markdown', langMarkdown),
  _LangOption('Bash', langBash),
  _LangOption('Python', langPython),
  _LangOption('Java', langJava),
  _LangOption('Go', langGo),
  _LangOption('Dart', langDart),
];

class _TextEditorPageState extends State<TextEditorPage> {
  late final CodeForgeController _controller;
  late final FindController _findController;

  bool _wrap = true;
  _LangOption _lang = _langs.first;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _controller = CodeForgeController()..text = widget.initialText ?? '';
    // 自己持有 FindController：CodeForge 默认会在 initState 创一个内部 controller，
    // 但拿不到引用，没法从工具栏 toggle 搜索面板。显式传一个进去就能控制。
    _findController = FindController(_controller);
    if (Platforms.isDesktop() && widget.windowId != null) {
      HardwareKeyboard.instance.addHandler(_onKeyEvent);
    }
  }

  @override
  void dispose() {
    _findController.dispose();
    _controller.dispose();
    if (Platforms.isDesktop() && widget.windowId != null) {
      HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    }
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    if (widget.windowId == null) return false;
    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      HardwareKeyboard.instance.removeHandler(_onKeyEvent);
      WindowController.fromWindowId(widget.windowId!).close();
      return true;
    }
    return false;
  }

  // ---------- 操作 ----------

  void _copy() {
    final text = _controller.text;
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    _toast(localizations.copied);
  }

  void _clear() {
    if (_controller.text.isEmpty) return;
    _controller.text = '';
  }

  /// 是否支持格式化：JSON / XML / HTML / CSS。
  /// 其他语言要引入重型 formatter，不在范围内——按钮在 UI 上禁用。
  bool get _canFormat => _lang.label == 'JSON' || _lang.label == 'XML / HTML' || _lang.label == 'CSS';

  /// 按当前语言格式化。失败时通过 toast 显示原因，不修改原文。
  void _format() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    switch (_lang.label) {
      case 'JSON':
        try {
          final pretty = JSON.pretty(text);
          if (pretty != text) _controller.text = pretty;
        } catch (e) {
          _toast('${localizations.fail}: $e');
        }
      case 'XML / HTML':
        try {
          // 不复用 utils/xml_formatter 的 XML.pretty：那个工具吞掉解析错误，
          // 这里希望失败有反馈。
          final pretty = XmlDocument.parse(text).toXmlString(pretty: true, indent: '  ');
          if (pretty != text) _controller.text = pretty;
        } on XmlException catch (e) {
          _toast('${localizations.fail}: ${e.message}');
        }
      case 'CSS':
        // CSS.pretty 内部 try/catch 失败时返回原文——非破坏性，不再额外加 toast。
        final pretty = CSS.pretty(text);
        if (pretty != text) _controller.text = pretty;
    }
  }

  Future<void> _openFile() async {
    String? path;
    try {
      final result = await FilePicker.pickFiles(type: FileType.any);
      path = result?.files.single.path;
    } catch (_) {
      final result = await FilePicker.pickFiles();
      path = result?.files.single.path;
    }

    if (path == null) return;
    try {
      final content = await File(path).readAsString();
      _controller.text = content;
      _autoDetectLanguage(path);
    } catch (e) {
      logger.w('Failed to open file: ', error: e);
      _toast('${localizations.fail}: $e');
    }
  }

  /// 按文件后缀粗略命中语言；只是个便利项，命中失败保持当前选择。
  void _autoDetectLanguage(String path) {
    final ext = path.split('.').last.toLowerCase();
    const map = {
      'http': 'HTTP',
      'rest': 'HTTP',
      'json': 'JSON',
      'xml': 'XML / HTML',
      'html': 'XML / HTML',
      'htm': 'XML / HTML',
      'js': 'JavaScript',
      'mjs': 'JavaScript',
      'ts': 'TypeScript',
      'tsx': 'TypeScript',
      'css': 'CSS',
      'sql': 'SQL',
      'yaml': 'YAML',
      'yml': 'YAML',
      'md': 'Markdown',
      'markdown': 'Markdown',
      'sh': 'Bash',
      'bash': 'Bash',
      'py': 'Python',
      'java': 'Java',
      'go': 'Go',
      'dart': 'Dart',
    };
    final label = map[ext];
    if (label == null) return;
    final hit = _langs.where((l) => l.label == label).firstOrNull;
    if (hit != null && hit != _lang) {
      setState(() => _lang = hit);
    }
  }

  Future<void> _download() async {
    final text = _controller.text;
    if (text.isEmpty) return;

    if (Platforms.isMobile()) {
      final file = XFile.fromData(utf8.encode(text), mimeType: 'text/plain');
      RenderBox? box;
      if (await Platforms.isIpad() && mounted) {
        box = context.findRenderObject() as RenderBox?;
      }
      await SharePlus.instance.share(
          ShareParams(files: [file], fileNameOverrides: const ['text.txt'], sharePositionOrigin: box?.paintBounds));
      return;
    }

    String? path = await FilePicker.saveFile(fileName: 'text.txt', bytes: utf8.encode(text));
    if (path == null) return;
    if (mounted) _toast(localizations.saveSuccess);
  }

  void _toast(String msg) {
    if (!mounted) return;
    FlutterToastr.show(msg, context, duration: 3);
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    bool isNewWindows = widget.windowId != null && Platform.isWindows;

    return Scaffold(
      appBar: isNewWindows
          ? null
          : PreferredSize(
              preferredSize: Platforms.isDesktop() ? const Size.fromHeight(23) : const Size.fromHeight(36),
              child: AppBar(
                  title:
                      Text(localizations.textEditor, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w300)),
                  centerTitle: true),
            ),
      body: Column(children: [
        _toolbar(),
        const Divider(height: 1, thickness: 0.3),
        Expanded(child: _textView()),
      ]),
    );
  }

  Widget _toolbar() {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.only(top: 2, bottom: 2, left: 8, right: 12),
      child: Row(children: [
        SizedBox(width: 6),
        // 语言下拉
        DropdownButton<_LangOption>(
          value: _lang,
          isDense: true,
          underline: const SizedBox.shrink(),
          icon: const Icon(Icons.arrow_drop_down, size: 18),
          items: _langs
              .map((l) => DropdownMenuItem(value: l, child: Text(l.label, style: const TextStyle(fontSize: 12.5))))
              .toList(),
          onChanged: (v) {
            if (v == null || v == _lang) return;
            setState(() => _lang = v);
          },
        ),
        const Spacer(),
        Wrap(
          spacing: 0,
          runSpacing: 0,
          children: [
            _iconBtn(Icons.folder_open, localizations.selectFile, _openFile),
            _iconBtn(Icons.delete_outline, localizations.clear, _clear),
            _iconBtn(Icons.auto_fix_high, localizations.format, _canFormat ? _format : null),
            _iconBtn(Icons.search, localizations.search, _findController.toggleActive),
            _iconBtn(
              Icons.wrap_text,
              localizations.wordWrap,
              () => setState(() => _wrap = !_wrap),
              tint: _wrap ? color : null,
            ),
            _iconBtn(Icons.copy, localizations.copy, _copy),
            _iconBtn(Icons.file_download_outlined, localizations.download, _download),
          ],
        ),
      ]),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback? onTap, {Color? tint}) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 17, color: tint),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _textView() {
    final isDark = Theme.brightnessOf(context) == Brightness.dark;
    final baseTheme = isDark ? atomOneDarkTheme : atomOneLightTheme;
    final pageBg = Theme.of(context).colorScheme.surface;
    final editorTheme = isDark
        ? {
            ...baseTheme,
            'root': const TextStyle(color: Color(0xffabb2bf)).copyWith(backgroundColor: pageBg),
          }
        : baseTheme;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.black12)),
        child: CodeForge(
          // CodeForge 的 language / lineWrap 是 late final，切换得新 key 重建；
          // controller / findController 在 State 持有，重建不丢文本、搜索状态、撤销栈。
          key: ValueKey('text-editor-${_lang.label}-$_wrap'),
          controller: _controller,
          findController: _findController,
          lineWrap: _wrap,
          language: _lang.mode,
          enableGuideLines: false,
          editorTheme: editorTheme,
          textStyle: const TextStyle(fontSize: 13),
          finderBuilder: (c, controller) => FindPanelView(controller: controller),
          selectionStyle: CodeSelectionStyle(cursorColor: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }
}
