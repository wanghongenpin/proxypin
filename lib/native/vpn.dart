import 'package:flutter/services.dart';
import 'package:proxypin/network/bin/configuration.dart';

class Vpn {
  static const MethodChannel proxyVpnChannel = MethodChannel('com.proxy/proxyVpn');

  static bool isVpnStarted = false; //vpn是否已经启动

  static startVpn(String host, int port, Configuration configuration, {bool? ipProxy = false}) {
    List<String>? appList = configuration.appWhitelistEnabled ? configuration.appWhitelist : [];

    List<String>? disallowApps;
    if (appList.isEmpty) {
      disallowApps = configuration.appBlacklist ?? [];
    }

    proxyVpnChannel.invokeMethod("startVpn",
        {"proxyHost": host, "proxyPort": port, "allowApps": appList, "disallowApps": disallowApps, "ipProxy": ipProxy});
    isVpnStarted = true;
  }

  static stopVpn() {
    proxyVpnChannel.invokeMethod("stopVpn");
    isVpnStarted = false;
  }

  //重启vpn
  static restartVpn(String host, int port, Configuration configuration, {bool ipProxy = false}) {
    List<String>? appList = configuration.appWhitelistEnabled ? configuration.appWhitelist : [];

    List<String>? disallowApps;
    if (appList.isEmpty) {
      disallowApps = configuration.appBlacklist ?? [];
    }
    proxyVpnChannel.invokeMethod("restartVpn",
        {"proxyHost": host, "proxyPort": port, "allowApps": appList, "disallowApps": disallowApps, "ipProxy": ipProxy});

    isVpnStarted = true;
  }

  static Future<bool> isRunning() async {
    return await proxyVpnChannel.invokeMethod("isRunning");
  }
}
