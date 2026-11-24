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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/code_forge/read_only_viewer.dart';
import 'package:proxypin/ui/component/search/search_controller.dart';
import 'package:proxypin/ui/component/search/virtualized_highlight_text.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/utils/css_formatter.dart';
import 'package:re_highlight/re_highlight.dart';

// 大 body 格式化进 isolate 的字符阈值，与 body.dart 旧文本路径的策略保持一致。
const int _isolateFormatThreshold = 10000;

// 超过该字符数的文档不再走 code_forge 软换行路径，与 body.dart 旧文本路径的
// VirtualizedHighlightText 阈值对齐：code_forge 不按视觉行虚拟化，换行模式挂载时
// 要对全文做定宽段落布局，512k 单条长行实测 15 秒（TextPainter 定宽布局本身 5 秒）。
const int _largeBodyThreshold = 100000;

// 单条逻辑行超过该字符数视为「超长行」：实测 5 万字符的定宽布局约 53ms，尚可接受；
// 10 万字符涨到 204ms，512k 达到 5 秒且被 code_forge 重复构建放大。含超长行的大文档
// 改走 code_forge 不换行快路径（512k 实测挂载约 350ms，长行横向滚动），而不是虚拟化回退
// （旧组件对单条 512k 长行仍要 4.7 秒，因为 Flutter 无法在单个段落内虚拟化视觉行）。
const int _overlongLineThreshold = 50000;

String _formatCssIsolate(Map<String, String> args) => CSS.pretty(args['body'] ?? '');

/// 纯文本不做任何处理。
String _identityFormat(String body) => body;

/// formUrl 解码：与旧路径一致用 Uri.decodeFull，遇到非法百分号编码（会抛 ArgumentError）
/// 时回退原文，保证畸形 body 也能展示而不是白屏。
String _decodeFormUrl(String body) {
  try {
    return Uri.decodeFull(body);
  } catch (_) {
    return body;
  }
}

/// 格式化后的纯文本类 body 查看器：负责解码与格式化（含小数据同步/大数据 isolate 的阈值），
/// 渲染与搜索等通用能力交给 [CodeForgeReadOnlyViewer]。已用于 CSS（重型、带高亮）、
/// 纯文本 Text（identity、无高亮）与 formUrl（URL 解码、无高亮）；
/// 后续 XML/JS/HTML 迁移时按各自 formatter/language 扩展即可。
///
/// 缓存按消息身份失效：body 区每帧可能重建，缓存保证传给底层的 String/Future 身份稳定，
/// 不会被误判为内容变化而重载（切换消息或解码态产生新实例时自动重建）。
class FormattedCodeViewer extends StatefulWidget {
  final HttpMessage message;

  /// re_highlight 语法模式；null 为纯文本。
  final Mode? language;

  /// 同步格式化函数；小 body 在主 isolate 调用。超过 [_isolateFormatThreshold] 且
  /// [isolateFormatter] 非空时才进后台 isolate；为空（纯文本/URL 解码等线性轻量处理）
  /// 时始终同步格式化，避免无谓的 isolate 往返与 loading 闪烁。
  final String Function(String body) formatter;

  /// isolate 入口（顶层函数或静态方法），与 [formatter] 行为一致；null 表示永不进 isolate。
  final String Function(Map<String, String> args)? isolateFormatter;

  /// 自动换行：纯文本/表单视图为 true（延续旧 SelectableText 的软换行，不出现横向滚动），
  /// CSS 等代码视图为 false（长行横向滚动）。
  final bool lineWrap;

  /// 是否启用大文档分流（超过 [_largeBodyThreshold] 时强制不换行或回退虚拟化组件）。
  /// 纯文本/表单视图开启；CSS 等代码视图关闭，始终用 code_forge（本就不换行，无卡死路径）。
  final bool enableLargeBodyFallback;

  final SearchTextController searchController;
  final ScrollController? outerScrollController;

  const FormattedCodeViewer({
    super.key,
    required this.message,
    required this.language,
    required this.formatter,
    this.isolateFormatter,
    this.lineWrap = false,
    this.enableLargeBodyFallback = false,
    required this.searchController,
    this.outerScrollController,
  });

  /// 纯文本 tab：不做格式化、不做语法高亮，仅把原文交给 code_forge 只读查看器。
  /// 自动换行，与旧 SelectableText 的软换行行为一致，不产生横向滚动。
  factory FormattedCodeViewer.text({
    Key? key,
    required HttpMessage message,
    required SearchTextController searchController,
    ScrollController? outerScrollController,
  }) {
    return FormattedCodeViewer(
      key: key,
      message: message,
      language: null,
      formatter: _identityFormat,
      lineWrap: true,
      enableLargeBodyFallback: true,
      searchController: searchController,
      outerScrollController: outerScrollController,
    );
  }

  /// formUrl（URL Decode）tab：Uri.decodeFull 解码，非法编码回退原文，无语法高亮。
  /// 解码是线性轻量处理，不进 isolate（与旧路径的同步行为一致），同帧挂载无 loading。
  /// 自动换行，与旧 SelectableText 的软换行行为一致。
  factory FormattedCodeViewer.formUrl({
    Key? key,
    required HttpMessage message,
    required SearchTextController searchController,
    ScrollController? outerScrollController,
  }) {
    return FormattedCodeViewer(
      key: key,
      message: message,
      language: null,
      formatter: _decodeFormUrl,
      lineWrap: true,
      enableLargeBodyFallback: true,
      searchController: searchController,
      outerScrollController: outerScrollController,
    );
  }

  /// CSS tab 的便捷构造。
  factory FormattedCodeViewer.css({
    Key? key,
    required HttpMessage message,
    required Mode? language,
    required SearchTextController searchController,
    ScrollController? outerScrollController,
  }) {
    return FormattedCodeViewer(
      key: key,
      message: message,
      language: language,
      formatter: CSS.pretty,
      isolateFormatter: _formatCssIsolate,
      searchController: searchController,
      outerScrollController: outerScrollController,
    );
  }

  @override
  State<FormattedCodeViewer> createState() => _FormattedCodeViewerState();
}

// 大文档的渲染路径。
enum _LargeBodyMode {
  // 常规：code_forge，按调用方的 lineWrap 决定是否软换行。
  normal,
  // 含超长行的大文档：code_forge 强制不换行（长行横向滚动），避开定宽段落布局的卡死成本。
  codeForgeNoWrap,
  // 行都正常但总量超大的文档：回退按行虚拟化的旧组件，挂载成本与行数无关。
  virtualized,
}

class _FormattedCodeViewerState extends State<FormattedCodeViewer> {
  int? _messageIdentity;
  // 同步就绪时缓存 String（身份稳定，底层同帧挂载无 loading）；否则缓存格式化 Future。
  String? _syncContent;
  Future<String>? _contentFuture;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant FormattedCodeViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.message, widget.message)) {
      _resolve();
    }
  }

  void _resolve() {
    _messageIdentity = identityHashCode(widget.message);
    _syncContent = null;
    _contentFuture = null;

    final message = widget.message;
    // 只有 zstd 的解码是异步的；gzip/br/deflate 在 getBodyString 内同步完成。
    if (message.headers.contentEncoding == 'zstd') {
      _contentFuture = message.decodeBodyString().then((body) => widget.formatter(body));
      return;
    }

    final body = message.getBodyString();
    final isolateFormatter = widget.isolateFormatter;
    // 无 isolate 入口（纯文本/URL 解码等轻量处理）或小数据：同步格式化并同帧挂载，
    // 切换消息时不出现 loading 闪烁；只有重型格式化（如 CSS.pretty）的大 body 才进 isolate。
    if (isolateFormatter == null || body.length < _isolateFormatThreshold) {
      _syncContent = widget.formatter(body);
    } else {
      _contentFuture = compute(isolateFormatter, {'body': body});
    }
  }

  // 仅在大文档（超过 _largeBodyThreshold）上扫描，判断是否含超长行。用换行符位置增量计算，
  // 一旦发现超长行立即返回，避免对全文做 split 分配；扫描本身是 O(n) 单次遍历。
  bool _hasOverlongLine(String content) {
    var lineStart = 0;
    while (true) {
      final nl = content.indexOf('\n', lineStart);
      final lineEnd = nl < 0 ? content.length : nl;
      if (lineEnd - lineStart >= _overlongLineThreshold) return true;
      if (nl < 0) return false;
      lineStart = nl + 1;
    }
  }

  _LargeBodyMode _modeFor(String content) {
    if (!widget.enableLargeBodyFallback ||
        widget.language != null ||
        content.length <= _largeBodyThreshold) {
      return _LargeBodyMode.normal;
    }
    return _hasOverlongLine(content)
        ? _LargeBodyMode.codeForgeNoWrap
        : _LargeBodyMode.virtualized;
  }

  @override
  Widget build(BuildContext context) {
    // 防御：build 中发现消息已切换（理论上 didUpdateWidget 已处理），按新消息重算。
    if (_messageIdentity != identityHashCode(widget.message)) {
      _resolve();
    }
    final syncContent = _syncContent;
    if (syncContent != null) {
      return _buildResolved(syncContent);
    }
    // 异步内容（zstd 解码或 isolate 格式化）：完成前显示加载指示，完成后按文档形态分流。
    return FutureBuilder<String>(
      future: _contentFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SizedBox(height: 240, child: Center(child: Text('Code viewer unavailable: ${snapshot.error}')));
        }
        if (!snapshot.hasData) {
          return const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()));
        }
        return _buildResolved(snapshot.data!);
      },
    );
  }

  Widget _buildResolved(String content) {
    final mode = _modeFor(content);
    if (mode == _LargeBodyMode.virtualized) {
      // 与迁移前 body.dart 的 >10 万字符路径一致：按行虚拟化、不软换行。
      // 自带共享搜索、外层滚动级联和 SelectionArea 右键菜单（含解码器/AES，移动端也有）。
      return VirtualizedHighlightText(
        text: content,
        searchController: widget.searchController,
        scrollController: widget.outerScrollController,
      );
    }
    return _buildCodeForge(content, forceNoWrap: mode == _LargeBodyMode.codeForgeNoWrap);
  }

  Widget _buildCodeForge(String text, {required bool forceNoWrap}) {
    return CodeForgeReadOnlyViewer(
      text: text,
      language: widget.language,
      // 含超长行的大文档强制不换行；常规文档沿用调用方的软换行设置。
      lineWrap: forceNoWrap ? false : widget.lineWrap,
      searchController: widget.searchController,
      outerScrollController: widget.outerScrollController,
      // 恢复旧 SelectableText 右键菜单的“发送到解码器 / AES 解密”：取选中文本，无选区回退全文。
      contextMenuItemsBuilder: (controller) => codeForgeSendToToolItems(context, () {
        final selection = controller.selection;
        if (selection.isValid &&
            !selection.isCollapsed &&
            selection.start >= 0 &&
            selection.end <= controller.text.length) {
          return controller.text.substring(selection.start, selection.end);
        }
        return controller.text;
      }),
    );
  }
}
