import 'dart:async';
import 'dart:io';

import 'package:nativeapi/nativeapi.dart';
import 'package:nativeapi_flutter/nativeapi_flutter.dart' show ImageAsset;
import 'package:proxypin/utils/window_gateway.dart';
import 'package:tray_manager/tray_manager.dart';

class DesktopTrayManager {
  static final DesktopTrayManager instance = DesktopTrayManager._();

  DesktopTrayManager._();

  bool _initialized = false;
  Future<void> Function()? _quitHandler;

  TrayIcon? _trayIcon;
  Menu? _contextMenu;
  MenuItem? _showWindowItem;
  MenuItem? _quitItem;
  ListenerId? _iconListener;
  ListenerId? _showWindowListener;
  ListenerId? _quitListener;

  void setQuitHandler(Future<void> Function()? handler) {
    _quitHandler = handler;
  }

  String _text(String zh, String en) => Platform.localeName.startsWith('zh') ? zh : en;

  Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }

    _initialized = true;

    try {
      final trayIcon = TrayIcon.create();
      if (trayIcon == null) {
        throw StateError('failed to create native tray icon');
      }
      _trayIcon = trayIcon;

      final icon = ImageAsset.fromAsset('assets/icon.ico');
      if (icon != null) {
        trayIcon.icon = icon;
      }
      trayIcon.setTooltip('ProxyPin');

      final menu = Menu.create();
      if (menu == null) {
        throw StateError('failed to create native tray menu');
      }
      _contextMenu = menu;

      final showWindowItem = MenuItem.createWithLabelAndType(
        _text('显示窗口', 'Show window'),
        MenuItemType.normal,
      );
      final quitItem = MenuItem.createWithLabelAndType(
        _text('退出', 'Quit'),
        MenuItemType.normal,
      );
      if (showWindowItem != null) {
        _showWindowItem = showWindowItem;
        _showWindowListener = showWindowItem.addListener((event) {
          if (event is MenuItemClickedEvent) {
            unawaited(restoreWindow());
          }
        });
        menu.addItem(showWindowItem);
      }
      menu.addSeparator();
      if (quitItem != null) {
        _quitItem = quitItem;
        _quitListener = quitItem.addListener((event) {
          if (event is MenuItemClickedEvent) {
            unawaited(_quitHandler?.call() ?? exitApp());
          }
        });
        menu.addItem(quitItem);
      }

      // 左键单击恢复窗口；右键由触发器自动弹出菜单（Linux 面板只认触发器，不回传点击事件）
      _iconListener = trayIcon.addListener((event) {
        if (event is TrayIconClickedEvent) {
          unawaited(restoreWindow());
        }
      });

      trayIcon.setContextMenu(menu);
      trayIcon.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
      trayIcon.setVisible(true);
    } catch (error) {
      // 初始化中途失败：释放已拿到的原生句柄，允许下次重新初始化
      await exitApp();
      rethrow;
    }
  }

  Future<void> showToTray() async {
    await ensureInitialized();
    await windowGateway.hide();
  }

  Future<void> restoreWindow() async {
    await windowGateway.show();
    await windowGateway.focus();
  }

  Future<void> exitApp() async {
    try {
      final trayIcon = _trayIcon;
      final menu = _contextMenu;
      if (trayIcon != null) {
        final iconListener = _iconListener;
        if (iconListener != null) {
          trayIcon.removeListener(iconListener);
        }
        trayIcon.dispose();
      }
      final showWindowItem = _showWindowItem;
      final quitItem = _quitItem;
      final showWindowListener = _showWindowListener;
      final quitListener = _quitListener;
      if (showWindowItem != null && showWindowListener != null) {
        showWindowItem.removeListener(showWindowListener);
      }
      if (quitItem != null && quitListener != null) {
        quitItem.removeListener(quitListener);
      }
      showWindowItem?.dispose();
      quitItem?.dispose();
      menu?.dispose();
    } catch (_) {
      // ignore tray cleanup errors during app shutdown
    } finally {
      _trayIcon = null;
      _contextMenu = null;
      _showWindowItem = null;
      _quitItem = null;
      _iconListener = null;
      _showWindowListener = null;
      _quitListener = null;
      _initialized = false;
    }
  }
}
