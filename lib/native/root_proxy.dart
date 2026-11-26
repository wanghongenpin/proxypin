import 'dart:io';

import 'package:flutter/services.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/util/logger.dart';

/// 启动结果
class RootProxyResult {
  final bool success;
  final String? error;

  const RootProxyResult(this.success, [this.error]);
}

/// Android Root 模式：iptables 透明代理，不占用 VPN 通道。
///
/// 原生侧把被捕获应用的 TCP 流量 REDIRECT 到本地代理端口，
/// 原始目的地址 / 应用归属通过内核连接表反查，复用 `com.proxy/processInfo` 通道。
class RootProxy {
  static const MethodChannel _channel = MethodChannel('com.proxy/rootProxy');

  static bool get supported => Platform.isAndroid;

  static List<String> _split(String value) =>
      value.split(RegExp(r'[;,\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  static Map<String, dynamic> _arguments(String host, int port, Configuration configuration) {
    List<String> appList = configuration.appWhitelistEnabled ? configuration.appWhitelist : [];
    List<String> disallowApps = appList.isEmpty ? (configuration.appBlacklist ?? []) : [];

    return {
      "proxyHost": host,
      "proxyPort": port,
      "allowApps": appList,
      "disallowApps": disallowApps,
      "proxyPassDomains": _split(configuration.proxyPassDomains),
      "redirectPorts": _split(configuration.rootRedirectPorts),
      "blockIpv6": configuration.rootBlockIpv6,
      "blockQuic": configuration.rootBlockQuic,
    };
  }

  /// 设备上是否存在 su（不触发授权）
  static Future<bool> hasSuBinary() async {
    if (!supported) return false;
    return await _channel.invokeMethod<bool>("hasSuBinary") ?? false;
  }

  /// 请求 root 授权并检测是否可用（会触发 Magisk/KernelSU 授权弹窗）
  static Future<bool> isRootAvailable() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>("isRootAvailable") ?? false;
    } catch (e) {
      logger.e("isRootAvailable error", error: e);
      return false;
    }
  }

  static Future<RootProxyResult> start(String host, int port, Configuration configuration) async {
    return _invokeStart("start", host, port, configuration);
  }

  static Future<RootProxyResult> restart(String host, int port, Configuration configuration) async {
    return _invokeStart("restart", host, port, configuration);
  }

  static Future<RootProxyResult> _invokeStart(String method, String host, int port, Configuration configuration) async {
    if (!supported) return const RootProxyResult(false, 'unsupported platform');
    final args = _arguments(host, port, configuration);
    logger.d("RootProxy $method $args");
    try {
      final result = await _channel.invokeMethod<Map>(method, args);
      return RootProxyResult(result?['success'] == true, result?['error']);
    } catch (e) {
      logger.e("RootProxy $method error", error: e);
      return RootProxyResult(false, e.toString());
    }
  }

  static Future<void> stop() async {
    if (!supported) return;
    await _channel.invokeMethod("stop");
  }

  static Future<bool> isRunning() async {
    if (!supported) return false;
    return await _channel.invokeMethod<bool>("isRunning") ?? false;
  }
}
