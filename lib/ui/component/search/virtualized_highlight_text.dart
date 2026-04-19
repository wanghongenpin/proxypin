import 'dart:math';

import 'package:flutter/material.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/search/highlight_text_document.dart';
import 'package:proxypin/ui/component/search/search_controller.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:scrollable_positioned_list_nic/scrollable_positioned_list_nic.dart';

class VirtualizedHighlightText extends StatefulWidget {
  final String text;
  final String? language;
  final TextStyle? style;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final SearchTextController searchController;
  final ScrollController? scrollController;
  final double? height;
  final int chunkLines;

  const VirtualizedHighlightText({
    super.key,
    required this.text,
    this.language,
    this.style,
    this.contextMenuBuilder,
    required this.searchController,
    this.scrollController,
    this.height,
    this.chunkLines = 80,
  });

  @override
  State<VirtualizedHighlightText> createState() => _VirtualizedHighlightTextState();
}

class _VirtualizedHighlightTextState extends State<VirtualizedHighlightText> {
  final ItemScrollController itemScrollController = ItemScrollController();
  ScrollController? trackingScrollController;
  int _lastScrolledMatchIndex = -1;

  // 缓存机制，避免重复计算
  HighlightTextDocument? _cachedDocument;
  String? _cachedText;
  SearchSettings? _cachedSearchSettings;
  late final Map<int, List<InlineSpan>> _chunkSpanCache;
  late List<HighlightDocumentChunk> chunks;

  @override
  void initState() {
    super.initState();
    _chunkSpanCache = {};
    // 初始化chunks为空列表，避免late未初始化错误
    chunks = [];
  }

  @override
  void dispose() {
    trackingScrollController?.dispose();
    _chunkSpanCache.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewHeight = widget.height ?? max(240, MediaQuery.sizeOf(context).height - 220);

    return AnimatedBuilder(
      animation: widget.searchController,
      builder: (context, child) {
        // 只在文本或搜索参数（模式、大小写敏感性、正则表达式）变化时重新创建document
        // 不在currentMatchIndex变化时重新创建，以避免频繁rebuild
        final newSearchSettings = SearchSettings(
          isCaseSensitive: widget.searchController.value.isCaseSensitive,
          isRegExp: widget.searchController.value.isRegExp,
          pattern: widget.searchController.value.pattern,
          currentMatchIndex: 0, // 忽略currentMatchIndex用于比较
        );

        final shouldRebuildDocument =
          _cachedText != widget.text ||
          _cachedSearchSettings != newSearchSettings;

        if (shouldRebuildDocument) {
          _cachedDocument = HighlightTextDocument.create(
            context,
            text: widget.text,
            language: widget.language,
            style: widget.style,
            searchController: widget.searchController,
          );
          _cachedText = widget.text;
          _cachedSearchSettings = newSearchSettings;
          // 清除旧的块缓存
          _chunkSpanCache.clear();
          // 重新分块
          chunks = _buildChunks(_cachedDocument!, widget.chunkLines);
        }

        _updateSearchState(_cachedDocument!);

        return _buildList(viewHeight, chunks, (index) {
          final chunk = chunks[index];
          final chunkSpans = _chunkSpanCache.putIfAbsent(
            index,
            () => _buildSpansForChunk(context, _cachedDocument!, chunk),
          );
          return Text.rich(TextSpan(children: chunkSpans));
        });
      },
    );
  }

  Widget _buildList<T>(double viewHeight, List<T> items, Widget Function(int) itemBuilder) {
    // 根据文本块大小动态调整缓存范围，避免过度缓存导致的内存和CPU消耗
    // 缓存范围应该是视口高度的2-3倍
    final estimatedItemHeight = 24.0; // 粗略估计单行高度（monospace）
    final itemsInView = max(3, (viewHeight / estimatedItemHeight).ceil());
    final minCacheExtent = estimatedItemHeight * itemsInView * 2;

    return SizedBox(
      width: double.infinity,
      height: viewHeight,
      child: SelectionArea(
        child: ScrollablePositionedList.builder(
          key: const ValueKey('virtualized-highlight-text'),
          physics: Platforms.isDesktop() ? null : const BouncingScrollPhysics(),
          scrollController: Platforms.isDesktop() ? null : _trackingScroll(),
          itemScrollController: itemScrollController,
          minCacheExtent: minCacheExtent,
          itemCount: items.length,
          itemBuilder: (context, index) {
            return Container(
              key: ValueKey('virtualized-code-chunk-$index'),
              child: itemBuilder(index),
            );
          },
        ),
      ),
    );
  }

  void _updateSearchState(HighlightTextDocument document) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 使用缓存的文档，确保使用最新的数据
      final cachedDoc = _cachedDocument;
      if (cachedDoc == null) return;

      widget.searchController.updateMatchCount(cachedDoc.totalMatchCount);
      final currentMatch = widget.searchController.currentMatchIndex.value;
      if (currentMatch != _lastScrolledMatchIndex && currentMatch >= 0) {
        _lastScrolledMatchIndex = currentMatch;
        _scrollToCurrentMatch(cachedDoc);
      }
    });
  }

  Future<void> _scrollToCurrentMatch(HighlightTextDocument document) async {
    // 防守性检查：确保所有条件都满足才进行滚动
    if (document.totalMatchCount == 0 || chunks.isEmpty) {
      return;
    }

    // 必须从 searchController 获取最新的匹配索引，
    // 因为 document.currentMatchIndex 是创建时的快照，缓存后不会更新
    final matchIndex = widget.searchController.currentMatchIndex.value;
    final lineIndex = document.lineIndexForMatch(matchIndex);

    if (lineIndex == null || lineIndex < 0) {
      return;
    }

    // 根据行索引找到对应的块索引
    // 找到包含该行的块
    int chunkIndex = -1;
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      // 检查该行是否在这个块的范围内
      if (lineIndex >= chunk.startLineIndex && lineIndex < chunk.endLineIndex) {
        chunkIndex = i;
        break;
      }
    }

    // 如果没找到（lineIndex超出所有块范围，防守性编程），使用最后一个块
    if (chunkIndex == -1) {
      chunkIndex = max(0, chunks.length - 1);
    }

    if (!itemScrollController.isAttached) {
      return;
    }

    try {
      await itemScrollController.scrollTo(
        index: chunkIndex,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: 0.45,
      );
    } catch (e) {
      logger.w('VirtualizedHighlightText scroll failed: $e');
    }
  }

  ScrollController _trackingScroll() {
    if (trackingScrollController != null) {
      return trackingScrollController!;
    }

    trackingScrollController = trackingScroll(widget.scrollController) ?? TrackingScrollController();
    return trackingScrollController!;
  }

  /// 将行分组为块，每块包含指定数量的行
  List<HighlightDocumentChunk> _buildChunks(HighlightTextDocument document, int chunkLines) {
    final chunks = <HighlightDocumentChunk>[];
    final allLines = document.lines;

    for (var i = 0; i < allLines.length; i += chunkLines) {
      final endIndex = min(i + chunkLines, allLines.length);
      chunks.add(HighlightDocumentChunk(
        startLineIndex: i,
        endLineIndex: endIndex,
      ));
    }

    return chunks.isEmpty ? [HighlightDocumentChunk(startLineIndex: 0, endLineIndex: 0)] : chunks;
  }

  /// 为指定块构建 InlineSpan 列表
  List<InlineSpan> _buildSpansForChunk(
    BuildContext context,
    HighlightTextDocument document,
    HighlightDocumentChunk chunk,
  ) {
    final spans = <InlineSpan>[];

    for (var i = chunk.startLineIndex; i < chunk.endLineIndex; i++) {
      if (i >= document.lines.length) break;

      spans.addAll(document.buildSpansForLine(context, i));

      // 在行之间添加换行符
      if (i < chunk.endLineIndex - 1) {
        spans.add(TextSpan(text: '\n', style: document.rootStyle));
      }
    }

    return spans;
  }
}

/// 文本块的定义，用于虚拟化渲染
class HighlightDocumentChunk {
  final int startLineIndex;
  final int endLineIndex;

  HighlightDocumentChunk({
    required this.startLineIndex,
    required this.endLineIndex,
  });

  int get lineCount => endLineIndex - startLineIndex;
}
