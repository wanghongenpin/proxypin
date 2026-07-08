import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/app_update/macos_zip_updater.dart';
import 'package:proxypin/ui/app_update/remote_version_entity.dart';
import 'package:proxypin/ui/app_update/windows_zip_updater.dart';
import 'package:proxypin/utils/desktop_tray.dart';
import 'package:window_manager/window_manager.dart';

enum DesktopUpdatePhase {
  idle,
  downloading,
  readyToInstall,
  launchingInstaller,
  failed,
  cancelled,
}

class DesktopUpdateState {
  final DesktopUpdatePhase phase;
  final RemoteVersionEntity? version;
  final ReleaseAsset? asset;
  final double? progress;
  final int receivedBytes;
  final int? totalBytes;
  final String? filePath;
  final String? errorMessage;

  const DesktopUpdateState({
    required this.phase,
    this.version,
    this.asset,
    this.progress,
    this.receivedBytes = 0,
    this.totalBytes,
    this.filePath,
    this.errorMessage,
  });

  factory DesktopUpdateState.idle() => const DesktopUpdateState(phase: DesktopUpdatePhase.idle);

  DesktopUpdateState copyWith({
    DesktopUpdatePhase? phase,
    RemoteVersionEntity? version,
    ReleaseAsset? asset,
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    String? filePath,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DesktopUpdateState(
      phase: phase ?? this.phase,
      version: version ?? this.version,
      asset: asset ?? this.asset,
      progress: progress ?? this.progress,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      filePath: filePath ?? this.filePath,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// 桌面端应用内更新服务：下载安装包(带进度) -> 原地安装/打开。
/// 参考 ssrdog 项目实现，下载改用 dart:io HttpClient。
class DesktopUpdateService {
  DesktopUpdateService._();

  static final DesktopUpdateService instance = DesktopUpdateService._();

  final ValueNotifier<DesktopUpdateState> state = ValueNotifier(DesktopUpdateState.idle());

  bool _updating = false;
  bool _cancelRequested = false;
  HttpClient? _httpClient;

  /// 桌面专属功能, 文案内联中英文(参考 desktop_tray.dart)。
  static String _t(String zh, String en) => Platform.localeName.startsWith('zh') ? zh : en;

  static bool _isInPlaceZip(ReleaseAsset asset) {
    return asset.installerType == 'zip' && (Platform.isMacOS || Platform.isWindows);
  }

  Future<void> start(RemoteVersionEntity version, ReleaseAsset asset) async {
    if (_updating) {
      return;
    }

    _updating = true;
    _cancelRequested = false;
    state.value = DesktopUpdateState(phase: DesktopUpdatePhase.downloading, version: version, asset: asset);

    HttpClient? client;
    File? tempFile;
    try {
      final uri = Uri.tryParse(asset.downloadUrl);
      if (uri == null) {
        throw DesktopUpdateException(_t('下载地址无效', 'Invalid download URL'));
      }

      final directory = await _updateDirectory();
      final fileName = _safeFileName(version.version, asset.installerType);
      final targetFile = File('${directory.path}${Platform.pathSeparator}$fileName');
      await _cleanupUpdateDirectory(directory, keepFileName: fileName);

      // 已存在且大小匹配, 直接进入待安装
      if (await targetFile.exists() && await _verifyFile(targetFile, asset.size)) {
        final len = await targetFile.length();
        state.value = state.value.copyWith(
          phase: DesktopUpdatePhase.readyToInstall,
          progress: 1,
          receivedBytes: len,
          totalBytes: asset.size ?? len,
          filePath: targetFile.path,
          clearError: true,
        );
        return;
      }

      tempFile = File('${targetFile.path}.part');
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      state.value = state.value.copyWith(
        phase: DesktopUpdatePhase.downloading,
        progress: 0,
        receivedBytes: 0,
        totalBytes: asset.size,
        filePath: tempFile.path,
        clearError: true,
      );

      client = HttpClient();
      _httpClient = client;
      client.userAgent = 'ProxyPin-Updater';

      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw DesktopUpdateException(_t('下载失败 (HTTP ${response.statusCode})', 'Download failed (HTTP ${response.statusCode})'));
      }

      final totalBytes = response.contentLength > 0 ? response.contentLength : asset.size;
      var received = 0;
      final sink = tempFile.openWrite();
      try {
        await for (final chunk in response) {
          if (_cancelRequested) {
            throw const _CancelledException();
          }
          sink.add(chunk);
          received += chunk.length;
          state.value = state.value.copyWith(
            phase: DesktopUpdatePhase.downloading,
            progress: totalBytes != null && totalBytes > 0 ? received / totalBytes : null,
            receivedBytes: received,
            totalBytes: totalBytes,
            filePath: tempFile.path,
            clearError: true,
          );
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      // 下载循环结束后再次确认未被取消, 避免取消后仍落地并覆盖 cancelled 状态。
      if (_cancelRequested) {
        throw const _CancelledException();
      }

      if (!await _verifyFile(tempFile, asset.size)) {
        await _deleteFile(tempFile.path);
        throw DesktopUpdateException(_t('下载文件校验失败', 'Downloaded file verification failed'));
      }

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);

      final len = await targetFile.length();
      state.value = state.value.copyWith(
        phase: DesktopUpdatePhase.readyToInstall,
        progress: 1,
        receivedBytes: len,
        totalBytes: asset.size ?? len,
        filePath: targetFile.path,
        clearError: true,
      );
    } on _CancelledException {
      await _deleteFile(tempFile?.path);
      state.value = state.value.copyWith(phase: DesktopUpdatePhase.cancelled);
    } on DesktopUpdateException catch (e) {
      await _deleteFile(tempFile?.path);
      state.value = state.value.copyWith(phase: DesktopUpdatePhase.failed, errorMessage: e.message);
    } catch (e, stackTrace) {
      logger.e('DesktopUpdateService download failed', error: e, stackTrace: stackTrace);
      await _deleteFile(tempFile?.path);
      state.value = state.value.copyWith(phase: DesktopUpdatePhase.failed, errorMessage: _t('下载失败: $e', 'Download failed: $e'));
    } finally {
      try {
        client?.close(force: true);
      } catch (_) {}
      _httpClient = null;
      _updating = false;
    }
  }

  Future<void> cancel() async {
    _cancelRequested = true;
    try {
      _httpClient?.close(force: true);
    } catch (_) {}
    state.value = state.value.copyWith(phase: DesktopUpdatePhase.cancelled);
  }

  /// 执行安装并退出/重启应用。
  Future<void> installAndQuit() async {
    final current = state.value;
    final version = current.version;
    final asset = current.asset;
    final filePath = current.filePath;
    if (version == null || asset == null || filePath == null || filePath.isEmpty) {
      state.value = current.copyWith(phase: DesktopUpdatePhase.failed, errorMessage: _t('安装文件缺失', 'Installer file missing'));
      return;
    }

    state.value = current.copyWith(phase: DesktopUpdatePhase.launchingInstaller);

    try {
      if (_isInPlaceZip(asset)) {
        final started = Platform.isMacOS
            ? await MacosZipUpdater.install(version.version, File(filePath))
            : await WindowsZipUpdater.install(version.version, File(filePath));
        if (!started) {
          state.value = state.value.copyWith(
            phase: DesktopUpdatePhase.failed,
            errorMessage: _t('原地更新失败, 请手动安装', 'In-place update failed, please install manually'),
          );
        }
        return;
      }

      // 非 zip(如 macOS dmg / Windows exe): 打开安装包后退出。
      await _openInstaller(filePath);
      await _quitApp();
    } catch (e, stackTrace) {
      logger.e('DesktopUpdateService install failed', error: e, stackTrace: stackTrace);
      state.value = state.value.copyWith(phase: DesktopUpdatePhase.failed, errorMessage: _t('安装启动失败: $e', 'Failed to launch installer: $e'));
    }
  }

  Future<void> _openInstaller(String filePath) async {
    if (Platform.isMacOS) {
      await Process.start('open', [filePath]);
    } else if (Platform.isWindows) {
      await Process.start(filePath, [], mode: ProcessStartMode.detached);
    } else {
      throw DesktopUpdateException(_t('当前平台不支持自动安装', 'Auto-install not supported on this platform'));
    }
  }

  Future<void> _quitApp() async {
    try {
      await DesktopTrayManager.instance.exitApp();
    } catch (_) {}
    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  Future<Directory> _updateDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final directory = Directory('${supportDir.path}${Platform.pathSeparator}updates');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<void> _cleanupUpdateDirectory(Directory directory, {required String keepFileName}) async {
    if (!await directory.exists()) return;

    await for (final entity in directory.list(followLinks: false)) {
      // 只清理同级文件, 保留目标文件和 .part, 不动子目录(staging)。
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isNotEmpty ? entity.uri.pathSegments.last : '';
      if (name == keepFileName || name == '$keepFileName.part') {
        continue;
      }
      await _deleteFile(entity.path);
    }
  }

  Future<void> _deleteFile(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      logger.w('DesktopUpdateService failed to delete update file: $filePath $e');
    }
  }

  String _safeFileName(String version, String installerType) {
    final ext = installerType.isEmpty ? 'bin' : installerType;
    final rawName = 'proxypin-${Platform.operatingSystem}-$version.$ext';
    return rawName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<bool> _verifyFile(File file, int? expectedSize) async {
    if (!await file.exists()) {
      return false;
    }

    if (expectedSize != null && expectedSize > 0) {
      final actualSize = await file.length();
      if (actualSize != expectedSize) {
        logger.w('DesktopUpdateService file size mismatch: $actualSize != $expectedSize');
        return false;
      }
    }

    return true;
  }
}

class DesktopUpdateException implements Exception {
  final String message;

  DesktopUpdateException(this.message);

  @override
  String toString() => message;
}

class _CancelledException implements Exception {
  const _CancelledException();
}
