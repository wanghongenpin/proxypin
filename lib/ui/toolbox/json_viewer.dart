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

import 'dart:convert';
import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/json/json_viewer.dart' as proxy_json;
import 'package:proxypin/ui/component/json/theme.dart';
import 'package:proxypin/ui/component/search/finder.dart';
import 'package:proxypin/utils/highlight_languages.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:share_plus/share_plus.dart';

/// JSON 查看 / 格式化工具
/// @author Hongen Wang
class JsonViewerPage extends StatefulWidget {
  final int? windowId;
  final String? initialText;

  const JsonViewerPage({super.key, this.windowId, this.initialText});

  @override
  State<JsonViewerPage> createState() => _JsonViewerPageState();
}

class _JsonViewerPageState extends State<JsonViewerPage> with SingleTickerProviderStateMixin {
  late final CodeForgeController _controller;
  late final TabController _tabs;

  dynamic _parsed;

  String? _parseError;

  /// `_parsed` 对应的源文本快照；
  String? _parsedSource;

  /// 编辑器自动换行；CodeForge 的 lineWrap 是 late final，
  bool _wrap = true;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _controller = CodeForgeController()..text = widget.initialText ?? '';
    _tabs = TabController(length: 2, vsync: this);

    if (Platforms.isDesktop() && widget.windowId != null) {
      HardwareKeyboard.instance.addHandler(_onKeyEvent);
    }
    _tabs.addListener(() {
      if (_tabs.index == 1) {
        _reparse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _tabs.dispose();
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

  void _reparse() {
    final text = _controller.text.trim();
    if (text == _parsedSource) return;
    _parsedSource = text;

    if (text.isEmpty) {
      if (_parsed != null || _parseError != null) {
        _parsed = null;
        _parseError = null;
      }
      return;
    }
    try {
      final value = jsonDecode(text);
      _parsed = value;
      _parseError = null;
    } on FormatException catch (e, st) {
      logger.w('JSON parse error: ${e.message} at ${e.offset}', error: e, stackTrace: st);
      // 失败时清掉旧的解析结果，让树视图显示错误
      setState(() {
        _parsed = null;
        _parseError = e.toString();
      });
    }
  }

  // ---------- 操作 ----------
  void _format() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    try {
      final pretty = const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
      if (pretty != text) _controller.text = pretty;
    } on FormatException catch (e) {
      _toast('${localizations.fail}: $e');
    }
  }

  void _compact() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    try {
      final compact = jsonEncode(jsonDecode(text));
      if (compact != text) _controller.text = compact;
    } on FormatException catch (e) {
      _toast('${localizations.fail}: $e');
    }
  }

  void _copy() {
    final text = _controller.text;
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    _toast(localizations.copied);
  }

  void _clear() {
    if (_controller.text.isEmpty) return;
    _controller.text = '';
    // 切到 Tree tab 时再 reparse；这里直接清掉缓存让树视图立即显示空状态
    setState(() {
      _parsed = null;
      _parseError = null;
      _parsedSource = '';
    });
  }

  Future<void> _openFile() async {
    String? path;
    try {
      if (Platform.isMacOS && widget.windowId != null) {
        path = await DesktopMultiWindow.invokeMethod(0, "pickFiles");
        WindowController.fromWindowId(widget.windowId!).show();
      } else {
        final result = await FilePicker.pickFiles(type: FileType.any);
        path = result?.files.single.path;
      }
    } catch (_) {
      // 某些平台 (e.g. Linux) custom + extensions 可能抛错，回退到任意类型
      final result = await FilePicker.pickFiles();
      path = result?.files.single.path;
    }

    if (path == null) return;
    try {
      final content = await File(path).readAsString();
      _controller.text = content;
    } catch (e) {
      _toast('${localizations.fail}: $e');
    }
  }

  Future<void> _download() async {
    final text = _controller.text;
    if (text.isEmpty) return;

    if (Platforms.isMobile()) {
      // 手机端通过系统分享面板让用户选择保存位置
      final file = XFile.fromData(utf8.encode(text), mimeType: 'application/json');
      RenderBox? box;
      if (await Platforms.isIpad() && mounted) {
        box = context.findRenderObject() as RenderBox?;
      }
      await SharePlus.instance.share(
          ShareParams(files: [file], fileNameOverrides: const ['data.json'], sharePositionOrigin: box?.paintBounds));
      return;
    }

    String? path;
    if (Platform.isMacOS && widget.windowId != null) {
      path = await DesktopMultiWindow.invokeMethod(0, "saveFile", {"fileName": "data.json"});
      WindowController.fromWindowId(widget.windowId!).show();
    } else {
      path = await FilePicker.saveFile(fileName: 'data.json');
    }
    if (path == null) return;
    try {
      await File(path).writeAsString(text);
      if (mounted) _toast(localizations.saveSuccess);
    } catch (e) {
      _toast('${localizations.fail}: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    FlutterToastr.show(msg, context, duration: 3);
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final body = Column(children: [
      Align(alignment: Alignment.centerRight, child: _toolbar()),
      const Divider(height: 1, thickness: 0.3),
      TabBar(
        controller: _tabs,
        isScrollable: false,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        indicatorSize: TabBarIndicatorSize.label,
        tabs: [
          Tab(text: localizations.text, height: 36),
          const Tab(text: 'Tree', height: 36),
        ],
      ),
      Expanded(
        // 用 IndexedStack 让两个视图同时挂载，切回 Text 时编辑器不会丢光标 / 滚动位置
        child: AnimatedBuilder(
          animation: _tabs,
          builder: (_, __) => IndexedStack(
            index: _tabs.index,
            children: [
              _textView(),
              _treeView(),
            ],
          ),
        ),
      ),
    ]);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Platforms.isDesktop() ? const Size.fromHeight(23) : const Size.fromHeight(36),
        child: AppBar(
            title: Text("JSON Viewer", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w300)),
            centerTitle: true),
      ),
      body: body,
    );
  }

  Widget _toolbar() {
    final color = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.only(top: 2, bottom: 2, right: 12),
      child: Wrap(
        spacing: 0,
        runSpacing: 0,
        children: [
          _iconBtn(Icons.folder_open, localizations.selectFile, _openFile),
          _iconBtn(Icons.auto_fix_high, localizations.format, _format),
          _iconBtn(Icons.compress, localizations.compact, _compact),
          _iconBtn(
            Icons.wrap_text,
            localizations.wordWrap,
            () => setState(() => _wrap = !_wrap),
            tint: _wrap ? color : null,
          ),
          _iconBtn(Icons.copy, localizations.copy, _copy),
          _iconBtn(Icons.delete_outline, localizations.clear, _clear),
          _iconBtn(Icons.file_download_outlined, localizations.download, _download),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap, {Color? tint}) {
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
          controller: _controller,
          lineWrap: _wrap,
          language: HighlightLanguages.getLanguage(ContentType.json),
          enableGuideLines: false,
          editorTheme: editorTheme,
          textStyle: const TextStyle(fontSize: 13),
          finderBuilder: (c, controller) => FindPanelView(controller: controller),
          selectionStyle: CodeSelectionStyle(cursorColor: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }

  Widget _treeView() {
    if (_parseError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '${localizations.fail}: $_parseError',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_parsed == null) {
      return Center(
        child: Text(
          localizations.localeName == 'zh' ? '请输入或打开 JSON' : 'Paste or open a JSON file',
          style: TextStyle(color: Theme.of(context).hintColor),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: SelectionArea(child: proxy_json.JsonViewer(_parsed, colorTheme: ColorTheme.of(context))),
    );
  }
}
