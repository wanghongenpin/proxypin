import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/component/model/search_model.dart';
import 'package:proxypin/ui/component/search_condition.dart';
import 'package:proxypin/ui/mobile/request/search.dart';

Future<void> pumpSearch(WidgetTester tester, ValueChanged<SearchModel> onSearch) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(appBar: AppBar(title: MobileSearch(onSearch: onSearch))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('clears the keyword immediately and cancels the pending search', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final keywords = <String?>[];
    await pumpSearch(tester, (model) => keywords.add(model.keyword));

    final field = find.byType(TextFormField);
    final clear = find.byIcon(Icons.close);
    expect(clear, findsNothing);

    await tester.enterText(field, 'example.org');
    await tester.pump();
    await tester.tap(clear);
    await tester.pump();

    expect(tester.widget<TextFormField>(field).controller!.text, isEmpty);
    expect(keywords, ['']);
    expect(clear, findsNothing);

    await tester.pump(const Duration(milliseconds: 500));
    expect(keywords, ['']);
  });

  testWidgets('clears only the keyword when advanced filters are active', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SearchModel? applied;
    await pumpSearch(tester, (model) => applied = model.clone());

    final localizations = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    final fields = find.descendant(of: find.byType(SearchConditions), matching: find.byType(TextFormField));
    await tester.enterText(fields.first, 'example.org');
    await tester.tap(find.widgetWithText(FilterChip, 'HTTPS'));
    await tester.tap(find.text(localizations.confirm));
    await tester.pumpAndSettle();

    expect(applied!.keyword, 'example.org');
    expect(applied!.protocols, isNotEmpty);
    final protocols = applied!.protocols;
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(applied!.keyword, isEmpty);
    expect(applied!.protocols, protocols);
  });
}
