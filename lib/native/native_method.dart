import 'package:flutter/services.dart';
import 'package:proxypin/network/util/logger.dart';

class NativeMethod {
  static const MethodChannel _channel = MethodChannel('com.proxypin/method');

  /// 检查本地网络（Wi-Fi 或以太网）是否可用 (仅限 iOS)。
  ///
  /// 返回 `true` 如果本地网络可用，否则返回 `false`。
  static Future<bool> requestLocalNetworkAccess() async {
    try {
      // 在 iOS 上，这将调用你在 Swift 中实现的 requestLocalNetworkAccess 方法
      // 该方法通过 NWPathMonitor 检查网络状态
      final bool isAvailable = await _channel.invokeMethod('requestLocalNetwork');
      logger.d("Local network access requested: $isAvailable");
      return isAvailable;
    } on PlatformException catch (e) {
      // 处理可能的平台异常，例如方法未实现等
      logger.e("Failed to request local network access: '${e.message}'.");
      return false;
    }
  }
}