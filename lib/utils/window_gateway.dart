import 'dart:ui';

import 'package:window_manager/window_manager.dart';

/// 窗口动作的统一网关。
///
/// 业务侧统一走本网关调用窗口能力，测试通过 [debugWindowGatewayOverride]
/// 注入 fake 来断言窗口动作，无需 mock 插件通道；事件监听（WindowListener）
/// 仍直接注册在 windowManager 上。
///
/// 底层固定为 window_manager 0.5.x：其桌面插件按 engine 各自绑定
/// `registrar.view.window`，与 desktop_multi_window 的多 engine 子窗口兼容。
/// 0.6+ 改用 nativeapi 进程级单例、按全局 mainWindow 选窗口，会让隐藏子窗口
/// （hiddenAtLaunch）的 show/resize 错配到主窗口，故在切换到 Flutter 原生多窗口
/// 方案前不要升级，详见 pubspec.yaml 注释。
abstract interface class WindowGateway {
  Future<bool> isMaximized();

  Future<void> maximize();

  Future<void> unmaximize();

  Future<bool> isMinimized();

  Future<void> minimize();

  Future<void> restore();

  Future<void> close();

  Future<void> hide();

  Future<void> show();

  Future<void> center();

  Future<void> focus();

  Future<void> setTitle(String title);

  Future<void> setSize(Size size);

  Future<Size> getSize();

  Future<Rect> getBounds();

  Future<void> setPosition(Offset position);

  double getDevicePixelRatio();

  Future<void> startDragging();
}

class _DefaultWindowGateway implements WindowGateway {
  @override
  Future<bool> isMaximized() => windowManager.isMaximized();

  @override
  Future<void> maximize() => windowManager.maximize();

  @override
  Future<void> unmaximize() => windowManager.unmaximize();

  @override
  Future<bool> isMinimized() => windowManager.isMinimized();

  @override
  Future<void> minimize() => windowManager.minimize();

  @override
  Future<void> restore() => windowManager.restore();

  @override
  Future<void> close() => windowManager.close();

  @override
  Future<void> hide() => windowManager.hide();

  @override
  Future<void> show() => windowManager.show();

  @override
  Future<void> center() => windowManager.center();

  @override
  Future<void> focus() => windowManager.focus();

  @override
  Future<void> setTitle(String title) => windowManager.setTitle(title);

  @override
  Future<void> setSize(Size size) => windowManager.setSize(size);

  @override
  Future<Size> getSize() => windowManager.getSize();

  @override
  Future<Rect> getBounds() => windowManager.getBounds();

  @override
  Future<void> setPosition(Offset position) => windowManager.setPosition(position);

  @override
  double getDevicePixelRatio() => windowManager.getDevicePixelRatio();

  @override
  Future<void> startDragging() => windowManager.startDragging();
}

/// 测试注入点：非 null 时 [windowGateway] 返回它而不是真实实现。仅用于测试。
WindowGateway? debugWindowGatewayOverride;

WindowGateway get windowGateway => debugWindowGatewayOverride ?? _instance;

final WindowGateway _instance = _DefaultWindowGateway();
