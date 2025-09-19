import 'package:flutter/material.dart';
import 'package:proxypin/ui/component/search/search_controller.dart';

class HighlightTextWidget extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final SearchTextController searchController;

  const HighlightTextWidget(
      {super.key, required this.text, this.contextMenuBuilder, required this.searchController, this.style});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: searchController,
      builder: (context, child) {
        final spans = _highlightMatches(context);
        return SelectableText.rich(
          TextSpan(children: spans),
          showCursor: true,
          contextMenuBuilder: contextMenuBuilder,
        );
      },
    );
  }

  List<InlineSpan> _highlightMatches(BuildContext context) {
    if (!searchController.shouldSearch()) {
      return [TextSpan(text: text, style: style)];
    }

    final pattern = searchController.value.pattern;
    final regex = searchController.value.isRegExp
        ? RegExp(pattern, caseSensitive: searchController.value.isCaseSensitive)
        : RegExp(
            RegExp.escape(pattern),
            caseSensitive: searchController.value.isCaseSensitive,
          );

    final spans = <InlineSpan>[];
    int start = 0;
    var allMatches = regex.allMatches(text).toList();
    final currentIndex = searchController.currentMatchIndex.value;
    ColorScheme colorScheme = ColorScheme.of(context);
    List<GlobalKey> matchKeys = [];
    for (int i = 0; i < allMatches.length; i++) {
      final match = allMatches[i];
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start), style: style));
      }

      // 为每个高亮项分配一个 GlobalKey
      final key = GlobalKey();
      matchKeys.add(key);
      spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          baseline: TextBaseline.ideographic,
          child: Container(
            key: key,
            color: i == currentIndex ? colorScheme.primary : colorScheme.inversePrimary,
            child: Text(text.substring(match.start, match.end), style: style),
          )));
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: style));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      searchController.updateMatchCount(allMatches.length);
      _scrollToMatch(context, matchKeys);
      matchKeys.clear();
    });

    return spans;
  }

  void _scrollToMatch(BuildContext context, List<GlobalKey> matchKeys) {
    if (matchKeys.isNotEmpty) {
      final currentIndex = searchController.currentMatchIndex.value;
      if (currentIndex >= 0 && currentIndex < matchKeys.length) {
        final key = matchKeys[currentIndex];
        final context = key.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 300),
            alignment: 0.5, // 高亮项在视图中的位置
          );
        }
      }
    }
  }
}
