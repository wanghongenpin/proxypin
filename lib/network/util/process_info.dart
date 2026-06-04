/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:proxypin/native/installed_apps.dart';
import 'package:proxypin/native/process_info.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/socket_address.dart';
import 'package:win32audio/win32audio.dart';

import 'cache.dart';
import 'process_info_macos.dart';

void main() async {
  var processInfo = await ProcessInfoUtils.getProcess(512);
  // await ProcessInfoUtils.getMacIcon(processInfo!.path);
  // print(await ProcessInfoUtils.getProcessByPort(63194));
  print(processInfo);
}

/// 进程信息工具类 用于获取进程信息
///@author wanghongen
class ProcessInfoUtils {
  static final processInfoCache = ExpiringCache<String, ProcessInfo>(const Duration(minutes: 5));

  // (host:port) -> pid short cache. Keeps the FFI / Process.run lookup off
  // the request hot path for the typical HTTP keep-alive case where many
  // requests share a single client TCP connection (and thus a single
  // remote socket address). Greatly reduces how often the synchronous
  // libproc scan runs on the main isolate.
  static final _pidCache = ExpiringCache<String, int>(const Duration(seconds: 15));

  // Negative cache for ports whose owner can't be resolved (e.g. the client
  // process has already exited by the time we scan). Without this, every
  // short-lived connection forces a full PID-list rescan on every request.
  // Short TTL so a real owner that appears soon after is not masked.
  static final _pidNotFoundCache = ExpiringCache<String, bool>(const Duration(seconds: 5));

  static Future<ProcessInfo?> getProcessByPort(InetSocketAddress socketAddress, String cacheKeyPre) async {
    try {
      if (Platform.isAndroid) {
        var app = await ProcessInfoPlugin.getProcessByPort(socketAddress.host, socketAddress.port);
        if (app != null) {
          return app;
        }
        if (socketAddress.host == '127.0.0.1') {
          return ProcessInfo('com.network.proxy', "ProxyPin", '', os: Platform.operatingSystem);
        }
        return null;
      }

      var addrKey = "${socketAddress.host}:${socketAddress.port}";
      if (_pidNotFoundCache.get(addrKey) == true) return null;
      var pid = _pidCache.get(addrKey);
      if (pid == null) {
        pid = await _getPid(socketAddress);
        if (pid == null) {
          _pidNotFoundCache.set(addrKey, true);
          return null;
        }
        _pidCache.set(addrKey, pid);
      }

      String cacheKey = "$cacheKeyPre:$pid";
      var processInfo = processInfoCache.get(cacheKey);
      if (processInfo != null) return processInfo;

      processInfo = await getProcess(pid);
      if (processInfo != null) {
        processInfoCache.set(cacheKey, processInfo);
      }
      return processInfo;
    } catch (e) {
      logger.e("getProcessByPort error: $e");
      return null;
    }
  }

  // 获取进程 ID
  static Future<int?> _getPid(InetSocketAddress socketAddress) async {
    if (Platform.isWindows) {
      var result = await Process.run('cmd', ['/c', 'netstat -ano | findstr :${socketAddress.port}']);
      var lines = LineSplitter.split(result.stdout);
      for (var line in lines) {
        var parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length < 5) {
          continue;
        }
        if (parts[1].trim().contains("${socketAddress.host}:${socketAddress.port}")) {
          return int.tryParse(parts[4]);
        }
      }
      return null;
    }

    if (Platform.isMacOS) {
      // Use libproc syscalls (FFI) instead of spawning `lsof`. Each
      // Process.run on macOS goes through fork()+execvp(); under load a
      // multi-threaded Dart VM occasionally deadlocks the forked child
      // before exec, and the orphaned child keeps the inherited listening
      // socket fd alive forever. See issue #763.
      return MacosProcessInfo.findPidByLocalTcpPort(socketAddress.port);
    }
    return null;
  }

  static Future<ProcessInfo?> getProcess(int pid) async {
    if (Platform.isWindows) {
      // 获取应用路径
      var result = await Process.run('cmd', ['/c', 'wmic process where processid=$pid get ExecutablePath']);
      var output = result.stdout.toString();
      var path = output.split('\n')[1].trim();
      String name = path.substring(path.lastIndexOf('\\') + 1);
      return ProcessInfo(name, name.split(".")[0], path, os: Platform.operatingSystem);
    }

    if (Platform.isMacOS) {
      // Use libproc syscalls (FFI) instead of spawning `ps`. See issue #763.
      final fullPath = MacosProcessInfo.getProcessPath(pid);
      if (fullPath == null) return null;
      // For .app bundles, surface the bundle directory as the path so the
      // icon loader can find Contents/Info.plist. For standalone binaries
      // (e.g. /usr/bin/curl) use the executable path verbatim -- the old
      // implementation blindly appended ".app", producing non-existent
      // paths that poisoned the icon cache with empty bytes for 5 minutes.
      final bundleIdx = fullPath.indexOf('.app/');
      final String displayPath;
      final String name;
      if (bundleIdx >= 0) {
        final bundleBase = fullPath.substring(0, bundleIdx);
        displayPath = '$bundleBase.app';
        name = bundleBase.substring(bundleBase.lastIndexOf('/') + 1);
      } else {
        displayPath = fullPath;
        name = fullPath.substring(fullPath.lastIndexOf('/') + 1);
      }
      return ProcessInfo(name, name, displayPath, os: Platform.operatingSystem);
    }

    return null;
  }
}

class ProcessInfo {
  static final _iconCache = ExpiringCache<String, Uint8List?>(const Duration(minutes: 5));

  final String id; //应用包名
  final String name; //应用名称
  final String path;
  final String? os;

  Uint8List? icon;
  String? remoteHost;
  int? remotePost;

  ProcessInfo(this.id, this.name, this.path, {required this.os, this.icon, this.remoteHost, this.remotePost});

  factory ProcessInfo.fromJson(Map<String, dynamic> json) {
    return ProcessInfo(json['id'], json['name'], json['path'], os: json['os']);
  }

  bool get hasCacheIcon => icon != null || _iconCache.get(id) != null;

  Uint8List? get cacheIcon => icon ?? _iconCache.get(id);

  Future<Uint8List> getIcon() async {
    if (icon != null) return icon!;
    if (_iconCache.get(id) != null) return _iconCache.get(id)!;
    try {
      if (Platform.isAndroid) {
        icon = (await InstalledApps.getAppInfo(id)).icon;
      }

      if ('windows' == os || path.endsWith('.exe')) {
        icon = await _getWindowsIcon(path);
      }

      if (Platform.isMacOS) {
        var macIcon = await _getMacIcon(path);
        icon = await File(macIcon).readAsBytes();
      }

      icon = icon ?? Uint8List(0);
      _iconCache.set(id, icon);
    } catch (e) {
      icon = Uint8List(0);
    }
    return icon!;
  }

  Future<Uint8List?> _getWindowsIcon(String path) async {
    return await WinIcons().extractFileIcon(path);
  }

  static Future<String> _getMacIcon(String path) async {
    var xml = await File('$path/Contents/Info.plist').readAsString();
    var key = "<key>CFBundleIconFile</key>";
    var indexOf = xml.indexOf(key);
    var iconName = xml.substring(indexOf + key.length, xml.indexOf("</string>", indexOf));
    iconName = iconName.trim().replaceAll("<string>", "");
    var icon = iconName.endsWith(".icns") ? iconName : "$iconName.icns";
    String iconPath = "$path/Contents/Resources/$icon";
    return iconPath;
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'path': path, 'os': os};
  }

  @override
  String toString() {
    return toJson().toString();
  }
}
