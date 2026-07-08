import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/utils/desktop_tray.dart';

/// Windows 原地更新：解压 zip -> 启动 helper 脚本 -> 等待当前进程退出 -> robocopy 覆盖 -> 重启。
class WindowsZipUpdater {
  static bool _updating = false;

  /// 持久化日志文件(位于 updates 目录, 不随 staging 删除), 便于排查静默失败。
  static Future<File> _logFile() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}updates');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}install.log');
  }

  static Future<void> _log(File logFile, String msg) async {
    final line = '[${DateTime.now().toIso8601String()}] [dart] $msg\n';
    try {
      await logFile.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (_) {}
    logger.i('WindowsZipUpdater: $msg');
  }

  static Future<bool> install(String version, File zipFile) async {
    if (!Platform.isWindows || _updating) {
      return false;
    }

    _updating = true;
    Directory? stagingDir;
    final logFile = await _logFile();
    await _log(logFile, '==== install start version=$version zip=${zipFile.path} ====');

    try {
      if (!await zipFile.exists()) {
        await _log(logFile, 'zip file not found: ${zipFile.path}');
        return false;
      }

      final currentExe = File(Platform.resolvedExecutable);
      if (!await currentExe.exists()) {
        await _log(logFile, 'current exe not found: ${currentExe.path}');
        return false;
      }

      final targetDir = currentExe.parent;
      final needsAuth = _needsAuthorization(targetDir);
      await _log(logFile, 'currentExe=${currentExe.path}');
      await _log(logFile, 'targetDir=${targetDir.path} needsAuth=$needsAuth pid=$pid');

      stagingDir = await _createStagingDir(version);
      final extractDir = Directory('${stagingDir.path}${Platform.pathSeparator}extracted');
      await _extractZip(zipFile, extractDir);
      await _log(logFile, 'extracted to ${extractDir.path}');

      final stagedExe = await _findStagedExe(extractDir);
      final stagedRoot = _stagedRoot(extractDir, stagedExe);
      await _log(logFile, 'stagedExe=${stagedExe.path} stagedRoot=${stagedRoot.path}');

      final helper = await _writeHelperScript(stagingDir: stagingDir, logPath: logFile.path);
      await _log(logFile, 'helper bat written: ${helper.path}');

      // 先清理托盘图标(不销毁窗口, 避免在启动 helper 前进程被终止)
      try {
        await DesktopTrayManager.instance.exitApp();
      } catch (_) {}

      final args = [
        pid.toString(),
        stagedRoot.path,
        targetDir.path,
        currentExe.path,
        stagingDir.path,
      ];

      await _launchHelper(logFile: logFile, helper: helper, args: args, needsAuth: needsAuth);
      await _log(logFile, 'helper launched, exiting app');

      exit(0);
    } catch (e, stackTrace) {
      await _log(logFile, 'FAILED: $e\n$stackTrace');
      logger.e('WindowsZipUpdater failed', error: e, stackTrace: stackTrace);
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

  /// 启动 helper 脚本。
  /// 实测: 直接运行 bat 可靠(会执行), 而 powershell Start-Process 不会真正拉起 bat。
  /// 普通情况用 cmd start /min 最小化运行以减少黑窗口打扰;
  /// 需要提权(安装在 Program Files)时用 powershell Start-Process -Verb RunAs 触发 UAC。
  static Future<void> _launchHelper({
    required File logFile,
    required File helper,
    required List<String> args,
    required bool needsAuth,
  }) async {
    if (needsAuth) {
      String psQuote(String s) => "'${s.replaceAll("'", "''")}'";
      final argList = args.map(psQuote).join(',');
      final psCmd =
          'Start-Process -FilePath ${psQuote(helper.path)} -ArgumentList $argList -Verb RunAs -WindowStyle Hidden';
      await _log(logFile, 'launch via powershell runas: $psCmd');
      await Process.start(
        'powershell.exe',
        ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', psCmd],
        mode: ProcessStartMode.detached,
      );
      return;
    }

    // 普通情况: 通过 cmd start /min 最小化启动 bat(直接运行已证明可靠)。
    await _log(logFile, 'launch bat via cmd start /min: ${helper.path} args=$args');
    await Process.start(
      'cmd.exe',
      ['/c', 'start', '', '/min', helper.path, ...args],
      mode: ProcessStartMode.detached,
    );
  }

  static Future<Directory> _createStagingDir(String version) async {
    final base = await getApplicationSupportDirectory();
    final safeVersion = version.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final dir = Directory(
        '${base.path}${Platform.pathSeparator}updates${Platform.pathSeparator}windows-$safeVersion');
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

    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      final outputPath = _safeOutputPath(extractDir, file.name);
      if (outputPath == null) continue;

      if (file.isFile) {
        await File(outputPath).parent.create(recursive: true);
        final output = OutputFileStream(outputPath);
        file.writeContent(output);
        await output.close();
      } else {
        await Directory(outputPath).create(recursive: true);
      }
    }
  }

  static String? _safeOutputPath(Directory root, String name) {
    final normalized = name
        .replaceAll('\\', Platform.pathSeparator)
        .replaceAll('/', Platform.pathSeparator);
    if (normalized.startsWith(Platform.pathSeparator) ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
        normalized.split(Platform.pathSeparator).contains('..')) {
      return null;
    }
    return '${root.path}${Platform.pathSeparator}$normalized';
  }

  static Future<File> _findStagedExe(Directory extractDir) async {
    final exes = <File>[];

    await for (final entity in extractDir.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.exe')) {
        exes.add(entity);
      }
    }

    if (exes.isEmpty) {
      throw WindowsZipUpdateException('更新包中未找到 exe');
    }

    final named = exes.where((exe) {
      final name = exe.uri.pathSegments.isNotEmpty ? exe.uri.pathSegments.last.toLowerCase() : '';
      return name == 'proxypin.exe' || name.contains('proxypin');
    }).toList();
    if (named.isNotEmpty) {
      return named.first;
    }

    if (exes.length == 1) {
      return exes.first;
    }

    throw WindowsZipUpdateException('更新包中包含多个 exe，无法确认启动目标');
  }

  static Directory _stagedRoot(Directory extractDir, File stagedExe) {
    final parent = stagedExe.parent;
    if (parent.parent.path == extractDir.path) {
      return parent;
    }
    return extractDir;
  }

  static bool _needsAuthorization(Directory targetDir) {
    final path = targetDir.path.toLowerCase();
    return path.contains('\\program files') || path.contains('\\program files (x86)');
  }

  static Future<File> _writeHelperScript({required Directory stagingDir, required String logPath}) async {
    final script = File('${stagingDir.path}${Platform.pathSeparator}update_helper.bat');

    await script.writeAsString('''@echo off
chcp 65001 >nul
setlocal EnableExtensions
set "PID=%~1"
set "STAGED_ROOT=%~2"
set "TARGET_DIR=%~3"
set "TARGET_EXE=%~4"
set "STAGING_DIR=%~5"
set "LOG=$logPath"

echo [%DATE% %TIME%] [bat] start pid=%PID% >> "%LOG%" 2>&1
echo [%DATE% %TIME%] [bat] staged=%STAGED_ROOT% >> "%LOG%" 2>&1
echo [%DATE% %TIME%] [bat] target=%TARGET_DIR% >> "%LOG%" 2>&1

set /a WAIT=0
:wait_loop
tasklist /FI "PID eq %PID%" 2>nul | find /I "%PID%" >nul
if not "%ERRORLEVEL%"=="0" goto do_copy
set /a WAIT+=1
if %WAIT% GEQ 120 goto do_copy
ping -n 2 127.0.0.1 >nul
goto wait_loop

:do_copy
echo [%DATE% %TIME%] [bat] pid gone (waited %WAIT%), copying >> "%LOG%" 2>&1
set /a TRY=0
:copy_loop
robocopy "%STAGED_ROOT%" "%TARGET_DIR%" /E /IS /IT /R:3 /W:1 >> "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
if %RC% LSS 8 goto copy_ok
set /a TRY+=1
echo [%DATE% %TIME%] [bat] robocopy failed rc=%RC% try=%TRY% >> "%LOG%" 2>&1
if %TRY% GEQ 5 goto copy_fail
ping -n 3 127.0.0.1 >nul
goto copy_loop

:copy_fail
echo [%DATE% %TIME%] [bat] copy failed permanently >> "%LOG%" 2>&1
exit /B 1

:copy_ok
echo [%DATE% %TIME%] [bat] copy ok rc=%RC%, restarting %TARGET_EXE% >> "%LOG%" 2>&1
start "" /D "%TARGET_DIR%" "%TARGET_EXE%"
echo [%DATE% %TIME%] [bat] restart issued, cleaning staging >> "%LOG%" 2>&1
cd /d "%TARGET_DIR%"
rmdir /S /Q "%STAGING_DIR%"
exit /B 0
''');

    return script;
  }
}

class WindowsZipUpdateException implements Exception {
  final String message;

  WindowsZipUpdateException(this.message);

  @override
  String toString() => message;
}
