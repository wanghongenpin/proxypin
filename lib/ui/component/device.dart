import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

class DeviceUtils {
  /// Get the device id
  static Future<String?> deviceId() async {
    var deviceInfoPlugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      return deviceInfoPlugin.androidInfo.then((it) => it.id);
    } else if (Platform.isIOS) {
      return deviceInfoPlugin.iosInfo.then((it) => it.identifierForVendor);
    }

    return await desktopDeviceId();
  }

  /// Get the desktop device id
  static Future<String?> desktopDeviceId() async {
    var deviceInfoPlugin = DeviceInfoPlugin();
    if (Platform.isWindows) {
      return deviceInfoPlugin.windowsInfo.then((it) => it.deviceId);
    } else if (Platform.isMacOS) {
      return deviceInfoPlugin.macOsInfo.then((it) => it.systemGUID);
    } else if (Platform.isLinux) {
      return deviceInfoPlugin.linuxInfo.then((it) => it.machineId);
    }
    return null;
  }
}
