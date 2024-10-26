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
import 'package:proxypin/network/util/socket_address.dart';
import 'package:win32audio/win32audio.dart';

import 'cache.dart';

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

  static Future<ProcessInfo?> getProcessByPort(InetSocketAddress socketAddress, String cacheKeyPre) async {
    if (Platform.isAndroid) {
      var app = await ProcessInfoPlugin.getProcessByPort(socketAddress.host, socketAddress.port);
      if (app != null) {
        return app;
      }
      if (socketAddress.host == '127.0.0.1') return ProcessInfo('com.network.proxy', "ProxyPin", '');
      return null;
    }

    var pid = await _getPid(socketAddress);
    if (pid == null) return null;

    String cacheKey = "$cacheKeyPre:$pid";
    var processInfo = processInfoCache.get(cacheKey);
    if (processInfo != null) return processInfo;

    processInfo = await getProcess(pid);
    processInfoCache.set(cacheKey, processInfo!);
    return processInfo;
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
      var results =
          await Process.run('bash', ['-c', 'lsof -nP -iTCP:${socketAddress.port} |grep "${socketAddress.port}->"']);

      if (results.exitCode != 0) {
        return null;
      }

      var lines = LineSplitter.split(results.stdout);

      for (var line in lines) {
        var parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 9) {
          return int.tryParse(parts[1]);
        }
      }
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
      return ProcessInfo(name, name.split(".")[0], path);
    }

    if (Platform.isMacOS) {
      var results = await Process.run('bash', ['-c', 'ps -p $pid -o pid= -o comm=']);
      if (results.exitCode == 0) {
        var lines = LineSplitter.split(results.stdout);
        for (var line in lines) {
          var parts = line.trim().split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            parts.removeAt(0).trim();
            var path = parts.join(" ").split(".app/")[0];
            String name = path.substring(path.lastIndexOf('/') + 1);
            return ProcessInfo(name, name, "$path.app");
          }
        }
      }
    }

    return null;
  }
}

class ProcessInfo {
  static final _iconCache = ExpiringCache<String, Uint8List?>(const Duration(minutes: 5));

  final String id; //应用包名
  final String name; //应用名称
  final String path;

  Uint8List? icon;
  String? remoteHost;
  int? remotePost;

  ProcessInfo(this.id, this.name, this.path, {this.icon, this.remoteHost, this.remotePost});

  factory ProcessInfo.fromJson(Map<String, dynamic> json) {
    return ProcessInfo(json['id'], json['name'], json['path']);
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

      if (Platform.isWindows) {
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
    return {'id': id, 'name': name, 'path': path};
  }

  @override
  String toString() {
    return toJson().toString();
  }
}
