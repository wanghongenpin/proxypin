import 'package:flutter/services.dart';
import 'package:proxypin/native/root_proxy.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/util/logger.dart';

/// Android 抓包通道：默认使用 VPN；开启 Root 模式时改用 iptables 透明代理（不占用 VPN）。
/// 对上层保持同一套接口，调用方无需区分模式。
class Vpn {
  static const MethodChannel proxyVpnChannel = MethodChannel('com.proxy/proxyVpn');

  static bool isVpnStarted = false; //抓包通道是否已经启动（VPN 或 Root）

  /// 当前通道是否为 Root 模式
  static bool rootModeActive = false;

  /// 最近一次 Root 模式启动失败的原因
  static String? lastRootError;

  static List<String> _proxyPassDomains(Configuration configuration) {
    return configuration.proxyPassDomains.split(';').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static bool _useRoot(Configuration configuration) => RootProxy.supported && configuration.rootModeEnabled;

  /// 启动抓包通道；Root 模式启动失败返回 false（VPN 模式可能需要用户授权，始终返回 true）
  static Future<bool> startVpn(String host, int port, Configuration configuration, {bool? ipProxy = false}) async {
    if (_useRoot(configuration)) {
      final result = await RootProxy.start(host, port, configuration);
      lastRootError = result.error;
      rootModeActive = result.success;
      isVpnStarted = result.success;
      if (!result.success) logger.w("Root proxy start failed: ${result.error}");
      return result.success;
    }

    List<String>? appList = configuration.appWhitelistEnabled ? configuration.appWhitelist : [];

    List<String>? disallowApps;
    if (appList.isEmpty) {
      disallowApps = configuration.appBlacklist ?? [];
    }

    final proxyPassDomains = _proxyPassDomains(configuration);
    logger.d("Starting VPN with host: $host, port: $port,  proxyPassDomains: $proxyPassDomains");
    proxyVpnChannel.invokeMethod("startVpn", {
      "proxyHost": host,
      "proxyPort": port,
      "allowApps": appList,
      "disallowApps": disallowApps,
      "ipProxy": ipProxy,
      "setSystemProxy": configuration.enableSystemProxy,
      "proxyPassDomains": proxyPassDomains,
    });
    rootModeActive = false;
    isVpnStarted = true;
    return true;
  }

  static Future<void> stopVpn() async {
    if (rootModeActive || await RootProxy.isRunning()) {
      await RootProxy.stop();
      rootModeActive = false;
    }
    proxyVpnChannel.invokeMethod("stopVpn");
    isVpnStarted = false;
  }

  //重启vpn
  static Future<void> restartVpn(String host, int port, Configuration configuration, {bool ipProxy = false}) async {
    if (_useRoot(configuration)) {
      // 从 VPN 切换到 Root 时先停掉 VPN
      if (!rootModeActive) proxyVpnChannel.invokeMethod("stopVpn");
      final result = await RootProxy.restart(host, port, configuration);
      lastRootError = result.error;
      rootModeActive = result.success;
      isVpnStarted = result.success;
      return;
    }

    if (rootModeActive) {
      await RootProxy.stop();
      rootModeActive = false;
    }

    List<String>? appList = configuration.appWhitelistEnabled ? configuration.appWhitelist : [];

    List<String>? disallowApps;
    if (appList.isEmpty) {
      disallowApps = configuration.appBlacklist ?? [];
    }
    final proxyPassDomains = _proxyPassDomains(configuration);
    proxyVpnChannel.invokeMethod("restartVpn", {
      "proxyHost": host,
      "proxyPort": port,
      "allowApps": appList,
      "disallowApps": disallowApps,
      "ipProxy": ipProxy,
      "setSystemProxy": configuration.enableSystemProxy,
      "proxyPassDomains": proxyPassDomains,
    });

    isVpnStarted = true;
  }

  static Future<bool> isRunning() async {
    final root = await RootProxy.isRunning();
    rootModeActive = root;
    if (root) return true;
    return await proxyVpnChannel.invokeMethod("isRunning");
  }
}
