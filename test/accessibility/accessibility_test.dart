import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';
import 'package:proxypin/ui/component/selection_action_bar.dart';
import 'package:proxypin/ui/toolbox/toolbox.dart';

void main() {
  group('accessibility', () {
    testWidgets('selection action bar exposes labeled actions', (tester) async {
      final controller = MultiSelectController()..enterSelectionMode('request-1');

      await _pumpLocalizedApp(
        tester,
        child: SelectionActionBar(
          selectionController: controller,
          onRepeat: () {},
          onExport: () {},
          onDelete: () {},
        ),
      );

      final context = tester.element(find.byType(SelectionActionBar));
      final localizations = AppLocalizations.of(context)!;

      expect(find.byTooltip(localizations.repeat), findsOneWidget);
      expect(find.byTooltip(localizations.export), findsOneWidget);
      expect(find.byTooltip(localizations.delete), findsOneWidget);
      expect(find.byTooltip(localizations.cancel), findsOneWidget);

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    testWidgets('toolbox action keeps an accessible label', (tester) async {
      const tooltip = 'JavaScript';

      await _pumpLocalizedApp(
        tester,
        child: Center(
          child: IconText(
            icon: Icons.code,
            text: tooltip,
            tooltip: tooltip,
            onTap: () {},
          ),
        ),
      );

      expect(find.byTooltip(tooltip), findsOneWidget);

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    });
  });
}

Future<void> _pumpLocalizedApp(
  WidgetTester tester, {
  required Widget child,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}
