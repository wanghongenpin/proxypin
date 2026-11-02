import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/desktop_support.dart';
import 'package:screen_retriever/screen_retriever.dart';

void main() {
  const windowSize = Size(1000, 600);

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
  final rightSecondary100 = display(const Offset(3840, 0), const Size(1920, 1080), 1);

  group('Windows window position restoration', () {
    test('keeps physical position when display scales are equal', () {
      final position = DesktopSupport.windowsPhysicalPosition(
        savedPosition: const Offset(100, 80),
        savedWindowSize: windowSize,
        savedScale: 1,
        displays: [primary],
      );

      expect(position, const Offset(100, 80));
    });

    test('restores issue 984 secondary position with a higher-DPI primary', () {
      const savedPosition = Offset(3937, 309);
      final position = DesktopSupport.windowsPhysicalPosition(
        savedPosition: savedPosition,
        savedWindowSize: const Size(1192, 767),
        savedScale: 1,
        displays: [primary150, rightSecondary100],
      );

      expect(position, savedPosition);
      // 启动窗口位于 150% 主屏，插件最终仍会乘回 1.5。
      final restoreArgument = position! / 1.5;
      expect(restoreArgument * 1.5, savedPosition);
    });

    test('rejects issue 984 legacy position without a saved scale', () {
      final position = DesktopSupport.windowsPhysicalPosition(
        savedPosition: const Offset(3937, 309),
        savedWindowSize: const Size(1192, 767),
        savedScale: null,
        displays: [primary150, rightSecondary100],
      );

      expect(position, isNull);
    });

    test('recovers a secondary monitor position despite overlapping logical ranges', () {
      // 保存值 (2080, 80) 同时落在两块显示器的逻辑范围内，只有比例能还原目标位置。
      final position = DesktopSupport.windowsPhysicalPosition(
        savedPosition: const Offset(2080, 80),
        savedWindowSize: windowSize,
        savedScale: 1.25,
        displays: [primary, secondary125],
      );

      expect(position, const Offset(2600, 100));
      // 启动窗口在 150% 主屏时，插件最终仍会乘回 1.5。
      final restoreArgument = position! / 1.5;
      expect(restoreArgument * 1.5, const Offset(2600, 100));
    });

    test('supports a scaled secondary monitor to the left of the primary', () {
      final leftSecondary = display(const Offset(-1920, 0), const Size(1920, 1032), 1.25);
      final position = DesktopSupport.windowsPhysicalPosition(
        savedPosition: const Offset(-1440, 40),
        savedWindowSize: windowSize,
        savedScale: 1.25,
        displays: [primary, leftSecondary],
      );

      expect(position, const Offset(-1800, 50));
    });

    test('rejects a saved position whose monitor is disconnected', () {
      final position = DesktopSupport.windowsPhysicalPosition(
        savedPosition: const Offset(2080, 80),
        savedWindowSize: windowSize,
        savedScale: 1.25,
        displays: [primary],
      );

      expect(position, isNull);
    });

    test('rejects legacy and invalid scales', () {
      for (final scale in <double?>[null, 0, -1, double.nan, double.infinity]) {
        final position = DesktopSupport.windowsPhysicalPosition(
          savedPosition: const Offset(100, 80),
          savedWindowSize: windowSize,
          savedScale: scale,
          displays: [primary],
        );
        expect(position, isNull, reason: 'scale: $scale');
      }
    });

    test('skips displays without a usable scale', () {
      final invalidDisplay = Display(
        id: 'invalid',
        size: const Size(1920, 1080),
        visiblePosition: const Offset(2560, 0),
        visibleSize: const Size(1920, 1032),
        scaleFactor: 0,
      );
      final position = DesktopSupport.windowsPhysicalPosition(
        savedPosition: const Offset(2600, 100),
        savedWindowSize: windowSize,
        savedScale: 1,
        displays: [invalidDisplay],
      );

      expect(position, isNull);
    });
  });
}
