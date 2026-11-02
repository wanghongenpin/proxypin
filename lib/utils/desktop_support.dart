import 'dart:io';

import 'package:flutter/material.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/desktop/window_listener.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../network/util/logger.dart';
import '../ui/component/multi_window.dart';

class DesktopSupport {
  static const _minimumWindowSize = Size(1000, 600);

  static Future<void> initialize(AppConfiguration appConfiguration) async {
    try {
      await windowManager.ensureInitialized();

      final defaultWindowSize = Platform.isMacOS ? const Size(1230, 750) : const Size(1100, 650);
      final windowSize = _sanitizeWindowSize(appConfiguration.windowSize, defaultWindowSize);
      appConfiguration.windowSize = windowSize;

      final windowOptions = WindowOptions(
        minimumSize: _minimumWindowSize,
        size: windowSize,
        titleBarStyle: TitleBarStyle.hidden,
      );
      if (appConfiguration.themeMode != ThemeMode.system) {
        await windowManager
            .setBrightness(appConfiguration.themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light);
      }

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        if (Platform.isWindows) {
          await _restoreWindowsPosition(appConfiguration, windowSize);
        } else {
          final position = appConfiguration.windowPosition;
          if (position != null && await _isPositionVisible(position, windowSize)) {
            await windowManager.setPosition(position);
          } else {
            if (position != null) {
              appConfiguration.windowPosition = null;
            }
            //位置无效(如显示器已断开)时居中显示，避免窗口跑到屏幕外不可见
            await windowManager.center();
          }
        }

        await windowManager.show();
        await windowManager.focus();
      });

      windowManager.addListener(WindowChangeListener(appConfiguration));
      registerMethodHandler();
    } catch (e) {
      logger.e('Error during desktop initialization: $e');
    }
  }

  /// window_manager 0.5.x 在 Windows 上使用当前窗口 DPI 换算全局物理坐标。
  /// 保存位置时必须同时保存比例，否则跨不同 DPI 显示器启动无法还原原坐标。
  static Future<void> _restoreWindowsPosition(AppConfiguration appConfiguration, Size windowSize) async {
    if (appConfiguration.windowPosition == null || !_validScale(appConfiguration.windowPositionScale)) {
      _clearWindowPosition(appConfiguration);
      await windowManager.center();
      return;
    }

    try {
      final displays = await screenRetriever.getAllDisplays();
      final savedPosition = windowsPhysicalPosition(
        savedPosition: appConfiguration.windowPosition,
        savedWindowSize: windowSize,
        savedScale: appConfiguration.windowPositionScale,
        displays: displays,
      );

      if (savedPosition == null) {
        // 显示器断开或分辨率变化后，旧位置可能已经不可见。
        _clearWindowPosition(appConfiguration);
        await windowManager.center();
        return;
      }

      // setPosition 内部会再次乘以此比例，因此这里只需转换并设置一次。
      final currentScale = windowManager.getDevicePixelRatio();
      await windowManager.setPosition(savedPosition / currentScale);
    } catch (e) {
      _clearWindowPosition(appConfiguration);
      logger.e('Error restoring Windows window position: $e');
      await windowManager.center();
    }
  }

  @visibleForTesting
  static Offset? windowsPhysicalPosition({
    required Offset? savedPosition,
    required Size savedWindowSize,
    required double? savedScale,
    required List<Display> displays,
  }) {
    final scale = savedScale;
    if (savedPosition == null ||
        !savedPosition.dx.isFinite ||
        !savedPosition.dy.isFinite ||
        !_validScale(scale) ||
        !savedWindowSize.width.isFinite ||
        !savedWindowSize.height.isFinite ||
        savedWindowSize.width <= 0 ||
        savedWindowSize.height <= 0) {
      return null;
    }

    final physicalPosition = savedPosition * scale!;
    final physicalWindowSize = savedWindowSize * scale;
    return _isPhysicalPositionVisible(physicalPosition, physicalWindowSize, displays) ? physicalPosition : null;
  }

  static bool _isPhysicalPositionVisible(Offset position, Size windowSize, List<Display> displays) {
    if (!position.dx.isFinite ||
        !position.dy.isFinite ||
        !windowSize.width.isFinite ||
        !windowSize.height.isFinite ||
        windowSize.width <= 0 ||
        windowSize.height <= 0) {
      return false;
    }

    for (final display in displays) {
      final visibleRect = _physicalVisibleRect(display);
      if (visibleRect != null && _overlapsVisibleRect(position, windowSize, visibleRect)) return true;
    }
    return false;
  }

  static Rect? _physicalVisibleRect(Display display) {
    final scale = display.scaleFactor?.toDouble();
    if (!_validScale(scale)) return null;

    final origin = display.visiblePosition ?? Offset.zero;
    final size = display.visibleSize ?? display.size;
    final left = origin.dx * scale!;
    final top = origin.dy * scale;
    final width = size.width * scale;
    final height = size.height * scale;
    if (!left.isFinite || !top.isFinite || !width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      return null;
    }
    return Rect.fromLTWH(left, top, width, height);
  }

  static void _clearWindowPosition(AppConfiguration appConfiguration) {
    appConfiguration.windowPosition = null;
    appConfiguration.windowPositionScale = null;
  }

  static bool _validScale(double? scale) => scale != null && scale.isFinite && scale > 0;

  /// 修复配置文件中可能残留的无效窗口尺寸。
  ///
  /// 旧配置可能包含 0、负数、NaN、Infinity 或远大于当前显示器的尺寸。
  /// 这些值会被 window_manager 直接用于创建窗口，Windows 上可能表现为
  /// 白屏、窗口不可见或 Flutter surface 无法正常布局。
  static Size _sanitizeWindowSize(Size? savedSize, Size defaultSize) {
    if (savedSize == null || !savedSize.width.isFinite || !savedSize.height.isFinite) {
      return defaultSize;
    }

    final width = savedSize.width.clamp(_minimumWindowSize.width, 3840.0);
    final height = savedSize.height.clamp(_minimumWindowSize.height, 2160.0);
    final sanitized = Size(width.toDouble(), height.toDouble());

    if (sanitized != savedSize) {
      logger.w('Invalid saved window size $savedSize, using $sanitized');
    }
    return sanitized;
  }

  /// 校验保存的窗口位置是否落在某个显示器的可见范围内。
  /// 显示器断开或分辨率变化后，旧位置可能在所有屏幕之外，导致窗口不可见。
  static Future<bool> _isPositionVisible(Offset position, Size windowSize) async {
    try {
      final displays = await screenRetriever.getAllDisplays();
      if (displays.isEmpty || !position.dx.isFinite || !position.dy.isFinite) return false;

      for (final display in displays) {
        final origin = display.visiblePosition ?? Offset.zero;
        final size = display.visibleSize ?? display.size;
        final visibleRect = Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height);
        if (_overlapsVisibleRect(position, windowSize, visibleRect)) return true;
      }
      return false;
    } catch (e) {
      logger.e("Error validating window position: $e");
      // 校验失败时不使用保存的位置，回退到居中显示。
      return false;
    }
  }

  static bool _overlapsVisibleRect(Offset position, Size windowSize, Rect visibleRect) {
    // 至少要有一部分标题栏在某个显示器内，才认为位置可用。
    const minVisible = 100.0;
    final overlapLeft = position.dx > visibleRect.left - windowSize.width + minVisible;
    final overlapRight = position.dx < visibleRect.right - minVisible;
    final overlapTop = position.dy >= visibleRect.top;
    final overlapBottom = position.dy < visibleRect.bottom - minVisible;
    return overlapLeft && overlapRight && overlapTop && overlapBottom;
  }
}
