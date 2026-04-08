import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/ui/component/search/highlight_text.dart';
import 'package:proxypin/ui/component/search/search_controller.dart';

void main() {
  group('HighlightTextWidget', () {
    testWidgets('does not apply root style when language is empty', (tester) async {
      final controller = SearchTextController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HighlightTextWidget(
            text: 'plain text body',
            searchController: controller,
          ),
        ),
      ));

      final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(selectable.style, isNull);

      await _disposeController(tester, controller);
    });

    testWidgets('keeps syntax highlighting while search is active', (tester) async {
      final controller = SearchTextController();
      BuildContext? hostContext;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            hostContext = context;
            return HighlightTextWidget(
              text: 'const token = 1;\nconst next = token;',
              language: 'javascript',
              searchController: controller,
            );
          }),
        ),
      ));

      controller.patternController.text = 'token';
      controller.showSearchOverlay(hostContext!, top: 0, right: 0);
      await tester.pump();
      await tester.pump();

      expect(controller.totalMatchCount.value, 2);

      final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
      final rootSpan = selectable.textSpan!;
      final keywordSpan = _flattenTextSpans(rootSpan).firstWhere((span) => span.text?.contains('const') ?? false);

      expect(keywordSpan.style?.color, isNotNull);
      expect((rootSpan.children ?? const <InlineSpan>[]).whereType<WidgetSpan>(), isEmpty);

      await _disposeController(tester, controller);
    });

    testWidgets('invalid regular expressions safely produce zero matches', (tester) async {
      final controller = SearchTextController();
      BuildContext? hostContext;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            hostContext = context;
            return HighlightTextWidget(
              text: '{"name": "proxypin"}',
              language: 'json',
              searchController: controller,
            );
          }),
        ),
      ));

      controller.toggleIsRegExp();
      controller.patternController.text = '(';
      controller.showSearchOverlay(hostContext!, top: 0, right: 0);
      await tester.pump();
      await tester.pump();

      expect(controller.totalMatchCount.value, 0);
      expect(find.byType(SelectableText), findsOneWidget);

      await _disposeController(tester, controller);
    });

    testWidgets('current match index is clamped when match count shrinks', (tester) async {
      final controller = SearchTextController();
      BuildContext? hostContext;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            hostContext = context;
            return HighlightTextWidget(
              text: 'foo bar foo',
              searchController: controller,
            );
          }),
        ),
      ));

      controller.patternController.text = 'foo';
      controller.showSearchOverlay(hostContext!, top: 0, right: 0);
      await tester.pump();
      await tester.pump();

      controller.moveNext();
      await tester.pump();
      expect(controller.currentMatchIndex.value, 1);

      controller.patternController.text = 'bar';
      await tester.pump();
      await tester.pump();

      expect(controller.totalMatchCount.value, 1);
      expect(controller.currentMatchIndex.value, 0);

      await _disposeController(tester, controller);
    });

    testWidgets('forwards the custom context menu builder', (tester) async {
      final controller = SearchTextController();
      Widget menuBuilder(BuildContext context, EditableTextState editableTextState) => const SizedBox.shrink();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HighlightTextWidget(
            text: 'plain text',
            searchController: controller,
            contextMenuBuilder: menuBuilder,
          ),
        ),
      ));

      final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(selectable.contextMenuBuilder, same(menuBuilder));

      await _disposeController(tester, controller);
    });
  });
}

Future<void> _disposeController(WidgetTester tester, SearchTextController controller) async {
  controller.closeSearch();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  controller.dispose();
}

Iterable<TextSpan> _flattenTextSpans(InlineSpan span) sync* {
  if (span is! TextSpan) {
    return;
  }

  yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _flattenTextSpans(child);
  }
}

