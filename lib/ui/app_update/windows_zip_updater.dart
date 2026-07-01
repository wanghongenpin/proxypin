import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/utils/desktop_tray.dart';

/// Windows 原地更新：解压 zip -> 等待当前进程退出 -> xcopy 覆盖 -> 重启。
/// 参考 ssrdog 项目实现。
class WindowsZipUpdater {
  static bool _updating = false;

  static Future<bool> install(String version, File zipFile) async {
    if (!Platform.isWindows || _updating) {
      return false;
    }

    _updating = true;
    Directory? stagingDir;

    try {
      if (!await zipFile.exists()) {
        logger.w('WindowsZipUpdater zip file not found: ${zipFile.path}');
        return false;
      }

      final currentExe = File(Platform.resolvedExecutable);
      if (!await currentExe.exists()) {
        logger.w('WindowsZipUpdater current exe not found: ${currentExe.path}');
        return false;
      }

      final targetDir = currentExe.parent;
      stagingDir = await _createStagingDir(version);
      final extractDir = Directory('${stagingDir.path}${Platform.pathSeparator}extracted');
      await _extractZip(zipFile, extractDir);

      final stagedExe = await _findStagedExe(extractDir);
      final stagedRoot = _stagedRoot(extractDir, stagedExe);
      final helper = await _writeHelperScript(stagingDir: stagingDir);
      final launcher = await _writeLauncherScript(
        stagingDir: stagingDir,
        helper: helper,
        needsAuthorization: _needsAuthorization(targetDir),
      );

      // 先清理托盘图标(不销毁窗口, 避免在启动 helper 前进程被终止)
      try {
        await DesktopTrayManager.instance.exitApp();
      } catch (_) {}

      await Process.start(
        'wscript.exe',
        [
          launcher.path,
          pid.toString(),
          stagedRoot.path,
          targetDir.path,
          currentExe.path,
          stagingDir.path,
        ],
        mode: ProcessStartMode.detached,
      );

      exit(0);
    } catch (e, stackTrace) {
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

    final input = InputFileStream(zipFile.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
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
    } finally {
      await input.close();
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

  static Future<File> _writeHelperScript({required Directory stagingDir}) async {
    final script = File('${stagingDir.path}${Platform.pathSeparator}update_helper.bat');
    final logPath = '${stagingDir.path}${Platform.pathSeparator}install.log';

    await script.writeAsString('''@echo off
setlocal EnableExtensions
set "PID=%~1"
set "STAGED_ROOT=%~2"
set "TARGET_DIR=%~3"
set "TARGET_EXE=%~4"
set "STAGING_DIR=%~5"
set "LOG=$logPath"

echo waiting for pid %PID% >> "%LOG%" 2>&1
:wait_loop
tasklist /FI "PID eq %PID%" 2>nul | find /I "%PID%" >nul
if "%ERRORLEVEL%"=="0" (
  timeout /T 1 /NOBREAK >nul
  goto wait_loop
)

echo copying update >> "%LOG%" 2>&1
xcopy "%STAGED_ROOT%\\*" "%TARGET_DIR%\\" /E /I /Y /Q >> "%LOG%" 2>&1
if ERRORLEVEL 4 (
  echo xcopy failed >> "%LOG%" 2>&1
  exit /B 1
)

start "" "%TARGET_EXE%"
rmdir /S /Q "%STAGING_DIR%"
exit /B 0
''');

    return script;
  }

  static Future<File> _writeLauncherScript({
    required Directory stagingDir,
    required File helper,
    required bool needsAuthorization,
  }) async {
    final script = File('${stagingDir.path}${Platform.pathSeparator}update_silent.vbs');
    final verb = needsAuthorization ? 'runas' : '';
    await script.writeAsString('''Set objShell = CreateObject("Shell.Application")
Set args = WScript.Arguments
bat = "${_escapeVbs(helper.path)}"
params = """" & bat & """ "
For i = 0 To args.Count - 1
  params = params & """" & args(i) & """ "
Next
objShell.ShellExecute "cmd.exe", "/c " & params, "", "$verb", 0
''');
    return script;
  }

  static String _escapeVbs(String value) {
    return value.replaceAll('"', '""');
  }
}

class WindowsZipUpdateException implements Exception {
  final String message;

  WindowsZipUpdateException(this.message);

  @override
  String toString() => message;
}
