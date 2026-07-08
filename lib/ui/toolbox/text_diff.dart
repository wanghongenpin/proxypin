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

import 'dart:io';

import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/flutter_compat.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:proxypin/utils/text_diff.dart';

/// 文本对比工具
/// - 左右两个 CodeForge 输入；
/// - 点对比后差异直接在原文 / 新文上染色（删行红、增行绿），无单独结果区；
/// - 用户开始编辑任一侧时清空高亮，避免行号错位误导。
///
/// @author Hongen Wang
class TextDiffPage extends StatefulWidget {
  final String? windowId;
  final String? initialLeft;
  final String? initialRight;

  const TextDiffPage({super.key, this.windowId, this.initialLeft, this.initialRight});

  @override
  State<TextDiffPage> createState() => _TextDiffPageState();
}

class _TextDiffPageState extends State<TextDiffPage> {
  late final TextEditingController _left;
  late final TextEditingController _right;

  bool _wrap = true;
  String? _summary;

  /// 上一次对比时左右文本的快照；用来判断 listener 收到的变化是不是真改了文本。
  String _leftSnapshot = '';
  String _rightSnapshot = '';

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _left = TextEditingController(text: widget.initialLeft ?? '');
    _right = TextEditingController(text: widget.initialRight ?? '');
    _left.addListener(_onLeftChanged);
    _right.addListener(_onRightChanged);

    if (Platforms.isDesktop() && widget.windowId != null) {
      HardwareKeyboard.instance.addHandler(_onKeyEvent);
    }
  }

  @override
  void dispose() {
    _left.removeListener(_onLeftChanged);
    _right.removeListener(_onRightChanged);
    _left.dispose();
    _right.dispose();
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
      WindowController.fromWindowId(widget.windowId!).invokeMethod('window_close');
      return true;
    }
    return false;
  }

  void _onLeftChanged() {
    if (_left.text == _leftSnapshot) return; // 选区 / 滚动等非文本变化忽略
    _onTextChange();
  }

  void _onRightChanged() {
    if (_right.text == _rightSnapshot) return;
    _onTextChange();
  }

  bool textChanged = false;

  void _onTextChange() {
    if (textChanged) return;
    textChanged = true;
    Future.delayed(const Duration(milliseconds: 1500), () {
      _compare();
      textChanged = false;
    });
  }

  // ---------- 操作 ----------
  void _compare() {
    if (_left.text.isEmpty && _right.text.isEmpty) return;
    final diffs = diffLines(_left.text, _right.text);

    var inserts = 0, deletes = 0;
    for (final d in diffs) {
      switch (d.type) {
        case LineDiffType.equal:
          break;
        case LineDiffType.delete:
          deletes++;
          break;
        case LineDiffType.insert:
          inserts++;
          break;
      }
    }

    _leftSnapshot = _left.text;
    _rightSnapshot = _right.text;

    setState(() {
      if (inserts == 0 && deletes == 0) {
        _summary = localizations.diffIdentical;
      } else {
        _summary = localizations.diffSummary(inserts, deletes);
      }
    });
  }

  /// 累计 \n 偏移得到每行起始处的全文 utf16 offset。下标 0-based。
  static List<int> _lineStartOffsets(String text) {
    final offsets = <int>[0];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) offsets.add(i + 1);
    }
    return offsets;
  }

  /// 清掉两侧高亮，但保留文本内容。
  void _clearHighlights() {
    if (_summary == null) return;
    // flutter_code_editor 0.3.5 不支持行高亮装饰，
    // 这里简化处理，只重置摘要状态。
    setState(() => _summary = null);
  }

  void _clearAll() {
    if (_left.text.isEmpty && _right.text.isEmpty) return;
    _left.text = '';
    _right.text = '';
    _clearHighlights();
  }

  /// 文件选择填到指定一侧。macOS 子窗口走父进程 IPC，跟 Json/Xml 工具一致。
  Future<void> _openFileInto(TextEditingController target) async {
    String? path;
    try {
      if (Platform.isMacOS && widget.windowId != null) {
        path = await DesktopMultiWindow.invokeMethod(0, "pickFiles");
        WindowController.fromWindowId(widget.windowId!).show();
      } else {
        final result = await FilePicker.platform.pickFiles(type: FileType.any);
        path = result?.files.single.path;
      }
    } catch (_) {
      final result = await FilePicker.platform.pickFiles();
      path = result?.files.single.path;
    }

    if (path == null) return;
    try {
      final content = await File(path).readAsString();
      target.text = content;
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
          title: Text(localizations.textDiff, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w300)),
          centerTitle: true,
        ),
      ),
      body: Column(children: [
        Align(alignment: Alignment.centerRight, child: _toolbar()),
        const Divider(height: 1, thickness: 0.3),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 800 是经验阈值：再窄左右两个编辑器单独宽度不够，堆叠更舒服。
              final wide = constraints.maxWidth >= 800;
              return wide ? _wideLayout() : _narrowLayout();
            },
          ),
        ),
        if (_summary != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(_summary!, style: const TextStyle(fontSize: 14)),
          ),
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
          _iconBtn(Icons.compare_arrows, localizations.compare, _onTextChange),
          _iconBtn(Icons.delete_outline, localizations.clear, _clearAll),
          _iconBtn(
            Icons.wrap_text,
            localizations.wordWrap,
                () => setState(() => _wrap = !_wrap),
            tint: _wrap ? color : null,
          ),
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

  Widget _wideLayout() {
    return Row(children: [
      Expanded(child: _editor(_left, localizations.diffOriginal, isLeft: true)),
      const VerticalDivider(width: 1, thickness: 0.3),
      Expanded(child: _editor(_right, localizations.diffChanged, isLeft: false)),
    ]);
  }

  Widget _narrowLayout() {
    return Column(children: [
      Expanded(child: _editor(_left, localizations.diffOriginal, isLeft: true)),
      const Divider(height: 1, thickness: 0.3),
      Expanded(child: _editor(_right, localizations.diffChanged, isLeft: false)),
    ]);
  }

  Widget _editor(TextEditingController controller, String title, {required bool isLeft}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(children: [
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const Spacer(),
          IconButton(
            tooltip: localizations.selectFile,
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.folder_open),
            onPressed: () => _openFileInto(controller),
          ),
        ]),
      ),
      Expanded(
        child: Container(
          margin: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor)),
          child: TextField(
            key: ValueKey('diff-$title-$_wrap'),
            controller: controller,
            maxLines: null,
            expands: true,
            style: const TextStyle(fontSize: 14.5),
            cursorColor: Theme.of(context).colorScheme.primary,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(8),
            ),
          ),
        ),
      ),
    ]);
  }
}
