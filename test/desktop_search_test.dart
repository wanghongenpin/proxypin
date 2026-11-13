import 'package:flutter/material.dart' hide DropdownMenu;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/model/search_model.dart';
import 'package:proxypin/ui/component/search_condition.dart';
import 'package:proxypin/ui/desktop/request/search.dart';

Widget buildSearchApp({ValueChanged<SearchModel>? onSearch}) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: Search(onSearch: onSearch))),
  );
}

Future<void> openSearchConditions(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.search));
  await tester.pumpAndSettle();
  expect(find.byType(SearchConditions), findsOneWidget);
}

Future<void> selectDropdownItem(WidgetTester tester, int index, String value) async {
  await tester.tap(find.byType(DropdownMenu).at(index));
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last, warnIfMissed: false);
  await tester.pumpAndSettle();
  expect(find.byType(SearchConditions), findsOneWidget);
}

void main() {
  testWidgets('confirm closes desktop search overlay without popping the page', (tester) async {
    await tester.pumpWidget(buildSearchApp());
    await tester.pumpAndSettle();

    final localizations = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    await openSearchConditions(tester);

    await tester.tap(find.text(localizations.confirm));
    await tester.pumpAndSettle();

    expect(find.byType(SearchConditions), findsNothing);
    expect(find.byType(Search), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter menus are clickable above the desktop search panel', (tester) async {
    SearchModel? submitted;
    await tester.pumpWidget(buildSearchApp(onSearch: (value) => submitted = value));
    await tester.pumpAndSettle();

    final localizations = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    await openSearchConditions(tester);

    expect(find.byType(DropdownMenu), findsNWidgets(3));
    expect(tester.getRect(find.byType(SearchConditions)).bottom, lessThan(tester.getRect(find.byType(Search)).top));

    await selectDropdownItem(tester, 0, 'POST');
    var state = tester.state<SearchConditionsState>(find.byType(SearchConditions));
    expect(state.searchModel.requestMethod, HttpMethod.post);

    await selectDropdownItem(tester, 1, 'FORM-DATA');
    state = tester.state<SearchConditionsState>(find.byType(SearchConditions));
    expect(state.searchModel.requestContentType, ContentType.formData);

    await selectDropdownItem(tester, 2, 'HTML');
    state = tester.state<SearchConditionsState>(find.byType(SearchConditions));
    expect(state.searchModel.responseContentTypes, {ContentType.html});

    await tester.tap(find.text(localizations.confirm));
    await tester.pumpAndSettle();

    expect(find.byType(SearchConditions), findsNothing);
    expect(find.byType(Search), findsOneWidget);
    expect(submitted!.requestMethod, HttpMethod.post);
    expect(submitted!.requestContentType, ContentType.formData);
    expect(submitted!.responseContentTypes, {ContentType.html});
    expect(tester.takeException(), isNull);
  });

  testWidgets('outside tap dismisses a filter menu before the search panel', (tester) async {
    await tester.pumpWidget(buildSearchApp());
    await tester.pumpAndSettle();
    await openSearchConditions(tester);

    await tester.tap(find.byType(DropdownMenu).first);
    await tester.pumpAndSettle();
    expect(find.text('POST'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('POST'), findsNothing);
    expect(find.byType(SearchConditions), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(SearchConditions), findsNothing);
    expect(find.byType(Search), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape dismisses a filter menu before the search panel', (tester) async {
    await tester.pumpWidget(buildSearchApp());
    await tester.pumpAndSettle();
    await openSearchConditions(tester);

    await tester.tap(find.byType(DropdownMenu).first);
    await tester.pumpAndSettle();
    expect(find.text('POST'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('POST'), findsNothing);
    expect(find.byType(SearchConditions), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SearchConditions), findsNothing);
    expect(find.byType(Search), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
