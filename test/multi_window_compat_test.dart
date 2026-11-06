import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:screen_retriever/screen_retriever.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const windowManagerChannel = MethodChannel('window_manager');
  const windowRouterChannel = MethodChannel('mixin.one/desktop_multi_window/channels');

  tearDown(() {
    messenger.setMockMethodCallHandler(windowManagerChannel, null);
    messenger.setMockMethodCallHandler(windowRouterChannel, null);
  });

  Display display(Offset physicalOrigin, Size physicalSize, double scale) {
    return Display(
      id: physicalOrigin.toString(),
      size: physicalSize / scale,
      visiblePosition: physicalOrigin / scale,
      visibleSize: physicalSize / scale,
      scaleFactor: scale,
    );
  }

  final primary = display(Offset.zero, const Size(2560, 1392), 1);
  final secondary125 = display(const Offset(2560, 0), const Size(1920, 1032), 1.25);
  final primary150 = display(Offset.zero, const Size(3840, 2160), 1.5);
  final rightSecondary125 = display(const Offset(3840, 0), const Size(2400, 1350), 1.25);

  group('child window display selection', () {
    test('uses the display containing the parent window center with mixed DPI', () {
      final screen = DesktopMultiWindow.displayRectForWindow(
        windowBounds: const Rect.fromLTWH(4000, 100, 1000, 700),
        displays: [primary150, rightSecondary125],
      );

      expect(screen, const Rect.fromLTWH(3840, 0, 2400, 1350));
    });

    test('does not confuse overlapping logical display ranges', () {
      final screen = DesktopMultiWindow.displayRectForWindow(
        windowBounds: const Rect.fromLTWH(2700, 100, 800, 600),
        displays: [primary, secondary125],
      );

      expect(screen, const Rect.fromLTWH(2560, 0, 1920, 1032));
    });

    test('supports a parent window on a display with negative coordinates', () {
      final leftSecondary = display(const Offset(-1920, 0), const Size(1920, 1080), 1);
      final screen = DesktopMultiWindow.displayRectForWindow(
        windowBounds: const Rect.fromLTWH(-1700, 100, 1000, 700),
        displays: [primary150, leftSecondary],
      );

      expect(screen, const Rect.fromLTWH(-1920, 0, 1920, 1080));
    });

    test('uses the largest overlap when the parent center is outside every display', () {
      final left = display(Offset.zero, const Size(1000, 1000), 1);
      final right = display(const Offset(2000, 0), const Size(1000, 1000), 1);
      final screen = DesktopMultiWindow.displayRectForWindow(
        windowBounds: const Rect.fromLTWH(500, 100, 1600, 500),
        displays: [left, right],
      );

      expect(screen, const Rect.fromLTWH(0, 0, 1000, 1000));
    });

    test('ignores displays without a usable scale and invalid window bounds', () {
      final invalidDisplay = Display(
        id: 'invalid',
        size: const Size(1920, 1080),
        visiblePosition: const Offset(3840, 0),
        visibleSize: const Size(1920, 1080),
        scaleFactor: 0,
      );
      final screen = DesktopMultiWindow.displayRectForWindow(
        windowBounds: const Rect.fromLTWH(4000, 100, 1000, 700),
        displays: [invalidDisplay],
      );

      expect(screen, isNull);
      expect(
        DesktopMultiWindow.displayRectForWindow(
          windowBounds: Rect.zero,
          displays: [primary],
        ),
        isNull,
      );
    });
  });

  group('child window centering', () {
    test('centers the physical child window size in the parent display work area', () {
      final position = DesktopMultiWindow.centeredWindowPosition(
        const Rect.fromLTWH(2560, 0, 1920, 1032),
        const Size(1440, 750),
      );

      expect(position, const Offset(2800, 141));
    });

    test('centers within a display to the left of the primary display', () {
      final position = DesktopMultiWindow.centeredWindowPosition(
        const Rect.fromLTWH(-1920, 0, 1920, 1080),
        const Size(800, 600),
      );

      expect(position, const Offset(-1360, 240));
    });

    test('keeps an oversized window centered instead of clamping to a corner', () {
      final position = DesktopMultiWindow.centeredWindowPosition(
        const Rect.fromLTWH(3840, 0, 1000, 800),
        const Size(1200, 900),
      );

      expect(position, const Offset(3740, -50));
    });
  });

  group('child window startup lifecycle', () {
    test('retries focus while the child window channel is starting', () async {
      var attempts = 0;
      messenger.setMockMethodCallHandler(windowRouterChannel, (call) async {
        expect(call.method, 'invokeMethod');
        attempts++;
        if (attempts < 3) {
          throw PlatformException(code: 'CHANNEL_UNREGISTERED', message: 'child engine is starting');
        }
        return null;
      });

      await WindowController.fromWindowId('42').focus();

      expect(attempts, 3);
    });

    testWidgets('shows the window when positioning fails', (tester) async {
      var showCalls = 0;
      messenger.setMockMethodCallHandler(windowManagerChannel, (call) async {
        if (call.method == 'getBounds') {
          throw PlatformException(code: 'TEST_ERROR', message: 'positioning failed');
        }
        if (call.method == 'isMinimized') return false;
        if (call.method == 'show') showCalls++;
        return null;
      });

      DesktopMultiWindow.prepareWindow();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pump();

      expect(showCalls, 1);
    });

    testWidgets('closes the hidden window when showing it also fails', (tester) async {
      var closeCalls = 0;
      messenger.setMockMethodCallHandler(windowManagerChannel, (call) async {
        if (call.method == 'getBounds' || call.method == 'show') {
          throw PlatformException(code: 'TEST_ERROR', message: '${call.method} failed');
        }
        if (call.method == 'isMinimized') return false;
        if (call.method == 'close') closeCalls++;
        return null;
      });

      DesktopMultiWindow.prepareWindow();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pump();

      expect(closeCalls, 1);
    });
  });
}
