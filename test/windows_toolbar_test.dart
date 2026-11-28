import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/ui/desktop/widgets/windows_toolbar.dart';
import 'package:proxypin/utils/window_gateway.dart';

/// 窗口插件依赖原生平台通道，widget test 没有原生侧，
/// 经 WindowGateway 注入 fake 记录窗口动作。
class _RecordingGateway implements WindowGateway {
  int maximizeCalls = 0;
  int unmaximizeCalls = 0;
  int minimizeCalls = 0;
  int restoreCalls = 0;
  int closeCalls = 0;
  int dragCalls = 0;
  bool maximized = false;
  bool minimized = false;

  @override
  Future<bool> isMaximized() async => maximized;

  @override
  Future<void> maximize() async => maximizeCalls++;

  @override
  Future<void> unmaximize() async => unmaximizeCalls++;

  @override
  Future<bool> isMinimized() async => minimized;

  @override
  Future<void> minimize() async => minimizeCalls++;

  @override
  Future<void> restore() async => restoreCalls++;

  @override
  Future<void> close() async => closeCalls++;

  @override
  Future<void> hide() async {}

  @override
  Future<void> startDragging() async => dragCalls++;

  @override
  Future<void> show() async {}

  @override
  Future<void> center() async {}

  @override
  Future<void> focus() async {}

  @override
  Future<void> setTitle(String title) async {}

  @override
  Future<void> setSize(Size size) async {}

  @override
  Future<Size> getSize() async => Size.zero;

  @override
  Future<Rect> getBounds() async => Rect.zero;

  @override
  Future<void> setPosition(Offset position) async {}

  @override
  double getDevicePixelRatio() => 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingGateway gateway;

  setUp(() {
    gateway = _RecordingGateway();
    debugWindowGatewayOverride = gateway;
  });

  tearDown(() {
    debugWindowGatewayOverride = null;
  });

  Widget buildApp() {
    return MaterialApp(
      home: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: SizedBox(
            height: 52,
            child: WindowsToolbar(
              title: Row(children: [
                IconButton(icon: const Icon(Icons.delete), onPressed: () {}),
                const Spacer(),
                IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> doubleTap(WidgetTester tester, Offset position) async {
    // createGesture().down() 在 automated binding 下不会派发到 Listener，须用 tapAt
    await tester.tapAt(position, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(position, kind: PointerDeviceKind.mouse);
    await tester.pump();
  }

  testWidgets('双击空白区域切换最大化', (tester) async {
    await tester.pumpWidget(buildApp());
    await doubleTap(tester, tester.getCenter(find.byType(Spacer)));
    expect(gateway.maximizeCalls, 1);
  });

  testWidgets('双击图标按钮不触发最大化', (tester) async {
    await tester.pumpWidget(buildApp());
    await doubleTap(tester, tester.getCenter(find.byIcon(Icons.delete)));
    expect(gateway.maximizeCalls, 0);
  });
}
