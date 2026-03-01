import 'package:flutter/services.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/util/logger.dart';

class Vpn {
  static const MethodChannel proxyVpnChannel = MethodChannel('com.proxy/proxyVpn');

  static bool isVpnStarted = false; //vpn是否已经启动

  static void startVpn(String host, int port, Configuration configuration, {bool? ipProxy = false}) {
    List<String>? appList = configuration.appWhitelistEnabled ? configuration.appWhitelist : [];

    List<String>? disallowApps;
    if (appList.isEmpty) {
      disallowApps = configuration.appBlacklist ?? [];
    }

    logger.d("Starting VPN with host: $host, port: $port,  proxyPassDomains: ${configuration.proxyPassDomains.split(';')}");
    proxyVpnChannel.invokeMethod("startVpn", {
      "proxyHost": host,
      "proxyPort": port,
      "allowApps": appList,
      "disallowApps": disallowApps,
      "ipProxy": ipProxy,
      "setSystemProxy": configuration.enableSystemProxy,
      "proxyPassDomains": configuration.proxyPassDomains.split(';'),
    });
    isVpnStarted = true;
  }

  static void stopVpn() {
    proxyVpnChannel.invokeMethod("stopVpn");
    isVpnStarted = false;
  }

  //重启vpn
  static void restartVpn(String host, int port, Configuration configuration, {bool ipProxy = false}) {
    List<String>? appList = configuration.appWhitelistEnabled ? configuration.appWhitelist : [];

    List<String>? disallowApps;
    if (appList.isEmpty) {
      disallowApps = configuration.appBlacklist ?? [];
    }
    proxyVpnChannel.invokeMethod("restartVpn", {
      "proxyHost": host,
      "proxyPort": port,
      "allowApps": appList,
      "disallowApps": disallowApps,
      "ipProxy": ipProxy,
      "setSystemProxy": configuration.enableSystemProxy,
      "proxyPassDomains": configuration.proxyPassDomains.split(';'),
    });

    isVpnStarted = true;
  }

  static Future<bool> isRunning() async {
    return await proxyVpnChannel.invokeMethod("isRunning");
  }
}
