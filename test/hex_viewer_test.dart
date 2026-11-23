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
import 'dart:math';

import 'package:code_forge/code_forge.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/search/active_viewer_scope.dart';
import 'package:proxypin/ui/component/search/highlight_text.dart';
import 'package:proxypin/ui/component/search/search_controller.dart';
import 'package:proxypin/ui/content/body.dart';
import 'package:proxypin/ui/content/hex_viewer.dart';

void main() async {
  // 纯 Dart 格式化逻辑不依赖原生库，任何环境都要跑。
  test('formats hex and ASCII including the incomplete final row', () {
    expect(
      formatHex([0, 32, 126, 127, 65], 4),
      '00 20 7e 7f     . ~.\n'
      '41              A\n',
    );
    expect(formatHex([], 16), isEmpty);
  });

  // CodeForge 走 FFI，需要 code_forge 原生库。默认按打包后的 framework 路径初始化
  //（与真实 App、CI 一致）；本机可用环境变量 CODE_FORGE_NATIVE_LIB 指向单独编译的动态库。
  // 初始化失败时原生相关用例整体跳过，保证无原生库的环境测试仍为绿色。
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

  group('HexViewer', () {
    late SearchTextController searchController;
    late GlobalKey<HexViewerState> viewerKey;

    setUp(() {
      searchController = SearchTextController();
      viewerKey = GlobalKey<HexViewerState>();
    });

    tearDown(() {
      searchController.dispose();
    });

    Future<void> pumpViewer(WidgetTester tester, List<int> data) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HexViewer(key: viewerKey, data: data, searchController: searchController),
        ),
      ));
    }

    testWidgets('loads current message and copies a multiline selection', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpViewer(tester, List.generate(64, (index) => index));
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && viewerKey.currentState!.controller == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(CodeForge), findsOneWidget);
      expect(viewerKey.currentState!.controller, isNotNull);

      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      viewerKey.currentState!.controller!.selection = const TextSelection(baseOffset: 3, extentOffset: 59);
      viewerKey.currentState!.controller!.copy();
      expect(clipboard.single, '01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f     .......');

      final firstFuture = viewerKey.currentState!.formattedText;
      final originalData = viewerKey.currentState!.widget.data;
      await pumpViewer(tester, originalData);
      expect(identical(firstFuture, viewerKey.currentState!.formattedText), isTrue);
      expect(viewerKey.currentState!.controller, isNotNull);

      // 小数据走同步路径：切换当帧就完成挂载，不出现 loading 闪烁。
      await pumpViewer(tester, [0x61, 0x62]);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(CodeForge), findsOneWidget);
      expect(viewerKey.currentState!.controller, isNotNull);
      expect(await viewerKey.currentState!.formattedText, formatHex([0x61, 0x62], 16));
      expect(viewerKey.currentState!.controller!.text, formatHex([0x61, 0x62], 16));
    });

    testWidgets('small data mounts synchronously without a loading frame', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpViewer(tester, List.generate(64, (index) => index));
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && viewerKey.currentState!.controller == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();
      expect(viewerKey.currentState!.controller, isNotNull);

      // 再次切换到另一个小消息：didUpdateWidget 同步挂载，任何时刻都不应出现 loading。
      await pumpViewer(tester, List.generate(128, (index) => (index * 2) % 256));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(CodeForge), findsOneWidget);
      expect(viewerKey.currentState!.controller, isNotNull);
      // 帧后延迟的搜索同步不应抛 build 阶段写 Rx 的异常。
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('large data still formats in the background and shows loading', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 超过同步阈值（256KiB）的大 body 必须保留 isolate 路径，避免阻塞主线程。
      await pumpViewer(tester, List.filled(300 * 1024, 0x41));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(viewerKey.currentState!.controller, isNull);
      await tester.runAsync(() async {
        for (int i = 0; i < 30 && viewerKey.currentState!.controller == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();
      expect(find.byType(CodeForge), findsOneWidget);
      expect(viewerKey.currentState!.controller, isNotNull);
    });

    testWidgets('body toolbar copies the full formatted Hex text', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final data = List<int>.generate(64, (index) => index);
      final message = HttpRequest(HttpMethod.get, 'https://example.com/hex')
        ..headers.contentType = 'application/octet-stream'
        ..body = data;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: HttpBodyWidget(httpMessage: message)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hex'));
      await tester.pump();
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && find.byType(CodeForge).evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();
      expect(find.byType(CodeForge), findsOneWidget);

      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.tap(find.byTooltip('Copy'));
      await tester.pump();
      expect(clipboard.single, formatHex(data, 16));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('scrolls to a line through the external scroll controller without line flash', skip: !nativeReady,
        (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 2000 字节 -> 125 行，内容高度超过视口（590），可以真实滚动。
      await pumpViewer(tester, List.generate(2000, (index) => index % 256));
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && viewerKey.currentState!.controller == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      // 再跑一帧让首帧后的 setScrollCallback 覆盖生效。
      await tester.pump();

      final state = viewerKey.currentState!;
      expect(state.scrollController.hasClients, isTrue);
      state.controller!.scrollToLine(100);
      // 单次长 pump 不会推进 Scrollable 的 Ticker，需要逐帧 pump 跑完 300ms 滚动动画；
      // 真实设备以连续帧驱动，不存在此问题。CodeForge 光标闪烁持续 repeat，同样不能用 pumpAndSettle。
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      // 行高 16.8，目标居中偏移 = 100*16.8 + 8.4 - 视口 590/2 = 1393.4。
      expect(state.scrollController.offset, closeTo(1393.4, 1.0));
    });

    testWidgets('synchronizes search count and navigation', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpViewer(tester, List.generate(64, (index) => index % 2));
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && viewerKey.currentState!.controller == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();
      searchController.showSearchOverlay(tester.element(find.byType(HexViewer)), top: 20, right: 10);
      searchController.patternController.text = '01';
      await tester.pump();
      expect(searchController.totalMatchCount.value, 32);
      expect(searchController.currentMatchIndex.value, 0);

      searchController.moveNext();
      expect(searchController.currentMatchIndex.value, 1);
      searchController.movePrevious();
      expect(searchController.currentMatchIndex.value, 0);

      searchController.closeSearch();
      await tester.pump();
      expect(searchController.totalMatchCount.value, 0);
    });

    testWidgets('re-triggers search after the overlay is closed and reopened', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpViewer(tester, List.generate(64, (index) => index % 2));
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && viewerKey.currentState!.controller == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();

      final viewerContext = tester.element(find.byType(HexViewer));
      searchController.showSearchOverlay(viewerContext, top: 20, right: 10);
      searchController.patternController.text = '01';
      await tester.pump();
      final findController = viewerKey.currentState!.findController!;
      expect(findController.isActive, isTrue);
      expect(findController.matchCount, 32);

      // X 按钮路径：closeSearch 清空 pattern 并移除浮层，帧后同步读到 shouldSearch=false，搜索停用。
      searchController.closeSearch();
      await tester.pump();
      expect(findController.isActive, isFalse);

      // 重开走 showSearchOverlay：先写回 pattern（触发通知时浮层尚未插入，shouldSearch 为 false）、
      // 后插入浮层。HexViewer 把通知延迟到帧后再同步，此刻读到的已是"可见"状态，搜索重新激活。
      searchController.showSearchOverlay(viewerContext, top: 20, right: 10);
      await tester.pump();
      expect(findController.isActive, isTrue);
      expect(findController.matchCount, 32);
    });

    testWidgets('previous match navigates one step instead of wrapping through all matches', skip: !nativeReady,
        (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpViewer(tester, List.generate(64, (index) => index % 2));
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && viewerKey.currentState!.controller == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();
      searchController.showSearchOverlay(tester.element(find.byType(HexViewer)), top: 20, right: 10);
      searchController.patternController.text = '01';
      await tester.pump();
      expect(searchController.totalMatchCount.value, 32);

      final findController = viewerKey.currentState!.findController!;
      searchController.moveNext();
      searchController.moveNext();
      await tester.pump();
      expect(findController.currentMatchIndex, 2);

      // 普通"上一个"：只允许一次 FindController 通知（一次 previous()）。
      // 旧实现换算成 31 次 next()，会产生 31 次通知并播放 31 次滚动动画。
      var notifications = 0;
      void countNotifications() => notifications++;
      findController.addListener(countNotifications);
      searchController.movePrevious();
      await tester.pump();
      expect(searchController.currentMatchIndex.value, 1);
      expect(findController.currentMatchIndex, 1);
      expect(notifications, 1);

      // 从首个匹配再按"上一个"环绕到末尾：最短路径仍是一次 previous()，而不是 31 次 next()。
      notifications = 0;
      searchController.movePrevious();
      await tester.pump();
      expect(searchController.currentMatchIndex.value, 0);
      expect(findController.currentMatchIndex, 0);
      notifications = 0;
      searchController.movePrevious();
      await tester.pump();
      expect(searchController.currentMatchIndex.value, 31);
      expect(findController.currentMatchIndex, 31);
      expect(notifications, 1);
      findController.removeListener(countNotifications);
    });

    testWidgets('re-attaches the IME connection so text selection works while search is active', skip: !nativeReady,
        (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpViewer(tester, List.generate(256, (index) => index % 2));
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && viewerKey.currentState!.controller == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();
      final controller = viewerKey.currentState!.controller!;

      searchController.showSearchOverlay(tester.element(find.byType(HexViewer)), top: 20, right: 10);
      await tester.pump();
      searchController.patternController.text = '01';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(viewerKey.currentState!.findController!.isActive, isTrue);

      // 搜索框抢走平台 IME 后，编辑器连接处于 detached 状态（真机上“搜索时选不中文字”的前置状态）。
      expect(controller.connection == null || controller.connection!.attached == false, isTrue);

      // 真机点击编辑器会 requestFocus，焦点监听同步重连；测试绑定的指针焦点交付时序不同，
      // 直接请求编辑器焦点来确定性触发同一条重连路径。
      viewerKey.currentState!.editorFocusNode.requestFocus();
      await tester.pump();
      expect(controller.connection, isNotNull);
      expect(controller.connection!.attached, isTrue);

      // 重连后拖拽应建立非折叠选区，且不再抛 attached 断言/空指针。
      final gesture = await tester.startGesture(const Offset(120, 120), kind: PointerDeviceKind.mouse);
      for (final dy in [40.0, 80.0, 120.0, 160.0]) {
        await gesture.moveTo(Offset(120, 120 + dy));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
      // 等双击识别器的 400ms 倒计时走完，避免收尾报 pending Timer。
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(controller.selection.isCollapsed, isFalse);
    });

    testWidgets('does not write GetX Rx during build when switching data', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 复刻真实结构：Obx 与 HexViewer 是兄弟节点，Obx 订阅 totalMatchCount。
      // 修复前 didUpdateWidget -> _load 在 build 阶段同步写 Rx，会让该 Obx markNeedsBuild 而抛异常。
      Widget buildFrame(List<int> data) {
        return MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Obx(() => Text('count=${searchController.totalMatchCount.value}')),
                Expanded(
                  child: HexViewer(key: viewerKey, data: data, searchController: searchController),
                ),
              ],
            ),
          ),
        );
      }

      await tester.pumpWidget(buildFrame(List.generate(64, (index) => index % 2)));
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && viewerKey.currentState!.controller == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();

      searchController.showSearchOverlay(tester.element(find.byType(HexViewer)), top: 20, right: 10);
      searchController.patternController.text = '01';
      await tester.pump();
      expect(searchController.totalMatchCount.value, greaterThan(0));

      // 同 key 切换 data -> didUpdateWidget -> _load，整个过程不应抛 "setState during build"。
      await tester.pumpWidget(buildFrame(List.generate(32, (index) => index)));
      await tester.pump();
      expect(tester.takeException(), isNull);

      // 等新内容加载完成，控制器重建且计数恢复为有效值，确认延迟清零没有覆盖最终结果。
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && viewerKey.currentState!.controller == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();
      expect(viewerKey.currentState!.controller, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching data during scroll does not notify a disposed renderer', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpViewer(tester, List.generate(2000, (index) => index % 256));
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && viewerKey.currentState!.controller == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();

      final firstScrollController = viewerKey.currentState!.scrollController;
      expect(firstScrollController.hasClients, isTrue);
      // 模拟用户快速滚动（惯性滚动活动仍在运行）时切换消息。
      (firstScrollController.position as ScrollPositionWithSingleContext).goBallistic(-1200);

      await pumpViewer(tester, List.generate(1500, (index) => (index + 7) % 256));
      // 这一帧旧 CodeForge 卸载，旧 ScrollController 在帧后被释放；小数据同步挂载新 CodeForge。
      await tester.pump();

      // 等新 Scrollable 把 position attach 到新的 ScrollController（同步/异步两条路径时序不同）。
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && !viewerKey.currentState!.scrollController.hasClients; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();

      final secondScrollController = viewerKey.currentState!.scrollController;
      expect(secondScrollController.hasClients, isTrue);

      // 新 position 的惯性滚动若仍扇出到旧渲染对象未清理的监听，
      // 会对已释放的 RenderObject 调 markNeedsPaint，触发 !_debugDisposed 断言。
      (secondScrollController.position as ScrollPositionWithSingleContext).goBallistic(-1200);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      (secondScrollController.position as ScrollPositionWithSingleContext).goBallistic(1200);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      // 身份断言放最后：它本身也是修复的一部分，但不能提前失败而掩盖上面的崩溃路径。
      expect(identical(secondScrollController, firstScrollController), isFalse);
    });

    // 滚轮/触控板级联由 Flutter 框架的 pointerSignalResolver 提供：内层到边后不注册，
    // 外层 Scrollable 自然接管。此用例锁定该行为在 HexViewer 嵌套结构下确实成立。
    testWidgets('cascades wheel scrolling to the outer view at inner edges', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final outer = ScrollController();
      addTearDown(outer.dispose);
      final cascadeKey = GlobalKey<HexViewerState>();
      // 复刻 panel.dart 结构：外层 SingleChildScrollView（header + HexViewer）。
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: outer,
            child: Column(children: [
              const SizedBox(height: 300, child: Text('header')),
              HexViewer(
                key: cascadeKey,
                data: List.generate(2000, (index) => index % 256),
                searchController: searchController,
                outerScrollController: outer,
              ),
            ]),
          ),
        ),
      ));
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && cascadeKey.currentState!.controller == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();

      final inner = cascadeKey.currentState!.scrollController;
      expect(inner.hasClients, isTrue);
      final innerMax = inner.position.maxScrollExtent;
      final outerMax = outer.position.maxScrollExtent;
      expect(innerMax, greaterThan(0));
      expect(outerMax, greaterThan(0));

      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      final location = tester.getCenter(find.byType(CodeForge));
      await tester.sendEventToBinding(mouse.hover(location));

      Future<void> wheel(double dy) async {
        await tester.sendEventToBinding(mouse.scroll(Offset(0, dy)));
        await tester.pump();
      }

      // 内部还能滚：滚轮只驱动内部，外层保持不动。
      await wheel(100);
      expect(inner.position.pixels, greaterThan(0));
      expect(outer.position.pixels, 0);

      // 内部到底后继续向下滚：内部钉在底部，滚动量级联给外层。
      inner.jumpTo(innerMax);
      await tester.pump();
      await wheel(100);
      expect(inner.position.pixels, closeTo(innerMax, 0.01));
      expect(outer.position.pixels, greaterThan(0));

      // 外层也到底后再滚：两边都不动，且不抛异常。
      outer.jumpTo(outerMax);
      await tester.pump();
      await wheel(100);
      expect(inner.position.pixels, closeTo(innerMax, 0.01));
      expect(outer.position.pixels, closeTo(outerMax, 0.01));
      expect(tester.takeException(), isNull);

      // 反向：内部不在顶边时，向上滚轮先回滚内部，外层不动。
      final outerBefore = outer.position.pixels;
      await wheel(-100);
      expect(inner.position.pixels, lessThan(innerMax));
      expect(outer.position.pixels, outerBefore);

      // 内部回顶后继续向上：内部钉在顶部，外层向回级联。
      inner.jumpTo(0);
      await tester.pump();
      await wheel(-100);
      expect(inner.position.pixels, 0);
      expect(outer.position.pixels, lessThan(outerBefore));
    });

    testWidgets('cascades touch overscroll at the inner top to the outer view', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final outer = ScrollController();
      addTearDown(outer.dispose);
      final cascadeKey = GlobalKey<HexViewerState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: outer,
            child: Column(children: [
              const SizedBox(height: 300, child: Text('header')),
              HexViewer(
                key: cascadeKey,
                data: List.generate(2000, (index) => index % 256),
                searchController: searchController,
                outerScrollController: outer,
              ),
            ]),
          ),
        ),
      ));
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && cascadeKey.currentState!.controller == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();

      final inner = cascadeKey.currentState!.scrollController;
      // 外层先滚到中段、内部置于顶部：此时在 Hex 区域向下拖拽（顶部越界）应让外层向回滚。
      outer.jumpTo(outer.position.maxScrollExtent * 0.8);
      inner.jumpTo(0);
      await tester.pump();
      final outerBefore = outer.position.pixels;

      await tester.drag(find.byType(CodeForge), const Offset(0, 80));
      await tester.pump();

      expect(inner.position.pixels, 0);
      expect(outer.position.pixels, lessThan(outerBefore));
      expect(tester.takeException(), isNull);

      // 拖拽会启动双击识别器的 300ms 计时器，等它走完再结束用例，避免 pending Timer 报错。
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('does not allow horizontal scrolling when the line fits the viewport', skip: !nativeReady,
        (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final key = GlobalKey<HexViewerState>();
      // 复刻真机布局：HexViewer 视口因面板/卡片内边距比整屏窄（左右各 50，视口 900）。
      Widget frame(List<int> data) {
        return MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 50),
              child: HexViewer(key: key, data: data, searchController: searchController),
            ),
          ),
        );
      }

      Future<double> horizontalExtent() async {
        final element =
            find.byWidgetPredicate((w) => w.runtimeType.toString() == 'TwoDimensionalScrollable').evaluate().single;
        final dynamic state = (element as StatefulElement).state;
        return state.horizontalScrollable.position.maxScrollExtent as double;
      }

      // 4 字节一行（Ahem 测试字体下约 56 字符 ×14 = 784px）放得下 900 视口，不应有横向越界。
      // 修复前 code_forge 把最小宽度取成整屏宽 1000，extent 恒为内边距总量 100，与内容无关。
      await tester.pumpWidget(frame(List.generate(4, (i) => i)));
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && key.currentState!.controller == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();
      expect(await horizontalExtent(), 0);

      // 完整 16 字节日志行（68 字符 ×14 = 952px）确实超过 900 视口，正当的横向滚动要保留，
      // 且 extent 只反映真实内容超宽（约 52），不再混入内边距造成的 100。
      await tester.pumpWidget(frame(List.generate(32, (i) => i)));
      await tester.pump();
      await tester.pump();
      final overflow = await horizontalExtent();
      expect(overflow, greaterThan(0));
      expect(overflow, lessThan(100));
    });

    testWidgets('shrinks to content height for small bodies but keeps a usable minimum', skip: !nativeReady,
        (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 屏高 800 -> 视口高度 max(240, 800-210) = 590；行高固定 14*1.2 = 16.8。
      double editorHeight() => tester.getSize(find.byType(CodeForge)).height;

      // 1 行内容远低于下限：保留 240 的最小可用高度，而不是整屏 590 的空白。
      await pumpViewer(tester, List.generate(4, (i) => i));
      await tester.pump();
      expect(editorHeight(), 240);

      // 落在下限与视口之间：严格按内容自然高度（lineCount * 行高）收缩，明显小于视口 590。
      await pumpViewer(tester, List.generate(320, (i) => i % 256));
      await tester.pump();
      final midController = viewerKey.currentState!.controller!;
      final midContentHeight = midController.lineCount * 16.8;
      expect(editorHeight(), closeTo(midContentHeight, 0.01));
      expect(editorHeight(), greaterThan(240));
      expect(editorHeight(), lessThan(590));

      // 内容远超视口：保持视口高度 590，由内部滚动承载，不把外层撑高。
      await pumpViewer(tester, List.generate(2000, (i) => i % 256));
      await tester.pump();
      expect(editorHeight(), 590);
    });

    testWidgets('windows large search highlights to the visible lines', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 2000 个相同字节 -> 每行 16 个 "00"，共约 2000 个匹配，超过窗口化阈值（80）。
      await pumpViewer(tester, List.filled(2000, 0));
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && viewerKey.currentState!.controller == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();

      final state = viewerKey.currentState!;
      final lineCharLength = formatHex(List.filled(2000, 0), 16).indexOf('\n') + 1;

      searchController.showSearchOverlay(tester.element(find.byType(HexViewer)), top: 20, right: 10);
      searchController.patternController.text = '00';
      await tester.pump();

      // 总匹配数仍来自 FindController 的完整结果，不受窗口化影响。
      expect(searchController.totalMatchCount.value, 2000);
      final topHighlights = state.controller!.searchHighlights;
      // 交给渲染层的只是可视窗口（含边距）子集，远小于全量。
      expect(topHighlights.length, lessThan(2000));
      expect(topHighlights, isNotEmpty);
      // 顶部窗口不应包含靠后行的匹配。
      final topMaxLine = topHighlights.map((h) => h.start ~/ lineCharLength).reduce(max);
      expect(topMaxLine, lessThan(80));

      // 滚到底部后窗口应重建为末尾若干行，首行匹配已移出窗口。
      state.scrollController.jumpTo(state.scrollController.position.maxScrollExtent);
      await tester.pump();
      await tester.pump();
      final bottomHighlights = state.controller!.searchHighlights;
      final bottomMinLine = bottomHighlights.map((h) => h.start ~/ lineCharLength).reduce(min);
      expect(bottomMinLine, greaterThan(topMaxLine));
      expect(bottomHighlights.length, lessThan(2000));
    });
  });

  group('HttpBody tab keep-alive', () {
    Widget frame(HttpMessage message) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: HttpBodyWidget(httpMessage: message)),
      );
    }

    // octet-stream 的 tab 为 [Text, Hex]，正好覆盖文本查看器和 HexViewer 两条路径。
    HttpRequest octetMessage(String body) {
      return HttpRequest(HttpMethod.get, 'https://example.com/body')
        ..headers.contentType = 'application/octet-stream'
        ..body = body.codeUnits;
    }

    testWidgets('keeps a visited tab alive with its scroll offset and lazily builds others', skip: !nativeReady,
        (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(frame(octetMessage(String.fromCharCodes(List.generate(2000, (i) => 65 + i % 26)))));
      await tester.pumpAndSettle();

      // 初始只构建了 Text tab，Hex 尚未访问，不应存在于树中。
      expect(find.byType(HexViewer, skipOffstage: false), findsNothing);

      await tester.tap(find.text('Hex'));
      await tester.pump();
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && find.byType(CodeForge).evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();
      expect(find.byType(HexViewer), findsOneWidget);

      // 滚动 Hex 后切到 Text：HexViewer 必须以 Offstage 形式保留而不是销毁。
      final hexState = tester.state<HexViewerState>(find.byType(HexViewer));
      await tester.runAsync(() async {
        if (hexState.scrollController.hasClients) {
          hexState.scrollController.jumpTo(120);
        }
      });
      await tester.pump();
      expect(hexState.scrollController.offset, 120);
      final savedOffset = hexState.scrollController.offset;

      await tester.tap(find.text('Text'));
      await tester.pump();
      // find 默认跳过 Offstage 子树，这里显式关掉以确认查看器只是被隐藏。
      final hiddenHex = find.byType(HexViewer, skipOffstage: false);
      expect(hiddenHex, findsOneWidget);
      final offstage = tester
          .widget<Offstage>(find.ancestor(of: hiddenHex, matching: find.byType(Offstage, skipOffstage: false)).first);
      expect(offstage.offstage, isTrue);
      // Text tab 同样已被访问，两个查看器此刻都在树中。
      expect(find.byType(HighlightTextWidget), findsOneWidget);

      // 切回 Hex：同一个 State（不是重新挂载），滚动偏移原样保留。
      await tester.tap(find.text('Hex'));
      await tester.pump();
      expect(find.byType(HexViewer), findsOneWidget);
      final restoredState = tester.state<HexViewerState>(find.byType(HexViewer));
      expect(restoredState, same(hexState));
      expect(restoredState.scrollController.offset, savedOffset);
    });

    testWidgets('drops kept viewers when switching to another message', skip: !nativeReady, (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final first = octetMessage('first message body');
      await tester.pumpWidget(frame(first));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hex'));
      await tester.pump();
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && find.byType(CodeForge).evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();
      expect(find.byType(HexViewer), findsOneWidget);
      final firstState = tester.state<HexViewerState>(find.byType(HexViewer));

      // 切换到另一条消息：旧 HexViewer 必须 dispose，缓存不能跨消息残留。
      // 注意 HttpBodyState 会复用并记住上次选中的 tab，因此新消息直接落在 Hex，
      // 但它必须是从零构建的新实例，且 Text tab 仍保持懒构建。
      final second = octetMessage('second message body');
      await tester.pumpWidget(frame(second));
      await tester.pump();
      await tester.runAsync(() async {
        for (int i = 0; i < 20 && find.byType(CodeForge).evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          tester.binding.scheduleFrame();
        }
      });
      await tester.pump();
      expect(firstState.mounted, isFalse);
      expect(find.byType(HexViewer, skipOffstage: false), findsOneWidget);
      final secondState = tester.state<HexViewerState>(find.byType(HexViewer));
      expect(secondState, isNot(same(firstState)));
      expect(find.byType(HighlightTextWidget, skipOffstage: false), findsNothing);

      // 切到 Text 才首次构建该查看器，验证新消息的懒构建语义没有被旧缓存破坏。
      await tester.tap(find.text('Text'));
      await tester.pump();
      expect(find.byType(HighlightTextWidget), findsOneWidget);
    });

    testWidgets('hidden viewers do not overwrite the shared search count', (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 组件级守卫：inactive 作用域内的查看器随共享控制器重建，但不得回写匹配计数。
      final search = SearchTextController();
      addTearDown(search.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ActiveViewerScope(
            active: false,
            child: HighlightTextWidget(text: 'hello hello', searchController: search),
          ),
        ),
      ));

      search.showSearchOverlay(tester.element(find.byType(HighlightTextWidget)), top: 20, right: 10);
      search.updateMatchCount(99);
      search.patternController.text = 'hello';
      await tester.pump();
      await tester.pump();
      // 文本实际有 2 个匹配，若守卫失效这里会被覆盖成 2。
      expect(search.totalMatchCount.value, 99);

      // 对照：同一查看器在 active 作用域下正常回写真实匹配数。
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ActiveViewerScope(
            active: true,
            child: HighlightTextWidget(text: 'hello hello', searchController: search),
          ),
        ),
      ));
      search.patternController.text = 'hello';
      await tester.pump();
      await tester.pump();
      expect(search.totalMatchCount.value, 2);
    });
  });
}
