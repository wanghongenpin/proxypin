import 'dart:io';

import 'package:flutter/material.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/desktop/window_listener.dart';
import 'package:window_manager/window_manager.dart';

import '../network/util/logger.dart';
import '../ui/component/multi_window.dart';

class DesktopSupport {
  static Future<void> initialize(AppConfiguration appConfiguration) async {
    try {
      await windowManager.ensureInitialized();

      //设置窗口大小
      Size windowSize =
          appConfiguration.windowSize ?? (Platform.isMacOS ? const Size(1230, 750) : const Size(1100, 650));
      WindowOptions windowOptions =
          WindowOptions(minimumSize: const Size(1000, 600), size: windowSize, titleBarStyle: TitleBarStyle.hidden);

      Offset? windowPosition = appConfiguration.windowPosition;

      if (appConfiguration.themeMode != ThemeMode.system) {
        windowManager.setBrightness(appConfiguration.themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light);
      }

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        if (windowPosition != null) {
          await windowManager.setPosition(windowPosition);
        }

        await windowManager.show();
        await windowManager.focus();
      });

      windowManager.addListener(WindowChangeListener(appConfiguration));
      registerMethodHandler();
    } catch (e) {
      logger.e("Error during desktop initialization: $e");
    }
  }
}
