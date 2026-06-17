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
  int _lastRenderedMatchIndex = -1;
  int _lastKnownMatchCount = -1;
  String _lastSearchSignature = '';
  bool _searchUpdateScheduled = false;
  int _scrollRequestId = 0;

  // 缓存机制，避免重复计算
  HighlightTextDocument? _cachedDocument;
  String? _cachedText;
  SearchSettings? _cachedSearchSettings;
  int? _cachedEffectiveChunkLines;
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
    final viewHeight = widget.height ?? max(240, MediaQuery.sizeOf(context).height - 210);

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

        final shouldRebuildDocument = _cachedText != widget.text || _cachedSearchSettings != newSearchSettings;
        // 搜索激活时切换为逐行虚拟化，保证自动滚动能精确定位到匹配行。
        final effectiveChunkLines = widget.searchController.shouldSearch() ? 1 : widget.chunkLines;

        if (shouldRebuildDocument || _cachedEffectiveChunkLines != effectiveChunkLines) {
          _cachedDocument = HighlightTextDocument.create(
            context,
            text: widget.text,
            language: widget.language,
            style: widget.style,
            searchController: widget.searchController,
          );
          _cachedText = widget.text;
          _cachedSearchSettings = newSearchSettings;
          _cachedEffectiveChunkLines = effectiveChunkLines;
          // 清除旧的块缓存
          _chunkSpanCache.clear();
          // 重新分块
          chunks = _buildChunks(_cachedDocument!, effectiveChunkLines);
          // 搜索文档重建后重置滚动状态，确保首次匹配也会触发自动跳转
          _lastScrolledMatchIndex = -1;
          _lastRenderedMatchIndex = -1;
        }

        final currentMatch = widget.searchController.currentMatchIndex.value;
        if (currentMatch != _lastRenderedMatchIndex) {
          // 当前匹配变化时，清理块渲染缓存，确保高亮样式同步到最新匹配项
          _chunkSpanCache.clear();
          _lastRenderedMatchIndex = currentMatch;
        }

        _updateSearchState(_cachedDocument!);

        return _buildList(viewHeight, chunks, (index) {
          final chunk = chunks[index];
          final chunkSpans = _chunkSpanCache.putIfAbsent(
            index,
                () => _buildSpansForChunk(
              context,
              _cachedDocument!,
              chunk,
              currentMatchIndex: widget.searchController.currentMatchIndex.value,
            ),
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
          padding: const EdgeInsets.only(bottom: 10),
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
    if (_searchUpdateScheduled) {
      return;
    }
    _searchUpdateScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchUpdateScheduled = false;
      if (!mounted) return;
      // 使用缓存的文档，确保使用最新的数据
      final cachedDoc = _cachedDocument;
      if (cachedDoc == null) return;

      final settings = widget.searchController.value;
      final searchSignature = '${settings.pattern}|${settings.isCaseSensitive}|${settings.isRegExp}';
      if (searchSignature != _lastSearchSignature || cachedDoc.totalMatchCount != _lastKnownMatchCount) {
        _lastSearchSignature = searchSignature;
        _lastKnownMatchCount = cachedDoc.totalMatchCount;
        _lastScrolledMatchIndex = -1;
      }

      widget.searchController.updateMatchCount(cachedDoc.totalMatchCount);
      final currentMatch = widget.searchController.currentMatchIndex.value;
      if (!widget.searchController.shouldSearch() || cachedDoc.totalMatchCount == 0) {
        return;
      }

      if (currentMatch != _lastScrolledMatchIndex && currentMatch >= 0) {
        _scheduleScrollToCurrentMatch(cachedDoc);
      }
    });
  }

  void _scheduleScrollToCurrentMatch(HighlightTextDocument document) {
    final requestId = ++_scrollRequestId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || requestId != _scrollRequestId) {
        return;
      }
      _scrollToCurrentMatch(document, requestId);
    });
  }

  Future<void> _scrollToCurrentMatch(HighlightTextDocument document, int requestId, [int attempt = 0]) async {
    if (!mounted || requestId != _scrollRequestId) {
      return;
    }

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

    // 直接通过行号计算块索引（更简单可靠）
    final chunkLines = _cachedEffectiveChunkLines ?? widget.chunkLines;
    final chunkIndex = (lineIndex ~/ max(1, chunkLines)).clamp(0, chunks.length - 1);

    // 计算匹配行在块内的位置（用于计算 alignment）
    final chunk = chunks[chunkIndex];
    if (chunk.lineCount <= 0) {
      return;
    }
    final lineOffsetInChunk = (lineIndex - chunk.startLineIndex).clamp(0, chunk.lineCount - 1);
    final chunkLineCount = max(1, chunk.lineCount);

    // alignment: 把匹配行放在块的相对位置上，限制在 [0.1, 0.9] 避免太靠边
    double alignment = (lineOffsetInChunk + 0.5) / chunkLineCount;
    alignment = alignment.clamp(0.1, 0.9);

    // 如果 itemScrollController 尚未 attach，则延迟一帧重试一次
    if (!itemScrollController.isAttached) {
      if (attempt >= 7) {
        logger.w('VirtualizedHighlightText scroll aborted: itemScrollController not attached');
        return;
      }
      await Future<void>.delayed(Duration(milliseconds: 16 * (attempt + 1)));
      return _scrollToCurrentMatch(document, requestId, attempt + 1);
    }

    try {
      await itemScrollController.scrollTo(
        index: chunkIndex,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: alignment,
      );

      // 只在滚动成功后更新 lastScrolled，避免失败后丢失同一索引的重试机会。
      _lastScrolledMatchIndex = matchIndex;
    } catch (e) {
      logger.w('VirtualizedHighlightText scroll failed: $e');
      if (attempt >= 5) {
        _lastScrolledMatchIndex = -1;
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
      return _scrollToCurrentMatch(document, requestId, attempt + 1);
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
      {required int currentMatchIndex}
      ) {
    final spans = <InlineSpan>[];

    for (var i = chunk.startLineIndex; i < chunk.endLineIndex; i++) {
      if (i >= document.lines.length) break;

      spans.addAll(document.buildSpansForLine(context, i, currentMatchIndexOverride: currentMatchIndex));

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
