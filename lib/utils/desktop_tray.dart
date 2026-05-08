import 'dart:async';
import 'dart:io';

import 'package:menu_base/menu_base.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class DesktopTrayManager with TrayListener {
  static final DesktopTrayManager instance = DesktopTrayManager._();

  DesktopTrayManager._();

  bool _initialized = false;
  Future<void> Function()? _quitHandler;

  void setQuitHandler(Future<void> Function()? handler) {
    _quitHandler = handler;
  }

  String _text(String zh, String en) => Platform.localeName.startsWith('zh') ? zh : en;

  Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }

    _initialized = true;
    trayManager.addListener(this);
    await trayManager.setIcon('assets/icon.ico');
    await trayManager.setToolTip('ProxyPin');
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
  }

  Future<void> showToTray() async {
    await ensureInitialized();
    await windowManager.hide();
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

