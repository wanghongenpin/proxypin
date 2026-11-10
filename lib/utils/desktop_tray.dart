import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:menu_base/menu_base.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class DesktopTrayManager with TrayListener {
  static final DesktopTrayManager instance = DesktopTrayManager._();

  DesktopTrayManager._();

  bool _initialized = false;
  bool _available = false;
  Future<void> Function()? _quitHandler;

  void setQuitHandler(Future<void> Function()? handler) {
    _quitHandler = handler;
  }

  /// 托盘是否真的可用；不可用时“关闭时最小化到托盘”会把窗口藏起来却找不回来。
  bool get isAvailable => _available;

  String _text(String zh, String en) => Platform.localeName.startsWith('zh') ? zh : en;

  /// tray_manager 会把相对路径拼成 `<exe>/data/flutter_assets/<asset>`，Linux 的
  /// AppIndicator 又只认真实图片文件；上游用的 .ico 在部分面板/主题下不渲染，
  /// 这里统一改成 PNG，并在文件缺失时判定托盘不可用。
  String? _resolveIconPath() {
    if (!Platform.isLinux) {
      return 'assets/icon.ico';
    }

    const iconAsset = 'assets/icon.png';
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final bundled = File('$exeDir/data/flutter_assets/$iconAsset');
    if (!bundled.existsSync()) {
      logger.w('tray icon ${bundled.path} not found, tray unavailable on Linux');
      return null;
    }
    return iconAsset;
  }

  Future<bool> ensureInitialized() async {
    if (_initialized) {
      return _available;
    }

    _initialized = true;
    final iconPath = _resolveIconPath();
    if (iconPath == null) {
      return _available = false;
    }

    try {
      trayManager.addListener(this);
      await trayManager.setIcon(iconPath);
      // tray_manager 的 Linux 实现没有 setToolTip，直接调用会抛 MissingPluginException，
      // 进而让整个托盘初始化失败（结果就是“最小化到托盘”永远无效）。
      try {
        await trayManager.setToolTip('ProxyPin');
      } on MissingPluginException {
        // 该平台不支持 tooltip，忽略
      }
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(
              key: 'show_window',
              label: _text('显示窗口', 'Show window'),
            ),
            MenuItem.separator(),
            MenuItem(
              key: 'quit_app',
              label: _text('退出', 'Quit'),
            ),
          ],
        ),
      );
      _available = true;
    } catch (e) {
      logger.e('tray init failed, fall back to window close = exit', error: e);
      _available = false;
    }
    return _available;
  }

  /// 最小化到托盘；托盘不可用（或窗口没真的藏起来）时返回 false，
  /// 调用方应改为直接退出，避免出现“窗口关不掉也找不回来”的状态。
  Future<bool> showToTray() async {
    if (!await ensureInitialized()) {
      return false;
    }

    // hide() 是通过 platform channel 调 GTK 的，在 delete-event 回调里可能不会立刻
    // 生效，所以隔一小段时间再确认一次，确认失败也不要卡住用户。
    for (var attempt = 0; attempt < 2; attempt++) {
      await windowManager.hide();
      await Future.delayed(Duration(milliseconds: 150 + attempt * 250));
      if (!await windowManager.isVisible()) {
        return true;
      }
      logger.w('window still visible after hide() attempt ${attempt + 1}');
    }
    return false;
  }

  Future<void> restoreWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> exitApp() async {
    try {
      trayManager.removeListener(this);
      await trayManager.destroy();
    } catch (_) {
      // ignore tray cleanup errors during app shutdown
    } finally {
      _initialized = false;
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(restoreWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        unawaited(restoreWindow());
        break;
      case 'quit_app':
        unawaited(_quitHandler?.call() ?? exitApp());
        break;
    }
  }
}

