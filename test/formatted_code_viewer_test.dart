/*
 * Copyright 2026 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/code_forge/read_only_viewer.dart';
import 'package:proxypin/ui/component/search/search_controller.dart';
import 'package:proxypin/ui/component/search/virtualized_highlight_text.dart';
import 'package:proxypin/ui/content/formatted_code_viewer.dart';
import 'package:proxypin/utils/css_formatter.dart';
import 'package:re_highlight/languages/css.dart';

void main() async {
  // 纯 Dart 行索引不依赖原生库，任何环境都要跑。
  group('LineIndexer', () {
    test('maps offsets to zero-based line numbers', () {
      final indexer = LineIndexer.of('ab\ncd\nef');
      expect(indexer.lineOfOffset(0), 0);
      expect(indexer.lineOfOffset(2), 0); // 换行符本身仍属于上一行
      expect(indexer.lineOfOffset(3), 1); // 第二行首字符
      expect(indexer.lineOfOffset(5), 1);
      expect(indexer.lineOfOffset(6), 2);
      expect(indexer.lineOfOffset(8), 2); // 末行内任意偏移
    });

    test('single line without newline maps every offset to line zero', () {
      final indexer = LineIndexer.of('hello');
      for (var i = 0; i < 5; i++) {
        expect(indexer.lineOfOffset(i), 0);
      }
    });

    test('handles CRLF by indexing on LF', () {
      final indexer = LineIndexer.of('a\r\nb\r\nc');
      expect(indexer.lineOfOffset(0), 0);
      expect(indexer.lineOfOffset(3), 1); // \r 占 2、\n 占 3，第二行从 4 开始前的偏移
      expect(indexer.lineOfOffset(4), 1);
      expect(indexer.lineOfOffset(7), 2);
    });
  });

  // CodeForge 走 FFI，需要 code_forge 原生库，初始化方式与 hex_viewer_test 一致。
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

  group('FormattedCodeViewer (CSS)', () {
    late SearchTextController searchController;

    setUp(() {
      searchController = SearchTextController();
    });

    tearDown(() {
      searchController.dispose();
    });

    HttpRequest cssMessage(String css) => HttpRequest(HttpMethod.get, 'https://example.com/a.css')
      ..headers.contentType = 'text/css'
      ..body = css.codeUnits;

    Future<void> pumpViewer(WidgetTester tester, HttpRequest message) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FormattedCodeViewer.css(
            message: message,
            language: langCss,
            searchController: searchController,
          ),
        ),
      ));
      await tester.runAsync(() async {
        for (var i = 0; i < 20 && find.byType(CodeForge).evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();
    }

    testWidgets('formats and renders CSS through CodeForge', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const raw = 'a{color:red}b{margin:0}';
      await pumpViewer(tester, cssMessage(raw));

      expect(find.byType(CodeForge), findsOneWidget);
      final viewerState =
          tester.state<CodeForgeReadOnlyViewerState>(find.byType(CodeForgeReadOnlyViewer));
      expect(viewerState.controller!.text, CSS.pretty(raw));
      expect(tester.takeException(), isNull);
    });

    testWidgets('synchronizes search matches', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpViewer(tester, cssMessage('.a{color:red}.b{color:blue}'));

      searchController.showSearchOverlay(tester.element(find.byType(FormattedCodeViewer)), top: 20, right: 10);
      searchController.patternController.text = 'color';
      await tester.pump();
      expect(searchController.totalMatchCount.value, 2);
      expect(searchController.currentMatchIndex.value, 0);

      searchController.moveNext();
      expect(searchController.currentMatchIndex.value, 1);
    });

    testWidgets('reloads when switching to another message', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const first = 'a{color:red}';
      const second = 'b{margin:0}';
      await pumpViewer(tester, cssMessage(first));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FormattedCodeViewer.css(
            message: cssMessage(second),
            language: langCss,
            searchController: searchController,
          ),
        ),
      ));
      await tester.pump();

      final viewerState =
          tester.state<CodeForgeReadOnlyViewerState>(find.byType(CodeForgeReadOnlyViewer));
      expect(viewerState.controller!.text, CSS.pretty(second));
      expect(viewerState.controller!.text.contains('color'), isFalse);
    });
  });

  group('FormattedCodeViewer (text / formUrl)', () {
    late SearchTextController searchController;

    setUp(() {
      searchController = SearchTextController();
    });

    tearDown(() {
      searchController.dispose();
    });

    HttpRequest message(String body, String contentType) => HttpRequest(HttpMethod.get, 'https://example.com/')
      ..headers.contentType = contentType
      ..body = body.codeUnits;

    Future<void> pump(WidgetTester tester, Widget viewer) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: viewer)));
      await tester.runAsync(() async {
        for (var i = 0; i < 20 && find.byType(CodeForge).evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();
    }

    String? currentText(WidgetTester tester) =>
        tester.state<CodeForgeReadOnlyViewerState>(find.byType(CodeForgeReadOnlyViewer)).controller?.text;

    testWidgets('plain text tab renders the raw body unchanged', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const raw = 'line one\nline two\nno highlighting here { } < >';
      await pump(
          tester,
          FormattedCodeViewer.text(
            message: message(raw, 'text/plain'),
            searchController: searchController,
          ));

      expect(find.byType(CodeForge), findsOneWidget);
      expect(currentText(tester), raw);
      expect(tester.takeException(), isNull);
    });

    testWidgets('formUrl tab decodes percent-encoding', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const encoded = 'a=1&b=%E4%BD%A0%E5%A5%BD';
      await pump(
          tester,
          FormattedCodeViewer.formUrl(
            message: message(encoded, 'application/x-www-form-urlencoded'),
            searchController: searchController,
          ));

      expect(currentText(tester), Uri.decodeFull(encoded));
      expect(tester.takeException(), isNull);
    });

    testWidgets('text and formUrl soft-wrap (no horizontal scroll), CSS does not',
        skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pump(
          tester,
          FormattedCodeViewer.text(
            message: message('a long line', 'text/plain'),
            searchController: searchController,
          ));
      expect(tester.widget<CodeForge>(find.byType(CodeForge)).lineWrap, isTrue);

      await pump(
          tester,
          FormattedCodeViewer.formUrl(
            message: message('a=1&b=2', 'application/x-www-form-urlencoded'),
            searchController: searchController,
          ));
      expect(tester.widget<CodeForge>(find.byType(CodeForge)).lineWrap, isTrue);

      await pump(
          tester,
          FormattedCodeViewer.css(
            message: message('a{color:red}', 'text/css'),
            language: langCss,
            searchController: searchController,
          ));
      expect(tester.widget<CodeForge>(find.byType(CodeForge)).lineWrap, isFalse);
    });

    testWidgets('keeps the send-to-decoder / AES context menu items', skip: !nativeReady,
        (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pump(
          tester,
          FormattedCodeViewer.text(
            message: message('line one\nline two', 'text/plain'),
            searchController: searchController,
          ));

      final codeForge = tester.widget<CodeForge>(find.byType(CodeForge));
      final labels = codeForge.customContextMenuItems?.map((item) => item.label).toList() ?? [];
      // 测试环境固定英文 locale，断言英文标签；与旧 SelectableText 右键菜单的两项对齐。
      expect(labels, containsAll(['Send to Decoder', 'Send to AES Decrypt']));
    });

    testWidgets('large body with an overlong line forces code_forge no-wrap',
        skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 总长超过 10 万阈值，且单行超过 5 万超长行阈值：定宽换行布局会卡死，强制不换行。
      final body = 'A' * (120 * 1024);
      await pump(
          tester,
          FormattedCodeViewer.text(
            message: message(body, 'text/plain'),
            searchController: searchController,
          ));

      expect(find.byType(VirtualizedHighlightText), findsNothing);
      expect(find.byType(CodeForge), findsOneWidget);
      expect(tester.widget<CodeForge>(find.byType(CodeForge)).lineWrap, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('large body of normal-length lines falls back to virtualized viewer',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 约 12 万字符、8000 行，每行 ~15 字符（低于超长行阈值）：回退按行虚拟化组件。
      final body = List.generate(8000, (i) => 'log line $i').join('\n');
      expect(body.length, greaterThan(100000));
      await pump(
          tester,
          FormattedCodeViewer.text(
            message: message(body, 'text/plain'),
            searchController: searchController,
          ));

      expect(find.byType(VirtualizedHighlightText), findsOneWidget);
      expect(find.byType(CodeForge), findsNothing);
    });

    testWidgets('caps rendered highlights for a dense no-wrap search while keeping the total count',
        skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 12 万字符单条长行：超过 10 万阈值且含超长行，路由到 code_forge 强制不换行。
      final body = 'A' * (120 * 1024);
      await pump(
          tester,
          FormattedCodeViewer.text(
            message: message(body, 'text/plain'),
            searchController: searchController,
          ));
      expect(find.byType(CodeForge), findsOneWidget);

      final viewerState =
          tester.state<CodeForgeReadOnlyViewerState>(find.byType(CodeForgeReadOnlyViewer));
      searchController.showSearchOverlay(tester.element(find.byType(FormattedCodeViewer)), top: 10, right: 10);
      searchController.patternController.text = 'A';
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // 全量匹配数仍上报给搜索 UI（1/N），渲染层只拿到封顶后的子集，避免每帧数百万次 FFI。
      expect(searchController.totalMatchCount.value, body.length);
      final rendered = viewerState.controller!.searchHighlights;
      expect(rendered.length, lessThanOrEqualTo(200));
      expect(rendered, isNotEmpty);

      // 导航后当前匹配必须始终保留在抽稀结果里，否则活动高亮会消失。
      searchController.moveNext();
      await tester.pump(const Duration(milliseconds: 100));
      expect(viewerState.controller!.searchHighlights.any((h) => h.isCurrentMatch), isTrue);
    });

    testWidgets('caps rendered highlights in line-wrap mode too', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 5 万字符单条长行但总量低于 10 万：走常规 code_forge 软换行路径，搜单字符产生 5 万匹配。
      final body = 'A' * 50000;
      await pump(
          tester,
          FormattedCodeViewer.text(
            message: message(body, 'text/plain'),
            searchController: searchController,
          ));
      expect(tester.widget<CodeForge>(find.byType(CodeForge)).lineWrap, isTrue);

      final viewerState =
          tester.state<CodeForgeReadOnlyViewerState>(find.byType(CodeForgeReadOnlyViewer));
      searchController.showSearchOverlay(tester.element(find.byType(FormattedCodeViewer)), top: 10, right: 10);
      searchController.patternController.text = 'A';
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(searchController.totalMatchCount.value, body.length);
      expect(viewerState.controller!.searchHighlights.length, lessThanOrEqualTo(200));
    });

    testWidgets('does not cap a normal sparse search', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const body = 'alpha beta alpha gamma alpha';
      await pump(
          tester,
          FormattedCodeViewer.text(
            message: message(body, 'text/plain'),
            searchController: searchController,
          ));

      final viewerState =
          tester.state<CodeForgeReadOnlyViewerState>(find.byType(CodeForgeReadOnlyViewer));
      searchController.showSearchOverlay(tester.element(find.byType(FormattedCodeViewer)), top: 10, right: 10);
      searchController.patternController.text = 'alpha';
      await tester.pump(const Duration(milliseconds: 100));

      expect(searchController.totalMatchCount.value, 3);
      expect(viewerState.controller!.searchHighlights.length, 3);
    });

    testWidgets('large CSS body stays on code_forge (fallback disabled)',
        skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final css = List.generate(8000, (i) => '.rule$i { color: red; }').join('\n');
      expect(css.length, greaterThan(100000));
      await pump(
          tester,
          FormattedCodeViewer.css(
            message: message(css, 'text/css'),
            language: langCss,
            searchController: searchController,
          ));

      expect(find.byType(VirtualizedHighlightText), findsNothing);
      expect(find.byType(CodeForge), findsOneWidget);
    });

    testWidgets('formUrl falls back to raw body on malformed percent-encoding',
        skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const malformed = 'a=%zz&b=2';
      await pump(
          tester,
          FormattedCodeViewer.formUrl(
            message: message(malformed, 'application/x-www-form-urlencoded'),
            searchController: searchController,
          ));

      // Uri.decodeFull 会抛 ArgumentError，查看器回退原文而不是白屏。
      expect(currentText(tester), malformed);
      expect(tester.takeException(), isNull);
    });
  });
}
