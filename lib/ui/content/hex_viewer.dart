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
import 'dart:async';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:proxypin/ui/component/code_forge/read_only_viewer.dart';
import 'package:proxypin/ui/component/search/search_controller.dart';

String _formatHexIsolate(Map<String, Object> args) => formatHex(args['data'] as List<int>, args['bytesPerRow'] as int);

// 与 CodeForge textStyle 的字号保持一致；code_forge 未显式设置 height 时行高倍率为 1.2。
const double _hexFontSize = 14;
const double _hexLineHeight = _hexFontSize * 1.2;

// 小于该字节数直接在主 isolate 同步格式化：compute 的 isolate 往返至少跨一帧，
// 小消息也走异步会在切换时闪一下 loading。超过阈值才进后台 isolate，避免大 body 阻塞 UI。
const int _syncFormatByteLimit = 128 * 1024;

// gutter 里显示的字节偏移统一用 8 位十六进制（0 起、每行 16 字节：00000000、00000010…），
// 足够覆盖 4GiB 数据；位数固定，滚动时 gutter 宽度不会随行数变化。
const int _offsetGutterDigits = 8;

// 行号槽与 Hex 正文之间的额外间距：gutter 内文字本身已近似贴右缘，再补一段留白避免拥挤。
const double _gutterSpacing = 12.0;

// 固定 gutter 宽度。code_forge 默认按「行数位数」估算首帧槽宽，gutterBuilder 生成的 8 位
// 偏移文本要等 paint 阶段才把槽宽撑大，首帧所有偏移会叠在窄槽里闪一下再跳正。这里按包内
// 撑宽公式（字符数 × 0.6em + 1em padding，见 code_area.dart）预算最终宽度，显式传入后
// 首帧即最终宽度；8 位定长文本也保证任何数据量下都放得下。
final double _gutterWidth = _offsetGutterDigits * _hexFontSize * 0.6 + _hexFontSize;

@visibleForTesting
String formatHex(List<int> data, int bytesPerRow) {
  final buffer = StringBuffer();
  for (int i = 0; i < data.length; i += bytesPerRow) {
    for (int j = 0; j < bytesPerRow; j++) {
      if (i + j < data.length) {
        buffer.write(data[i + j].toRadixString(16).padLeft(2, '0'));
      } else {
        buffer.write('  ');
      }
      buffer.write(' ');
    }

    buffer.write('    ');
    for (int j = 0; j < bytesPerRow && i + j < data.length; j++) {
      final byte = data[i + j];
      buffer.write(byte >= 32 && byte <= 126 ? String.fromCharCode(byte) : '.');
    }
    buffer.writeln();
  }
  return buffer.toString();
}

/// Hex 查看器：只负责字节数组 ↔ Hex 文本的格式化（含 128KiB 同步/isolate 阈值），
/// 控制器生命周期、搜索、高亮窗口化、滚动级联等通用能力由 [CodeForgeReadOnlyViewer] 承载。
class HexViewer extends StatefulWidget {
  final List<int> data;
  final int bytesPerRow;
  final SearchTextController searchController;

  /// 外层（header 所在）滚动视图的 controller。内部 Hex 滚到边后，剩余滚动量交给它，
  /// 实现 header ↔ body 级联；为 null 时不启用级联（如新窗口、请求编辑页等无外层滚动的场景）。
  final ScrollController? outerScrollController;

  /// 每次（重新）格式化都会把当前消息对应的 Future 回传，供父级获取完整 Hex 文本，
  /// 避免父级持有 GlobalKey（子树重挂载时 GlobalKey 容易出现多实例冲突）。
  final ValueChanged<Future<String>>? onFormattedText;

  const HexViewer({
    super.key,
    required this.data,
    this.bytesPerRow = 16,
    required this.searchController,
    this.outerScrollController,
    this.onFormattedText,
  });

  @override
  State<HexViewer> createState() => HexViewerState();
}

class HexViewerState extends State<HexViewer> {
  final GlobalKey<CodeForgeReadOnlyViewerState> _viewerKey = GlobalKey();

  // 缓存当前文档的两种载体：同步路径缓存 String 实例（跨 rebuild 身份稳定，
  // 避免内层按 identity 判断内容变化时误重载），异步路径缓存 isolate Future。
  String? _syncFormatted;
  late Future<String> _formattedText;

  @visibleForTesting
  CodeForgeController? get controller => _viewerKey.currentState?.controller;

  @visibleForTesting
  FindController? get findController => _viewerKey.currentState?.findController;

  @visibleForTesting
  FocusNode get editorFocusNode => _viewerKey.currentState!.editorFocusNode;

  @visibleForTesting
  ScrollController get scrollController => _viewerKey.currentState!.scrollController;

  @visibleForTesting
  Future<String> get formattedText => _formattedText;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant HexViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data) || oldWidget.bytesPerRow != widget.bytesPerRow) {
      _reload();
    }
  }

  void _reload() {
    final data = widget.data;
    if (data.length <= _syncFormatByteLimit) {
      // 小数据同步格式化并在同一帧挂载，切换消息时不出现 loading 闪烁。
      _syncFormatted = formatHex(data, widget.bytesPerRow);
      _formattedText = Future<String>.value(_syncFormatted!);
    } else {
      // 大数据进后台 isolate，避免大 body 的字符串拼接阻塞主线程。
      _syncFormatted = null;
      _formattedText = compute(_formatHexIsolate, {'data': data, 'bytesPerRow': widget.bytesPerRow});
    }
    widget.onFormattedText?.call(_formattedText);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final syncFormatted = _syncFormatted;
    // 同步路径传缓存的 String（身份稳定），异步路径传 isolate Future，内层据此显示 loading。
    // 不用条件表达式：String 与 Future<String> 的 LUB 是 Object，赋不回 FutureOr<String>。
    if (syncFormatted != null) {
      return _buildViewer(theme, syncFormatted);
    }
    return _buildViewer(theme, _formattedText);
  }

  CodeForgeReadOnlyViewer _buildViewer(ThemeData theme, FutureOr<String> text) {
    return CodeForgeReadOnlyViewer(
      key: _viewerKey,
      text: text,
      searchController: widget.searchController,
      outerScrollController: widget.outerScrollController,
      fontFamily: 'Courier',
      fontSize: _hexFontSize,
      lineHeight: _hexLineHeight,
      // gutter 不显示文档行号，改为每行首字节的偏移量（0 起的 8 位十六进制），
      // 与各 Hex 工具的惯例一致；每行固定 bytesPerRow 字节，按行号换算偏移即可。
      // 始终返回非 null：替换默认自增序号，渲染层据此把 gutter 宽度扩到完整宽度。
      gutterBuilder: GutterBuilder(
        builder: (lineNumber, lineText) =>
            ((lineNumber - 1) * widget.bytesPerRow).toRadixString(16).padLeft(_offsetGutterDigits, '0'),
      ),
      gutterStyle: GutterStyle(
        // 固定槽宽，避免 code_forge 首帧按行数估算窄槽、paint 阶段再撑宽造成的重叠闪烁。
        gutterWidth: _gutterWidth,
        // 与正文同为等宽字体；颜色由渲染层按当前行/非当前行覆盖（非当前行降透明度）。
        lineNumberStyle: TextStyle(
          fontFamily: 'Courier',
          fontSize: _hexFontSize,
          color: theme.colorScheme.onSurface,
        ),
        // 编辑器底色就是 surface，gutter 同色保持一体。
        backgroundColor: theme.colorScheme.surface,
        activeLineNumberColor: theme.colorScheme.onSurface,
        inactiveLineNumberColor: theme.colorScheme.onSurface.withValues(alpha: 120 / 255),
      ),
      gutterSpacing: _gutterSpacing,
      // Hex 不做语法高亮，只覆盖 root 配色；backgroundColor 用 surface 保证右键菜单不透明。
      editorTheme: {
        'root': TextStyle(
          fontFamily: 'Courier',
          fontSize: _hexFontSize,
          color: theme.colorScheme.onSurface,
          backgroundColor: theme.colorScheme.surface,
        ),
      },
    );
  }
}
