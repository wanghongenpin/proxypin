import 'package:flutter/services.dart';
import 'package:proxypin/network/util/process_info.dart';

class ProcessInfoPlugin {
  static const MethodChannel _methodChannel = MethodChannel('com.proxy/processInfo');

  static Future<ProcessInfo?> getProcessByPort(String host, int port) {
    return _methodChannel.invokeMethod<Map>('getProcessByPort', {"host": host, "port": port}).then((process) {
      if (process == null) return null;

      return ProcessInfo(process['packageName'], process['name'], process['packageName'],
          icon: process['icon'], remoteHost: process['remoteHost'], remotePost: process['remotePost']);
    });
  }
}
