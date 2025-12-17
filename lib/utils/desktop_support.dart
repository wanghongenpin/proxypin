import 'dart:io';

import 'package:flutter/material.dart';
import 'package:macos_window_utils/macos/ns_window_button_type.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:proxypin/ui/configuration.dart';
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

      if (Platform.isMacOS) {
        try {
          await WindowManipulator.initialize();
          // 调整关闭按钮的位置
          WindowManipulator.overrideStandardWindowButtonPosition(
              buttonType: NSWindowButtonType.closeButton, offset: Offset(10, 13));
          WindowManipulator.overrideStandardWindowButtonPosition(
              buttonType: NSWindowButtonType.miniaturizeButton, offset: const Offset(29, 13));
          WindowManipulator.overrideStandardWindowButtonPosition(
              buttonType: NSWindowButtonType.zoomButton, offset: const Offset(48, 13));
        } catch (e) {
          logger.e("Error adjusting macOS window button positions: $e");
        }
      }

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        if (windowPosition != null) {
          await windowManager.setPosition(windowPosition);
        }

        await windowManager.show();
        await windowManager.focus();
      });

      registerMethodHandler();
    } catch (e) {
      logger.e("Error during desktop initialization: $e");
    }
  }
}
