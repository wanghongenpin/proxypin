import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/json/json_viewer.dart';
import 'package:proxypin/ui/component/search/virtualized_highlight_text.dart';
import 'package:proxypin/ui/content/body.dart';
import 'package:proxypin/utils/html_formatter.dart';

void main() {
  testWidgets('switching messages keeps the JSON view when available', (tester) async {
    final first = HttpRequest(HttpMethod.get, 'https://example.com/first')
      ..headers.contentType = 'application/json'
      ..body = '{"first":true}'.codeUnits;
    final second = HttpRequest(HttpMethod.get, 'https://example.com/second')
      ..headers.contentType = 'application/json'
      ..body = '{"second":true}'.codeUnits;

    await tester.pumpWidget(_wrap(HttpBodyWidget(httpMessage: first)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JSON'));
    await tester.pumpAndSettle();
    expect(find.byType(JsonViewer), findsOneWidget);

    await tester.pumpWidget(_wrap(HttpBodyWidget(httpMessage: second)));
    await tester.pumpAndSettle();
    expect(find.byType(JsonViewer), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching to a small body does not render the previous large body', (tester) async {
    final large = HttpRequest(HttpMethod.get, 'https://example.com/large')
      ..headers.contentType = 'text/plain'
      ..body = List<int>.generate(150000, (index) => 97 + index % 26);
    final small = HttpRequest(HttpMethod.get, 'https://example.com/small')
      ..headers.contentType = 'text/plain'
      ..body = 'small body'.codeUnits;

    await tester.pumpWidget(_wrap(HttpBodyWidget(httpMessage: large)));
    await tester.pumpAndSettle();
    expect(find.byType(VirtualizedHighlightText), findsOneWidget);

    await tester.pumpWidget(_wrap(HttpBodyWidget(httpMessage: small)));

    final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(selectable.textSpan!.toPlainText(), 'small body');
    expect(find.byType(VirtualizedHighlightText), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching views does not render the previous formatted text', (tester) async {
    final html = List.filled(1000, '<section><div><p>Hello</p></div></section>').join();
    final rawBody = '<html><body>$html</body></html>';
    final message = HttpRequest(HttpMethod.get, 'https://example.com/html')
      ..headers.contentType = 'text/html'
      ..body = rawBody.codeUnits;

    await tester.pumpWidget(_wrap(HttpBodyWidget(httpMessage: message)));
    await tester.pumpAndSettle();
    expect(_bodyText(tester), rawBody);

    await tester.tap(find.text('HTML'));
    await tester.pump();

    // 格式化完成前只显示新视图的预览，不显示上一个视图的完整大文本。
    expect(_bodyText(tester).length, lessThanOrEqualTo(10000));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pumpAndSettle();
    expect(_bodyText(tester), HTML.pretty(rawBody));
    expect(tester.takeException(), isNull);
  });
}

String _bodyText(WidgetTester tester) =>
    tester.widget<SelectableText>(find.byType(SelectableText)).textSpan!.toPlainText();

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
