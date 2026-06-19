import 'dart:io';

import 'package:path_provider/path_provider.dart';

class Paths {
  static String? _homePath;
  static final Map<String, File> _cache = {};

  /// Application support directory path, with macOS multi-window IPC handling.
  ///
  /// Previously duplicated in ScriptManager, RequestMapManager,
  /// HostsManager, and RequestBreakpointManager.
  static Future<String> homePath() async {
    if (_homePath != null) return _homePath!;

    _homePath = await getApplicationSupportDirectory().then((it) => it.path);
    return _homePath!;
  }

  //获取配置路径
  static Future<File> getPath(String fileName) async {
    if (_cache.containsKey(fileName)) {
      return _cache[fileName]!;
    }

    final directory = await getApplicationSupportDirectory();
    var file = File('${directory.path}${Platform.pathSeparator}$fileName');

    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    _cache[fileName] = file;
    return file;
  }

  static Future<File> createFile(String dir, String filename) async {
    final directory = await getApplicationSupportDirectory();
    var file = File('${directory.path}${Platform.pathSeparator}$dir${Platform.pathSeparator}$filename');
    return file.create(recursive: true);
  }
}
