import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/code_forge/read_only_viewer.dart';
import 'package:proxypin/ui/component/json/json_viewer.dart';
import 'package:proxypin/ui/component/search/highlight_text.dart';
import 'package:proxypin/ui/content/body.dart';
import 'package:proxypin/utils/html_formatter.dart';

void main() async {
  // Text/formUrl 等纯文本 tab 已迁到 code_forge（FFI），与 hex_viewer_test 一样需要原生库；
  // 初始化失败时这些用例整体跳过，保证无原生库的环境测试仍为绿色。
  bool nativeReady;
  try {
    final override = Platform.environment['CODE_FORGE_NATIVE_LIB'];
    if (override != null && override.isNotEmpty) {
      await RustLib.init(externalLibrary: ExternalLibrary.open(override));
    } else {
      await RustLib.init();
    }
    nativeReady = true;
  } catch (_) {
    nativeReady = false;
  }

  // CodeForge 编辑器有持续 ticker，不能用 pumpAndSettle；带 AppLocalizations 的 HttpBodyWidget
  // 还依赖 deferred 库加载，需用定时 pump 推进 fake-async 时间（runAsync 推不动这种 Timer）。
  Future<void> waitForCodeForge(WidgetTester tester, {int count = 1}) async {
    for (var i = 0; i < 30 && find.byType(CodeForge).evaluate().length < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

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

  testWidgets('switching to a small body does not render the previous large body', skip: !nativeReady,
      (tester) async {
    final large = HttpRequest(HttpMethod.get, 'https://example.com/large')
      ..headers.contentType = 'text/plain'
      ..body = List<int>.generate(150000, (index) => 97 + index % 26);
    final small = HttpRequest(HttpMethod.get, 'https://example.com/small')
      ..headers.contentType = 'text/plain'
      ..body = 'small body'.codeUnits;

    await tester.pumpWidget(_wrap(HttpBodyWidget(httpMessage: large)));
    // 15 万字符的单条超长行：唯一会分流到 code_forge 不换行快路径的情况。
    await waitForCodeForge(tester);
    final largeState =
        tester.state<CodeForgeReadOnlyViewerState>(find.byType(CodeForgeReadOnlyViewer));
    expect(largeState.controller!.text.length, 150000);

    // 切换到另一条消息：保活缓存整体清空，旧查看器 dispose；小文本回到旧高亮组件。
    await tester.pumpWidget(_wrap(HttpBodyWidget(httpMessage: small)));
    for (var i = 0; i < 30 && find.byType(HighlightTextWidget).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(CodeForge), findsNothing);
    expect(find.byType(HighlightTextWidget), findsOneWidget);
    expect(tester.widget<HighlightTextWidget>(find.byType(HighlightTextWidget)).text, 'small body');
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching views does not render the previous formatted text', skip: !nativeReady,
      (tester) async {
    final html = List.filled(1000, '<section><div><p>Hello</p></div></section>').join();
    final rawBody = '<html><body>$html</body></html>';
    final message = HttpRequest(HttpMethod.get, 'https://example.com/html')
      ..headers.contentType = 'text/html'
      ..body = rawBody.codeUnits;

    await tester.pumpWidget(_wrap(HttpBodyWidget(httpMessage: message)));
    // 单行约 4 万字符、低于超长行阈值：Text tab 保持旧高亮组件。旧路径先用前 1 万字符
    // 预览挂载，需等到异步格式化完成、全文就绪后再断言展示的是未格式化原文。
    for (var i = 0; i < 30; i++) {
      final widgets = find.byType(HighlightTextWidget).evaluate();
      if (widgets.isNotEmpty &&
          tester.widget<HighlightTextWidget>(find.byType(HighlightTextWidget).first).text == rawBody) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.widget<HighlightTextWidget>(find.byType(HighlightTextWidget).first).text, rawBody);

    await tester.tap(find.text('HTML'));
    await tester.pump();

    // 格式化完成前只显示新视图的预览，不显示上一个视图的完整大文本（HTML 仍走旧高亮组件）。
    expect(_bodyText(tester).length, lessThanOrEqualTo(10000));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pump();
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
