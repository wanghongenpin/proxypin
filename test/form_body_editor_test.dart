import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/component/form_body_editor.dart';
import 'package:proxypin/utils/multipart.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  testWidgets('renders form rows without layout errors', (tester) async {
    final form = FormBody(parts: [
      FormPart(name: 'k1', value: 'v1'),
      FormPart(name: 'k2', value: 'v2'),
    ]);
    await tester.pumpWidget(wrap(FormBodyEditor(form: form)));
    await tester.pumpAndSettle();

    expect(find.text('k1'), findsOneWidget);
    expect(find.text('k2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty form renders empty hint', (tester) async {
    await tester.pumpWidget(wrap(FormBodyEditor(form: FormBody(), allowFiles: true)));
    await tester.pumpAndSettle();

    // 添加入口在工具栏，编辑区空状态只显示提示
    expect(find.text(AppLocalizations.of(tester.element(find.byType(Scaffold)))!.emptyData), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
