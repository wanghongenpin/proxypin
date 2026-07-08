import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

export 'package:desktop_multi_window/desktop_multi_window.dart';

typedef DesktopMultiWindowMethodHandler = Future<dynamic> Function(MethodCall call, String fromWindowId);

class DesktopMultiWindow {
  static const String _mainWindowIdKey = '__mainWindowId';
  static const String _fromWindowIdKey = '__fromWindowId';
  static const String _argumentsKey = '__arguments';
  static const String _mainWindowChannelName = 'proxypin/main_window';

  static final WindowMethodChannel _mainWindowChannel = WindowMethodChannel(
    _mainWindowChannelName,
    mode: ChannelMode.unidirectional,
  );

  static String? _currentWindowId;
  static String? _mainWindowId;
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
  }

  static Future<WindowController> createWindow(String arguments) async {
    final configurationArguments = _withMainWindowId(arguments);
    return WindowController.create(WindowConfiguration(arguments: configurationArguments));
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

  static String _withMainWindowId(String arguments) {
    final mainWindowId = _mainWindowId ?? _currentWindowId;
    if (mainWindowId == null || mainWindowId.isEmpty) {
      return arguments;
    }

    try {
      final decoded = jsonDecode(arguments);
      if (decoded is Map<String, dynamic>) {
        return jsonEncode({_mainWindowIdKey: mainWindowId, ...decoded});
      }
    } catch (_) {
      // Keep non-JSON arguments unchanged.
    }
    return arguments;
  }

  static Future<void> _setWindowMethodHandler(WindowController controller) {
    return controller.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'window_close':
          return windowManager.close();
        case 'window_center':
          return windowManager.center();
        case 'window_setTitle':
          return windowManager.setTitle(call.arguments as String);
        case 'window_setTitleBarStyle':
          return windowManager.setTitleBarStyle(
            call.arguments == 'hidden' ? TitleBarStyle.hidden : TitleBarStyle.normal,
          );
        case 'window_setSize':
          final arguments = call.arguments as Map<dynamic, dynamic>;

          return windowManager.setSize(Size(
            (arguments['width'] as num).toDouble(),
            (arguments['height'] as num).toDouble(),
          ));
      }

      return _handleMethodCall(call);
    });
  }
}

extension WindowControllerCompat on WindowController {
  Future<void> close() {
    return _invokeWindowMethod('window_close');
  }

  Future<void> center() {
    return _invokeWindowMethod('window_center');
  }

  Future<void> setTitle(String title) {
    return _invokeWindowMethod('window_setTitle', title);
  }

  Future<void> setSize(Size size) {
    return _invokeWindowMethod('window_setSize', {
      'width': size.width,
      'height': size.height,
    });
  }

  Future<void> _invokeWindowMethod(String method, [dynamic arguments]) async {
    for (var i = 0; i < 20; i++) {
      try {
        await invokeMethod(method, arguments);
        return;
      } on WindowChannelException catch (e) {
        if (e.code != 'CHANNEL_UNREGISTERED' || i == 19) {
          rethrow;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }
}
