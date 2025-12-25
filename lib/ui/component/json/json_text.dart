/*
 * Copyright 2023 Hongen Wang All rights reserved.
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
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/json/theme.dart';
import 'package:proxypin/ui/component/search/search_controller.dart';
import 'package:proxypin/utils/font.dart';
import 'package:scrollable_positioned_list_nic/scrollable_positioned_list_nic.dart';

import '../../../utils/platform.dart';

class JsonText extends StatefulWidget {
  final ColorTheme colorTheme;
  final dynamic json;
  final String indent;
  final ScrollController? scrollController;
  final SearchTextController? searchController;

  const JsonText({
    super.key,
    required this.json,
    this.indent = '  ',
    required this.colorTheme,
    this.scrollController,
    this.searchController,
  });

  @override
  State<JsonText> createState() => _JsonTextState();
}

class _JsonTextState extends State<JsonText> {
  ScrollController? trackingScrollController;
  SearchTextController? searchController;
  final ItemScrollController itemScrollController = ItemScrollController();

  @override
  void initState() {
    super.initState();
    searchController = widget.searchController;
  }

  @override
  void dispose() {
    trackingScrollController?.dispose();
    trackingScrollController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (searchController == null) {
      return jsonTextWidget(context);
    }
    return AnimatedBuilder(
      animation: searchController!,
      builder: (context, child) {
        return jsonTextWidget(context);
      },
    );
  }

  Widget jsonTextWidget(BuildContext context) {
    var jsonParser = JsonParser(widget.json, widget.colorTheme, widget.indent, searchController);
    var textList = jsonParser.getJsonTree();
    List<List<TextSpan>>? chunks;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      searchController?.updateMatchCount(jsonParser.searchMatchTotal);
      // 自动滚动到当前高亮项
      scrollToMatch(jsonParser, chunks);
    });

    if (textList.length < 1000) {
      return SelectableText.rich(TextSpan(children: textList), showCursor: true);
    } else {
      chunks = chunks ?? splitTextSpans(textList, 500);
      return SizedBox(
          width: double.infinity,
          height: MediaQuery.of(context).size.height - 160,
          child: SelectionArea(
              child: ScrollablePositionedList.builder(
            physics: Platforms.isDesktop() ? null : const BouncingScrollPhysics(),
            scrollController: Platforms.isDesktop() ? null : trackingScroll(),
            itemCount: chunks.length,
            minCacheExtent: 1500,
            itemScrollController: itemScrollController,
            itemBuilder: (BuildContext context, int index) {
              return Text.rich(
                TextSpan(children: chunks![index]),
                textHeightBehavior:
                    const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                strutStyle: const StrutStyle(forceStrutHeight: true, height: 1.393),
                style: TextStyle(fontFamily: fonts.regular),
              );
            },
          )));
    }
  }

  Future<void> scrollToMatch(JsonParser jsonParser, [List<List<TextSpan>>? chunks]) async {
    if (searchController == null || jsonParser.matchKeys.isEmpty) return;
    final index = searchController!.currentMatchIndex.value;
    if (index < 0 || index >= jsonParser.matchKeys.length) return;

    final key = jsonParser.matchKeys[index];

    if (key.currentContext != null) {
      await _ensureVisibleCenter(key, const Duration(milliseconds: 260));
      return;
    }

    // Chunk-first path for large documents
    if (chunks != null && chunks.isNotEmpty) {
      final chunkIndex = _findChunkIndexForKey(chunks, key);
      if (chunkIndex != -1) {
        /// 滚动到对应 chunk
        try {
          await itemScrollController.scrollTo(
            index: chunkIndex,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            alignment: 0.0,
          );
        } catch (_) {
          logger.w('Scroll to chunk $chunkIndex failed');
        }

        for (int i = 0; i < 10 && key.currentContext == null; i++) {
          await Future.delayed(Duration(milliseconds: 40));
        }

        await _ensureVisibleCenter(key, const Duration(milliseconds: 130));
        return;
      }
    }
  }

  Future<void> _ensureVisibleCenter(GlobalKey key, Duration duration) async {
    final ctx = key.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(ctx, duration: duration, alignment: 0.5);
    }
  }

  // 在分块数据中定位包含目标 key 的 chunk 下标
  int _findChunkIndexForKey(List<List<TextSpan>> chunks, GlobalKey key) {
    for (int i = 0; i < chunks.length; i++) {
      for (final span in chunks[i]) {
        if (_textSpanContainsKey(span, key)) return i;
      }
    }
    return -1;
  }

  // 递归检查 TextSpan 树是否包含对应 key 的 WidgetSpan
  bool _textSpanContainsKey(TextSpan span, GlobalKey key) {
    final children = span.children;
    if (children == null || children.isEmpty) return false;
    for (final child in children) {
      if (child is WidgetSpan) {
        final w = child.child;
        if (w is Text && w.key == key) return true;
      } else if (child is TextSpan) {
        if (_textSpanContainsKey(child, key)) return true;
      }
    }
    return false;
  }

  // 优化分块：避免因为 Text 组件分隔导致额外空行
  List<List<TextSpan>> splitTextSpans(List<TextSpan> spans, int chunkSize) {
    if (spans.length <= chunkSize) {
      return [spans];
    }

    List<List<TextSpan>> chunks = [];

    bool endsWithNewline(TextSpan s) => s.text != null && s.text!.endsWith('\n');
    bool startsWithNewline(TextSpan s) => s.text != null && s.text!.startsWith('\n');

    for (int i = 0; i < spans.length; i += chunkSize) {
      final chunk = spans.sublist(i, (i + chunkSize < spans.length) ? i + chunkSize : spans.length);

      if (chunk.isEmpty) continue;

      if (i > 0) {
        // 对非首块：去掉首 span 的一个前导换行抵消组件分隔换行
        final first = chunk.first;
        if (startsWithNewline(first)) {
          final newText = first.text!.substring(1);
          chunk[0] = TextSpan(text: newText, style: first.style, children: first.children);
        }
      }

      if (chunk.length > 1 && endsWithNewline(chunk.last)) {
        // 除最后一块外，块尾不保留以 \n 结尾的 span（把它挪到下一块）
        final last = chunk.last;
        final newText = last.text!.substring(0, last.text!.length - 1);
        chunk[chunk.length - 1] = TextSpan(text: newText, style: last.style, children: last.children);
      }

      chunks.add(chunk);
    }
    return chunks;
  }

  /// 滚动条控制：保证 ListView/SingleChildScrollView 使用同一个控制器，便于动画
  ScrollController trackingScroll() {
    if (trackingScrollController != null) {
      return trackingScrollController!;
    }

    var trackingScroll = TrackingScrollController();
    ScrollController? scrollController = widget.scrollController;

    double prevOffset = 0;
    trackingScroll.addListener(() {
      // iOS 回弹或向上轻微滑动时，驱动外部滚动条联动
      if (trackingScroll.offset < -10 || (trackingScroll.offset < 30 && trackingScroll.offset < prevOffset)) {
        if (scrollController != null && scrollController.offset >= 50) {
          scrollController.jumpTo(scrollController.offset - max((prevOffset - trackingScroll.offset), 10));
        }
      }
      prevOffset = trackingScroll.offset;
    });

    if (Platform.isIOS && scrollController != null) {
      scrollController.addListener(() {
        if (scrollController.offset >= scrollController.position.maxScrollExtent) {
          scrollController.jumpTo(scrollController.position.maxScrollExtent);
          trackingScroll
              .jumpTo(trackingScroll.offset + (scrollController.offset - scrollController.position.maxScrollExtent));
        }
      });
    }

    trackingScrollController = trackingScroll;
    return trackingScroll;
  }
}

class JsonParser {
  final dynamic json;
  final ColorTheme colorTheme;
  final String indent;
  final SearchTextController? searchController;
  int searchMatchTotal = 0;
  final List<GlobalKey> matchKeys = [];

  JsonParser(this.json, this.colorTheme, this.indent, this.searchController);

  int getLength() {
    if (json is Map) {
      return json.length;
    } else if (json is List) {
      return json.length;
    } else {
      return json == null ? 0 : json.toString().length;
    }
  }

  List<TextSpan> getJsonTree() {
    matchKeys.clear(); // 每次渲染前清空
    List<TextSpan> textList = [];
    if (json is Map) {
      textList.add(const TextSpan(text: '{ \n'));
      textList.addAll(getMapText(json, prefix: indent));
    } else if (json is List) {
      textList.add(const TextSpan(text: '[ \n'));
      textList.addAll(getArrayText(json));
    } else {
      textList.add(TextSpan(text: json == null ? '' : json.toString()));
      textList.add(const TextSpan(text: '\n'));
    }
    return textList;
  }

  /// 获取Map json
  List<TextSpan> getMapText(Map<String, dynamic> map,
      {String openPrefix = '', String prefix = '', String suffix = ''}) {
    var result = <TextSpan>[];

    var entries = map.entries;
    for (int i = 0; i < entries.length; i++) {
      var entry = entries.elementAt(i);
      String postfix = '${i == entries.length - 1 ? '' : ','} ';

      var textSpan = TextSpan(text: prefix, children: [
        ..._highlightMatches('"${entry.key}"', textColor: colorTheme.propertyKey),
        const TextSpan(text: ': '),
        getBasicValue(entry.value, postfix),
      ]);
      result.add(textSpan);
      result.add(const TextSpan(text: '\n'));

      if (entry.value is Map<String, dynamic>) {
        result.addAll(getMapText(entry.value, openPrefix: prefix, prefix: '$prefix$indent', suffix: postfix));
      } else if (entry.value is List) {
        result.addAll(getArrayText(entry.value, openPrefix: prefix, prefix: '$prefix$indent', suffix: postfix));
      }
    }

    result.add(TextSpan(text: '$openPrefix}$suffix  \n'));
    return result;
  }

  /// 获取数组json
  List<TextSpan> getArrayText(List<dynamic> list, {String openPrefix = '', String prefix = '', String suffix = ''}) {
    var result = <TextSpan>[];
    // result.add(TextSpan(text: '$openPrefix[ \n'));

    for (int i = 0; i < list.length; i++) {
      var value = list[i];
      String postfix = i == list.length - 1 ? '' : ',';

      result.add(getBasicValue(value, postfix, prefix: prefix));
      result.add(const TextSpan(text: '\n'));

      if (value is Map<String, dynamic>) {
        result.addAll(getMapText(value, openPrefix: '$openPrefix ', prefix: '$prefix$indent', suffix: postfix));
      } else if (value is List) {
        result.addAll(getArrayText(value, openPrefix: '$openPrefix ', prefix: '$prefix$indent', suffix: postfix));
      }
    }

    result.add(TextSpan(text: '$openPrefix]$suffix \n'));
    return result;
  }

  /// 获取基本类型值 复杂类型会忽略
  TextSpan getBasicValue(dynamic value, String suffix, {String? prefix}) {
    if (value == null) {
      return TextSpan(
          text: prefix,
          children: [..._highlightMatches('null', textColor: colorTheme.keyword), TextSpan(text: suffix)]);
    }

    if (value is String) {
      return TextSpan(
          text: prefix,
          children: [..._highlightMatches('"$value"', textColor: colorTheme.string), TextSpan(text: suffix)]);
    }

    if (value is num) {
      return TextSpan(
          text: prefix,
          children: [..._highlightMatches(value.toString(), textColor: colorTheme.number), TextSpan(text: suffix)]);
    }

    if (value is bool) {
      return TextSpan(
          text: prefix,
          children: [..._highlightMatches(value.toString(), textColor: colorTheme.keyword), TextSpan(text: suffix)]);
    }

    if (value is List) {
      return TextSpan(children: _highlightMatches("${prefix ?? ''}["));
    }

    return TextSpan(children: _highlightMatches("${prefix ?? ''}{"));
  }

  List<InlineSpan> _highlightMatches(String text, {Color? textColor}) {
    if (searchController == null || searchController?.shouldSearch() == false) {
      return [TextSpan(text: text, style: TextStyle(color: textColor))];
    }

    final pattern = searchController!.value.pattern;
    final regex = searchController!.value.isRegExp
        ? RegExp(pattern, caseSensitive: searchController!.value.isCaseSensitive)
        : RegExp(RegExp.escape(pattern), caseSensitive: searchController!.value.isCaseSensitive);

    final spans = <InlineSpan>[];
    int start = 0;
    var allMatches = regex.allMatches(text).toList();
    final currentIndex = searchController!.currentMatchIndex.value;
    for (int i = 0; i < allMatches.length; i++) {
      final match = allMatches[i];
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start), style: TextStyle(color: textColor)));
      }
      // 为每个高亮项分配一个 GlobalKey
      final key = GlobalKey();
      matchKeys.add(key);

      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        baseline: TextBaseline.ideographic,
        child: Text(
          text.substring(match.start, match.end),
          key: key,
          style: TextStyle(
            color: textColor,
            backgroundColor:
                searchMatchTotal == currentIndex ? colorTheme.searchMatchCurrentColor : colorTheme.searchMatchColor,
          ),
        ),
      ));
      start = match.end;
      searchMatchTotal += 1; // 统计总匹配数
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: TextStyle(color: textColor)));
    }
    return spans;
  }
}
