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
import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/ui/component/search/finder.dart';
import 'package:proxypin/utils/highlight_languages.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xml/xml.dart';

/// XML 查看 / 格式化工具
/// 跟 [JsonViewerPage] 风格一致，但只有文本视图：
/// XML 缺少现成的 tree 组件，且通常嵌套不深，编辑器配合美化已经够用。
///
/// @author Hongen Wang
class XmlViewerPage extends StatefulWidget {
  final String? windowId;
  final String? initialText;

  const XmlViewerPage({super.key, this.windowId, this.initialText});

  @override
  State<XmlViewerPage> createState() => _XmlViewerPageState();
}

class _XmlViewerPageState extends State<XmlViewerPage> {
  late final CodeForgeController _controller;

  /// 编辑器自动换行；CodeForge 的 lineWrap 是 late final，切换需要靠新的 key 重建组件，
  /// controller 在本 State 持有，重建不会丢文本与撤销栈。
  bool _wrap = true;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _controller = CodeForgeController()..text = widget.initialText ?? '';

    if (Platforms.isDesktop() && widget.windowId != null) {
      HardwareKeyboard.instance.addHandler(_onKeyEvent);
    }
  }

  @override
  void dispose() {
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

  /// 不复用 [XML.pretty]：那个工具吞掉解析错误，我们这里希望失败有反馈。
  void _format() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    try {
      final pretty = XmlDocument.parse(text).toXmlString(pretty: true, indent: '  ');
      if (pretty != text) _controller.text = pretty;
    } on XmlException catch (e) {
      _toast('${localizations.fail}: ${e.message}');
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
  }

  Future<void> _openFile() async {
    String? path;
    try {
      if (Platform.isMacOS && widget.windowId != null) {
        path = await DesktopMultiWindow.invokeMainWindowMethod("pickFiles");
        WindowController.fromWindowId(widget.windowId!).show();
      } else {
        final result = await FilePicker.pickFiles(type: FileType.any);
        path = result?.files.single.path;
      }
    } catch (_) {
      // 某些平台（e.g. Linux）custom + extensions 可能抛错，回退到任意类型
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
      final file = XFile.fromData(utf8.encode(text), mimeType: 'application/xml');
      RenderBox? box;
      if (await Platforms.isIpad() && mounted) {
        box = context.findRenderObject() as RenderBox?;
      }
      await SharePlus.instance.share(
          ShareParams(files: [file], fileNameOverrides: const ['data.xml'], sharePositionOrigin: box?.paintBounds));
      return;
    }

    String? path;
    if (Platform.isMacOS && widget.windowId != null) {
      path = await DesktopMultiWindow.invokeMainWindowMethod("saveFile", {"fileName": "data.xml"});
      WindowController.fromWindowId(widget.windowId!).show();
    } else {
      path = await FilePicker.saveFile(fileName: 'data.xml');
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
    bool isNewWindows = widget.windowId != null && Platform.isWindows;

    return Scaffold(
      appBar: isNewWindows
          ? null
          : PreferredSize(
              preferredSize: Platforms.isDesktop() ? const Size.fromHeight(23) : const Size.fromHeight(36),
              child: AppBar(
                title: Text("XML Viewer", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w300)),
                centerTitle: true,
              ),
            ),
      body: Column(children: [
        Align(alignment: Alignment.centerRight, child: _toolbar()),
        const Divider(height: 1, thickness: 0.3),
        Expanded(child: _textView()),
      ]),
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
          _iconBtn(Icons.delete_outline, localizations.clear, _clear),
          _iconBtn(Icons.auto_fix_high, localizations.format, _format),
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
          // CodeForge 的 lineWrap 是 late final，切换换行靠新 key 重建；
          // controller 在 State 里复用，文本不会丢。
          key: ValueKey('xml-editor-wrap-$_wrap'),
          controller: _controller,
          lineWrap: _wrap,
          language: HighlightLanguages.getLanguage(ContentType.xml),
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
