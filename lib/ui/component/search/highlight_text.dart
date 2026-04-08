import 'package:flutter/material.dart';
import 'package:proxypin/ui/component/search/highlight_text_document.dart';
import 'package:proxypin/ui/component/search/search_controller.dart';

class HighlightTextWidget extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final String? language;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final SearchTextController searchController;

  const HighlightTextWidget({
    super.key,
    required this.text,
    this.style,
    this.language,
    this.contextMenuBuilder,
    required this.searchController,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: searchController,
      builder: (context, child) {
        final document = HighlightTextDocument.create(
          context,
          text: text,
          style: style,
          language: language,
          searchController: searchController,
        );
        final spans = document.buildAllSpans(context);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          searchController.updateMatchCount(document.totalMatchCount);
        });

        return SelectableText.rich(
          TextSpan(children: spans),
          showCursor: true,
          // selectionColor: highlightSelectionColor(context),
          contextMenuBuilder: contextMenuBuilder,
        );
      },
    );
  }
}
