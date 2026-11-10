import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/utils/navigator.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

export 'package:desktop_multi_window/desktop_multi_window.dart';

typedef DesktopMultiWindowMethodHandler = Future<dynamic> Function(MethodCall call, String fromWindowId);

class DesktopMultiWindow {
  static const String _mainWindowIdKey = '__mainWindowId';
  static const String _mainWindowScreenKey = '__mainWindowScreen';
  static const String _windowTitleKey = '__windowTitle';
  static const String _windowSizeKey = '__windowSize';
  static const String _fromWindowIdKey = '__fromWindowId';
  static const String _argumentsKey = '__arguments';
  static const String _mainWindowChannelName = 'proxypin/main_window';

  static final WindowMethodChannel _mainWindowChannel = WindowMethodChannel(
    _mainWindowChannelName,
    mode: ChannelMode.unidirectional,
  );

  static String? _currentWindowId;
  static String? _mainWindowId;
  static Rect? _mainWindowScreen;
  static double? _mainWindowScreenScale;
  static String? _windowTitle;
  static Size? _windowSize;
  static DesktopMultiWindowMethodHandler? _handler;

  static String? get currentWindowId => _currentWindowId;

  static Future<WindowController> ensureInitialized({String? mainWindowId}) async {
    await windowManager.ensureInitialized();
    final controller = await WindowController.fromCurrentEngine();
    _currentWindowId = controller.windowId;
    _mainWindowId = mainWindowId ?? _mainWindowId ?? controller.windowId;
    await _setWindowMethodHandler(controller);
    return controller;
  }

  static void initializeFromArguments(Map<dynamic, dynamic> arguments) {
    final mainWindowId = arguments.remove(_mainWindowIdKey) as String?;
    if (mainWindowId != null && mainWindowId.isNotEmpty) {
      _mainWindowId = mainWindowId;
    }
    final screen = arguments.remove(_mainWindowScreenKey);
    _mainWindowScreen = _rectFromJson(screen);
    final scale = screen is Map ? screen['scale'] : null;
    _mainWindowScreenScale = scale is num && _validScale(scale.toDouble()) ? scale.toDouble() : null;
    _windowTitle = arguments.remove(_windowTitleKey) as String?;
    _windowSize = _sizeFromJson(arguments.remove(_windowSizeKey));
  }

  /// [size] 使用 Flutter 逻辑尺寸，由子窗口按目标显示器的 DPI 换算。
  static Future<WindowController> createWindow(String arguments, {String? title, Size? size}) async {
    final configurationArguments = await _withWindowContext(arguments, title: title, size: size);
    return WindowController.create(WindowConfiguration(
      arguments: configurationArguments,
      hiddenAtLaunch: true,
    ));
  }

  /// 首帧初始化 Flutter surface 后调整隐藏窗口，并等待 resize 后的帧完成再显示。
  static void prepareWindow() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final title = _windowTitle;
        if (title != null) {
          await windowManager.setTitle(title);
        }
        final size = _windowSize;
        final screen = _mainWindowScreen;
        final screenScale = _mainWindowScreenScale;
        if (Platform.isWindows && screen != null && screenScale != null) {
          await _resizeAndCenterOnMainScreen(screen, screenScale, size);
        } else {
          if (size != null) {
            await windowManager.setSize(size);
          }
          await windowManager.center();
        }
        await WidgetsBinding.instance.endOfFrame;
      } catch (error, stackTrace) {
        logger.e('Prepare child window failed, showing fallback window', error: error, stackTrace: stackTrace);
      } finally {
        try {
          await windowManager.show();
        } catch (error, stackTrace) {
          logger.e('Show child window failed, closing hidden window', error: error, stackTrace: stackTrace);
          try {
            await windowManager.close();
          } catch (closeError, closeStackTrace) {
            logger.e('Close hidden child window failed', error: closeError, stackTrace: closeStackTrace);
          }
        }
      }
    });
  }

  /// 同 DPI 直接设置最终尺寸；跨 DPI 先移动隐藏窗口，避免 WM_DPICHANGED 二次缩放目标尺寸。
  static Future<void> _resizeAndCenterOnMainScreen(Rect screen, double screenScale, Size? size) async {
    var scale = _windowPixelRatio();
    if (scale != screenScale) {
      final initialSize = await windowManager.getSize();
      final initialPosition = centeredWindowPosition(screen, initialSize * scale);
      await windowManager.setPosition(initialPosition / scale);
      await WidgetsBinding.instance.endOfFrame;
      scale = _windowPixelRatio();
    }

    if (size != null) {
      // setSize 内部会乘以当前窗口 DPI；跨 DPI 时换算成目标屏幕的物理尺寸。
      await windowManager.setSize(scale == screenScale ? size : size * screenScale / scale);
    }
    final windowSize = await windowManager.getSize();
    final position = centeredWindowPosition(screen, windowSize * scale);
    await windowManager.setPosition(position / scale);
  }

  static Future<T?> invokeMainWindowMethod<T>(String method, [dynamic arguments]) async {
    return _mainWindowChannel.invokeMethod<T>(method, {
      _fromWindowIdKey: _currentWindowId,
      _argumentsKey: arguments,
    });
  }

  static Future<T?> invokeMethod<T>(Object windowId, String method, [dynamic arguments]) async {
    if (windowId.toString() == '0') {
      return invokeMainWindowMethod<T>(method, arguments);
    }

    final targetWindowId = _resolveWindowId(windowId);
    return WindowController.fromWindowId(targetWindowId).invokeMethod<T>(method, arguments);
  }

  static Future<void> setMethodHandler(DesktopMultiWindowMethodHandler handler) async {
    _handler = handler;
    final controller = await ensureInitialized(mainWindowId: _mainWindowId);
    if (_currentWindowId == _mainWindowId) {
      await _mainWindowChannel.setMethodCallHandler(_handleMethodCall);
    } else {
      await _setWindowMethodHandler(controller);
    }
  }

  static String _resolveWindowId(Object windowId) {
    final id = windowId.toString();
    if (id == '0') {
      return _mainWindowId ?? id;
    }
    return id;
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    final arguments = call.arguments;
    if (arguments is Map && arguments.containsKey(_argumentsKey)) {
      return _handler?.call(
        MethodCall(call.method, arguments[_argumentsKey]),
        arguments[_fromWindowIdKey]?.toString() ?? '',
      );
    }
    return _handler?.call(call, '');
  }

  static Future<String> _withWindowContext(String arguments, {String? title, Size? size}) async {
    try {
      final decoded = jsonDecode(arguments);
      if (decoded is Map<String, dynamic>) {
        final context = Map<String, dynamic>.from(decoded);
        final mainWindowId = _mainWindowId ?? _currentWindowId;
        if (mainWindowId != null && mainWindowId.isNotEmpty) {
          context[_mainWindowIdKey] = mainWindowId;
        }
        if (Platform.isWindows) {
          final screen = await _currentWindowScreen();
          if (screen != null) {
            context[_mainWindowScreenKey] = {
              ..._rectToJson(screen),
              'scale': _windowPixelRatio(),
            };
          }
        }
        if (title != null) {
          context[_windowTitleKey] = title;
        }
        if (size != null) {
          context[_windowSizeKey] = {'width': size.width, 'height': size.height};
        }
        return jsonEncode(context);
      }
    } catch (_) {
      // Keep non-JSON arguments unchanged.
    }
    return arguments;
  }

  static Future<Rect?> _currentWindowScreen() async {
    try {
      // window_manager 和 screen_retriever 在 Windows 上使用不同 DPI 换算，
      // 统一还原成物理坐标后再判断父窗口属于哪个显示器。
      final scale = _windowPixelRatio();
      final bounds = await windowManager.getBounds();
      final windowBounds = Rect.fromLTWH(
        bounds.left * scale,
        bounds.top * scale,
        bounds.width * scale,
        bounds.height * scale,
      );
      return displayRectForWindow(
        windowBounds: windowBounds,
        displays: await screenRetriever.getAllDisplays(),
      );
    } catch (_) {
      // 获取显示器失败时回退到 window_manager 的默认居中行为。
      return null;
    }
  }

  @visibleForTesting
  static Rect? displayRectForWindow({
    required Rect windowBounds,
    required List<Display> displays,
  }) {
    if (!_validRect(windowBounds)) return null;

    Rect? bestRect;
    var bestOverlap = 0.0;
    for (final display in displays) {
      final scale = display.scaleFactor?.toDouble();
      if (!_validScale(scale)) continue;

      final origin = display.visiblePosition ?? Offset.zero;
      final size = display.visibleSize ?? display.size;
      final rect = Rect.fromLTWH(
        origin.dx * scale!,
        origin.dy * scale,
        size.width * scale,
        size.height * scale,
      );
      if (!_validRect(rect)) continue;
      if (rect.contains(windowBounds.center)) return rect;

      final overlapWidth = _min(windowBounds.right, rect.right) - _max(windowBounds.left, rect.left);
      final overlapHeight = _min(windowBounds.bottom, rect.bottom) - _max(windowBounds.top, rect.top);
      if (overlapWidth <= 0 || overlapHeight <= 0) continue;
      final overlap = overlapWidth * overlapHeight;
      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        bestRect = rect;
      }
    }
    return bestRect;
  }

  @visibleForTesting
  static Offset centeredWindowPosition(Rect screen, Size windowSize) {
    final position = Offset(
      screen.left + (screen.width - windowSize.width) / 2,
      screen.top + (screen.height - windowSize.height) / 2,
    );
    return Offset(
      windowSize.width < screen.width
          ? position.dx.clamp(screen.left, screen.right - windowSize.width).toDouble()
          : position.dx,
      windowSize.height < screen.height
          ? position.dy.clamp(screen.top, screen.bottom - windowSize.height).toDouble()
          : position.dy,
    );
  }

  static double _windowPixelRatio() {
    if (!Platform.isWindows) return 1;
    final scale = windowManager.getDevicePixelRatio();
    return _validScale(scale) ? scale : 1;
  }

  static bool _validScale(double? scale) => scale != null && scale.isFinite && scale > 0;

  static bool _validRect(Rect rect) {
    return rect.left.isFinite &&
        rect.top.isFinite &&
        rect.width.isFinite &&
        rect.height.isFinite &&
        rect.width > 0 &&
        rect.height > 0;
  }

  static double _min(double a, double b) => a < b ? a : b;

  static double _max(double a, double b) => a > b ? a : b;

  static Map<String, double> _rectToJson(Rect rect) {
    return {'left': rect.left, 'top': rect.top, 'width': rect.width, 'height': rect.height};
  }

  static Rect? _rectFromJson(dynamic value) {
    if (value is! Map) return null;
    final left = value['left'];
    final top = value['top'];
    final width = value['width'];
    final height = value['height'];
    if (left is! num || top is! num || width is! num || height is! num) return null;
    final rect = Rect.fromLTWH(left.toDouble(), top.toDouble(), width.toDouble(), height.toDouble());
    return _validRect(rect) ? rect : null;
  }

  static Size? _sizeFromJson(dynamic value) {
    if (value is! Map) return null;
    final width = value['width'];
    final height = value['height'];
    if (width is! num || height is! num) return null;
    final size = Size(width.toDouble(), height.toDouble());
    return size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0 ? size : null;
  }

  static Future<void> _setWindowMethodHandler(WindowController controller) {
    return controller.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'window_close':
          return windowManager.close();
        case 'window_focus':
          // 最小化（含 macOS 缩到 Dock）先还原，再置顶聚焦
          if (await windowManager.isMinimized()) {
            await windowManager.restore();
          }
          return windowManager.focus();
      }

      return _handleMethodCall(call);
    });
  }
}

extension WindowControllerCompat on WindowController {
  Future<void> close() {
    // windowId == '0' 表示“没有真实子窗口”（Linux 内嵌打开 / 移动端）：
    // 直接关掉当前路由，页面里的关闭按钮才有反应。
    if (windowId == '0') {
      // 内嵌路由：直接关闭当前路由；没有可关的页面时静默忽略（不要走 platform channel，
      // 否则会抛 WindowChannelException: CHANNEL_UNREGISTERED）。
      final navigator = navigatorHelper.navigatorKey.currentState;
      if (navigator != null && navigator.canPop()) {
        navigator.pop();
      }
      return Future.value();
    }
    return _invokeWindowMethod('window_close');
  }

  Future<void> focus() {
    return _invokeWindowMethod('window_focus');
  }

  Future<void> _invokeWindowMethod(String method, [dynamic arguments]) async {
    // 新窗口创建后，其 Dart engine 需要时间启动并注册对应的 window channel
    // （mixin.one/window_controller/<windowId>）。若立刻调用会在启动竞态期间
    // 收到 CHANNEL_UNREGISTERED，因此轮询等待窗口 engine 就绪。
    for (var i = 0; i < 20; i++) {
      try {
        await invokeMethod(method, arguments);
        return;
      } on WindowChannelException catch (e) {
        if (e.code != 'CHANNEL_UNREGISTERED' || i == 19) {
          rethrow;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  }
}
