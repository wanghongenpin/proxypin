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
/// - 左右两个文本编辑器输入；
/// - 点对比后差异直接在原文 / 新文上染色（删行红、增行绿），无单独结果区；
/// - 用户开始编辑任一侧后自动重新对比，避免行号错位误导。
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
  late final _DiffTextController _left;
  late final _DiffTextController _right;

  bool _wrap = true;
  String? _summary;

  /// 上一次对比时左右文本的快照；用来判断 listener 收到的变化是不是真改了文本。
  String _leftSnapshot = '';
  String _rightSnapshot = '';

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _left = _DiffTextController(text: widget.initialLeft ?? '');
    _right = _DiffTextController(text: widget.initialRight ?? '');
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
    // TextField 不能随编辑自动迁移装饰范围，先清掉旧高亮，稍后重新计算。
    _leftSnapshot = _left.text;
    _rightSnapshot = _right.text;
    _left.clearHighlights();
    _right.clearHighlights();
    if (_summary != null) setState(() => _summary = null);

    if (textChanged) return;
    textChanged = true;
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) _compare();
      textChanged = false;
    });
  }

  // ---------- 操作 ----------
  void _compare() {
    if (_left.text.isEmpty && _right.text.isEmpty) return;
    final diffs = diffLines(_left.text, _right.text);
    final leftLineStarts = _lineStartOffsets(_left.text);
    final rightLineStarts = _lineStartOffsets(_right.text);
    final leftHighlights = <_DiffHighlight>[];
    final rightHighlights = <_DiffHighlight>[];

    const deleteLine = TextStyle(backgroundColor: Color(0x2EE53935));
    const insertLine = TextStyle(backgroundColor: Color(0x2E43A047));
    const deleteChars = TextStyle(backgroundColor: Color(0xCCE53935));
    const insertChars = TextStyle(backgroundColor: Color(0xCC43A047));

    var inserts = 0, deletes = 0;
    for (final d in diffs) {
      switch (d.type) {
        case LineDiffType.equal:
          break;
        case LineDiffType.delete:
          deletes++;
          final start = leftLineStarts[d.leftLine! - 1];
          leftHighlights.add(_DiffHighlight(start, start + d.text.length, deleteLine));
          break;
        case LineDiffType.insert:
          inserts++;
          final start = rightLineStarts[d.rightLine! - 1];
          rightHighlights.add(_DiffHighlight(start, start + d.text.length, insertLine));
          break;
      }
    }

    // 紧邻的删除 / 新增行再计算字符差异，深底色叠加在整行浅底色上。
    final pairedDeleteLines = <int>{};
    final pairedInsertLines = <int>{};
    for (var k = 0; k + 1 < diffs.length; k++) {
      final a = diffs[k];
      final b = diffs[k + 1];
      LineDiff? deleted, inserted;
      if (a.type == LineDiffType.delete && b.type == LineDiffType.insert) {
        deleted = a;
        inserted = b;
      } else if (a.type == LineDiffType.insert && b.type == LineDiffType.delete) {
        deleted = b;
        inserted = a;
      }
      if (deleted == null || inserted == null) continue;

      final leftLine = deleted.leftLine! - 1;
      final rightLine = inserted.rightLine! - 1;
      if (pairedDeleteLines.contains(leftLine) || pairedInsertLines.contains(rightLine)) continue;

      final chars = diffChars(deleted.text, inserted.text);
      final leftOffset = leftLineStarts[leftLine];
      final rightOffset = rightLineStarts[rightLine];
      for (final range in chars.leftRanges) {
        if (range.start == range.end) continue;
        leftHighlights.add(_DiffHighlight(leftOffset + range.start, leftOffset + range.end, deleteChars));
      }
      for (final range in chars.rightRanges) {
        if (range.start == range.end) continue;
        rightHighlights.add(_DiffHighlight(rightOffset + range.start, rightOffset + range.end, insertChars));
      }
      pairedDeleteLines.add(leftLine);
      pairedInsertLines.add(rightLine);
    }

    _leftSnapshot = _left.text;
    _rightSnapshot = _right.text;
    _left.updateHighlights(leftHighlights);
    _right.updateHighlights(rightHighlights);

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
    if (_summary == null && !_left.hasHighlights && !_right.hasHighlights) return;
    _left.clearHighlights();
    _right.clearHighlights();
    setState(() => _summary = null);
  }

  void _clearAll() {
    if (_left.text.isEmpty && _right.text.isEmpty) return;
    _left.text = '';
    _right.text = '';
    _clearHighlights();
  }

  /// 文件选择填到指定一侧。macOS 子窗口走父进程 IPC，跟 Json/Xml 工具一致。
  Future<void> _openFileInto(_DiffTextController target) async {
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
      Expanded(child: _editor(_left, localizations.diffOriginal)),
      const VerticalDivider(width: 1, thickness: 0.3),
      Expanded(child: _editor(_right, localizations.diffChanged)),
    ]);
  }

  Widget _narrowLayout() {
    return Column(children: [
      Expanded(child: _editor(_left, localizations.diffOriginal)),
      const Divider(height: 1, thickness: 0.3),
      Expanded(child: _editor(_right, localizations.diffChanged)),
    ]);
  }

  Widget _editor(_DiffTextController controller, String title) {
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

class _DiffTextController extends TextEditingController {
  _DiffTextController({super.text});

  List<_DiffHighlight> _highlights = const [];

  bool get hasHighlights => _highlights.isNotEmpty;

  void updateHighlights(List<_DiffHighlight> highlights) {
    _highlights = highlights;
    notifyListeners();
  }

  void clearHighlights() {
    if (_highlights.isEmpty) return;
    _highlights = const [];
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (_highlights.isEmpty || text.isEmpty) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }

    // 在整行与字符范围的边界切分 TextSpan，按顺序合并样式。
    final boundaries = <int>{0, text.length};
    for (final highlight in _highlights) {
      boundaries.add(highlight.start.clamp(0, text.length));
      boundaries.add(highlight.end.clamp(0, text.length));
    }
    final offsets = boundaries.toList()..sort();
    final children = <TextSpan>[];
    for (var i = 0; i + 1 < offsets.length; i++) {
      final start = offsets[i];
      final end = offsets[i + 1];
      if (start == end) continue;
      TextStyle? spanStyle = style;
      for (final highlight in _highlights) {
        if (highlight.start <= start && highlight.end >= end) {
          spanStyle = spanStyle == null ? highlight.style : spanStyle.merge(highlight.style);
        }
      }
      children.add(TextSpan(style: spanStyle, text: text.substring(start, end)));
    }
    return TextSpan(style: style, children: children);
  }
}

class _DiffHighlight {
  final int start;
  final int end;
  final TextStyle style;

  const _DiffHighlight(this.start, this.end, this.style);
}
