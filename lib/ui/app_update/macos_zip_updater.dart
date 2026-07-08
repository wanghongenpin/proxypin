import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/utils/desktop_tray.dart';
import 'package:window_manager/window_manager.dart';

/// macOS 原地更新：解压新版本 .app -> 等待当前进程退出 -> 替换 -> 重启。
/// 参考 ssrdog 项目实现。
class MacosZipUpdater {
  static bool _updating = false;

  static Future<bool> install(String version, File zipFile) async {
    if (!Platform.isMacOS || _updating) {
      return false;
    }

    _updating = true;
    Directory? stagingDir;

    try {
      final currentApp = _currentAppBundle();
      if (currentApp == null) {
        logger.w('MacosZipUpdater current app bundle not found');
        return false;
      }

      if (_isTranslocated(currentApp)) {
        logger.w('MacosZipUpdater app is translocated: ${currentApp.path}');
        return false;
      }

      final parent = currentApp.parent;
      final needsAuthorization = !await _canWrite(parent);
      if (needsAuthorization) {
        logger.w('MacosZipUpdater app parent needs authorization: ${parent.path}');
      }

      if (!await zipFile.exists()) {
        logger.w('MacosZipUpdater zip file not found: ${zipFile.path}');
        return false;
      }

      stagingDir = await _createStagingDir(version);
      final extractDir = Directory('${stagingDir.path}${Platform.pathSeparator}extracted');
      await _extractZip(zipFile, extractDir);

      final stagedApp = await _findStagedApp(extractDir);
      await _validateStagedApp(stagedApp);
      await _deleteFile(zipFile);

      final helper = await _writeHelperScript(stagingDir: stagingDir);
      final helperArgs = [
        helper.path,
        pid.toString(),
        stagedApp.path,
        currentApp.path,
        '${currentApp.path}.backup',
        '${currentApp.path}.new',
        stagingDir.path,
      ];

      if (needsAuthorization) {
        await _startHelperWithAuthorization(helperArgs);
      } else {
        await Process.start(
          '/bin/sh',
          helperArgs,
          mode: ProcessStartMode.detached,
        );
      }

      await _quitApp();
      return true;
    } catch (e, stackTrace) {
      logger.e('MacosZipUpdater failed', error: e, stackTrace: stackTrace);
      if (stagingDir != null) {
        try {
          await stagingDir.delete(recursive: true);
        } catch (_) {}
      }
      return false;
    } finally {
      _updating = false;
    }
  }

  static Future<void> _quitApp() async {
    try {
      await DesktopTrayManager.instance.exitApp();
    } catch (_) {}
    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  static Directory? _currentAppBundle() {
    var dir = File(Platform.resolvedExecutable).parent;
    while (dir.path != dir.parent.path) {
      if (dir.path.endsWith('.app')) {
        return dir;
      }
      dir = dir.parent;
    }
    return null;
  }

  static bool _isTranslocated(Directory app) {
    return app.path.contains('/AppTranslocation/');
  }

  static Future<bool> _canWrite(Directory directory) async {
    try {
      final probe = File('${directory.path}${Platform.pathSeparator}.proxypin-update-probe');
      await probe.writeAsString('probe');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<Directory> _createStagingDir(String version) async {
    final base = await getApplicationSupportDirectory();
    final safeVersion = version.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}updates${Platform.pathSeparator}$safeVersion',
    );
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
    return dir;
  }

  static Future<void> _extractZip(File zipFile, Directory extractDir) async {
    if (await extractDir.exists()) {
      await extractDir.delete(recursive: true);
    }
    await extractDir.create(recursive: true);

    final result = await Process.run('/usr/bin/ditto', [
      '-x',
      '-k',
      zipFile.path,
      extractDir.path,
    ]);

    if (result.exitCode != 0) {
      throw MacosZipUpdateException('解压更新包失败: ${result.stderr ?? result.stdout}');
    }
  }

  static Future<Directory> _findStagedApp(Directory extractDir) async {
    final apps = <Directory>[];

    await for (final entity in extractDir.list(recursive: true, followLinks: false)) {
      if (entity is Directory && entity.path.endsWith('.app')) {
        apps.add(entity);
      }
    }

    if (apps.isEmpty) {
      throw MacosZipUpdateException('更新包中未找到 App');
    }

    final named = apps.where((app) => app.path.endsWith('${Platform.pathSeparator}ProxyPin.app')).toList();
    if (named.length == 1) {
      return named.first;
    }

    if (apps.length == 1) {
      return apps.first;
    }

    throw MacosZipUpdateException('更新包中包含多个 App，无法确认安装目标');
  }

  static Future<void> _validateStagedApp(Directory app) async {
    final infoPlist = File('${app.path}${Platform.pathSeparator}Contents${Platform.pathSeparator}Info.plist');
    final executable = File(
        '${app.path}${Platform.pathSeparator}Contents${Platform.pathSeparator}MacOS${Platform.pathSeparator}ProxyPin');

    if (!await infoPlist.exists() || !await executable.exists()) {
      throw MacosZipUpdateException('更新包 App 结构无效');
    }
  }

  static Future<void> _startHelperWithAuthorization(List<String> helperArgs) async {
    final command = '/usr/bin/nohup /bin/sh ${helperArgs.map(_shellQuote).join(' ')} >/dev/null 2>&1 &';
    final script = 'do shell script ${_appleScriptString(command)} with administrator privileges';
    final result = await Process.run('/usr/bin/osascript', ['-e', script]);

    if (result.exitCode != 0) {
      throw MacosZipUpdateException('用户取消授权或授权安装失败');
    }
  }

  static Future<void> _deleteFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      logger.w('MacosZipUpdater failed to delete zip file: ${file.path} $e');
    }
  }

  static Future<File> _writeHelperScript({required Directory stagingDir}) async {
    final script = File('${stagingDir.path}${Platform.pathSeparator}install_update.sh');
    final logPath = _shellQuote('${stagingDir.path}${Platform.pathSeparator}install.log');

    await script.writeAsString('''#!/bin/sh
set -eu

PID="\$1"
STAGED_APP="\$2"
TARGET_APP="\$3"
BACKUP_APP="\$4"
NEW_APP="\$5"
STAGING_DIR="\$6"
LOG=$logPath

exec >> "\$LOG" 2>&1

echo "waiting for pid \$PID"
while kill -0 "\$PID" 2>/dev/null; do
  sleep 0.2
done

echo "installing update"
rm -rf "\$NEW_APP"
rm -rf "\$BACKUP_APP"

/usr/bin/ditto "\$STAGED_APP" "\$NEW_APP"

if [ -d "\$TARGET_APP" ]; then
  /bin/mv "\$TARGET_APP" "\$BACKUP_APP"
fi

if /bin/mv "\$NEW_APP" "\$TARGET_APP"; then
  /usr/bin/open "\$TARGET_APP"
  rm -rf "\$BACKUP_APP"
  rm -rf "\$STAGING_DIR"
  exit 0
fi

echo "install failed, rolling back"
if [ -d "\$BACKUP_APP" ]; then
  /bin/mv "\$BACKUP_APP" "\$TARGET_APP"
  /usr/bin/open "\$TARGET_APP"
fi
exit 1
''');

    await Process.run('/bin/chmod', ['+x', script.path]);
    return script;
  }

  static String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  static String _appleScriptString(String value) {
    final escaped = value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    return '"$escaped"';
  }
}

class MacosZipUpdateException implements Exception {
  final String message;

  MacosZipUpdateException(this.message);

  @override
  String toString() => message;
}
