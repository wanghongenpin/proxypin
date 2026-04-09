import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/ui/component/search/search_controller.dart';
import 'package:proxypin/ui/component/search/virtualized_highlight_text.dart';
import 'package:scrollable_positioned_list_nic/scrollable_positioned_list_nic.dart';

void main() {
  group('VirtualizedHighlightText', () {
    testWidgets('renders through ScrollablePositionedList and updates match counts', (tester) async {
      final controller = SearchTextController();
      BuildContext? hostContext;
      final text = List.generate(260, (index) => index == 180 ? 'line $index target' : 'line $index').join('\n');

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            hostContext = context;
            return VirtualizedHighlightText(
              text: text,
              language: 'javascript',
              searchController: controller,
              chunkLines: 80,
            );
          }),
        ),
      ));

      controller.patternController.text = 'target';
      controller.showSearchOverlay(hostContext!, top: 0, right: 0);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(ScrollablePositionedList), findsOneWidget);
      expect(controller.totalMatchCount.value, 1);

      await _disposeController(tester, controller);
    });

    testWidgets('scrolls to the active match line when navigating', (tester) async {
      final controller = SearchTextController();
      BuildContext? hostContext;
      final text = List.generate(
        320,
        (index) => index == 24 || index == 260 ? 'line $index target' : 'line $index',
      ).join('\n');

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            hostContext = context;
            return VirtualizedHighlightText(
              text: text,
              language: 'javascript',
              searchController: controller,
              chunkLines: 80,
            );
          }),
        ),
      ));

      controller.patternController.text = 'target';
      controller.showSearchOverlay(hostContext!, top: 0, right: 0);
      await tester.pump();
      await tester.pumpAndSettle();

      controller.moveNext();
      await tester.pump();

      expect(controller.currentMatchIndex.value, 1);

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

