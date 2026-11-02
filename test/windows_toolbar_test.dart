import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/ui/desktop/widgets/windows_toolbar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  int maximizeCalls = 0;

  setUp(() {
    maximizeCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (call) async {
      switch (call.method) {
        case 'isMaximized':
        case 'isFullScreen':
        case 'isMinimized':
          return false;
        case 'maximize':
          maximizeCalls++;
          return null;
      }
      return null;
    });
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
    expect(maximizeCalls, 1);
  });

  testWidgets('双击图标按钮不触发最大化', (tester) async {
    await tester.pumpWidget(buildApp());
    await doubleTap(tester, tester.getCenter(find.byIcon(Icons.delete)));
    expect(maximizeCalls, 0);
  });
}
