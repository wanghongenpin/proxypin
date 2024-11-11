import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

class Platforms {
  /// 判断是否是桌面端
  static bool isDesktop() {
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// 判断是否是移动端
  static bool isMobile() {
    return Platform.isAndroid || Platform.isIOS;
  }

  /// 判断是否是ipad
  static Future<bool> isIpad() async {
    if (Platform.isIOS) {
      final deviceInfo = DeviceInfoPlugin();
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.model.toLowerCase().contains('ipad');
    }
    return false;
  }
}
