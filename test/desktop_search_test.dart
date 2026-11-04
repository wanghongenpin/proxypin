import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/component/search_condition.dart';
import 'package:proxypin/ui/desktop/request/search.dart';

void main() {
  testWidgets('confirm closes desktop search overlay without popping the page', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: Align(alignment: Alignment.bottomCenter, child: Search())),
    ));
    await tester.pumpAndSettle();

    final localizations = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(find.byType(SearchConditions), findsOneWidget);

    await tester.tap(find.text(localizations.confirm));
    await tester.pumpAndSettle();

    expect(find.byType(SearchConditions), findsNothing);
    expect(find.byType(Search), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
