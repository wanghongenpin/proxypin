import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/component/model/search_model.dart';
import 'package:proxypin/ui/mobile/request/search.dart';

void main() {
  testWidgets('clearKeyword clears text and notifies onSearch without other filters', (tester) async {
    SearchModel? submitted;
    final key = GlobalKey<MobileSearchState>();

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MobileSearch(
          key: key,
          onSearch: (model) => submitted = model,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'github.com');
    await tester.pump(const Duration(milliseconds: 600));
    expect(key.currentState!.searchModel.keyword, 'github.com');
    expect(submitted?.keyword, 'github.com');

    key.currentState!.clearKeyword();
    await tester.pumpAndSettle();

    expect(find.text('github.com'), findsNothing);
    expect(key.currentState!.searchModel.keyword, isNull);
    expect(submitted?.keyword, isNull);
    expect(submitted, isNotNull);
  });

  testWidgets('clearKeyword is a no-op when keyword already empty', (tester) async {
    var calls = 0;
    final key = GlobalKey<MobileSearchState>();

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MobileSearch(
          key: key,
          onSearch: (_) => calls++,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    key.currentState!.clearKeyword();
    await tester.pumpAndSettle();
    expect(calls, 0);
  });
}
