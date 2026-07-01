import 'dart:async';

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/app_update/desktop_update_service.dart';
import 'package:proxypin/ui/app_update/remote_version_entity.dart';
import 'package:proxypin/utils/navigator.dart';
import 'package:url_launcher/url_launcher.dart';

/// 桌面端更新进度对话框。参考 ssrdog 项目实现。
/// 通用按钮文案复用 AppLocalizations, 状态提示长句内联中英文(参考 desktop_tray.dart)。
class DesktopUpdateDialog extends StatelessWidget {
  final RemoteVersionEntity version;
  final ReleaseAsset asset;

  static bool _backgroundDownload = false;
  static VoidCallback? _backgroundListener;

  const DesktopUpdateDialog({super.key, required this.version, required this.asset});

  static String _t(BuildContext context, String zh, String en) {
    return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
  }

  /// 移除残留的后台下载监听器(如有)。
  static void _clearBackgroundListener() {
    if (_backgroundListener != null) {
      DesktopUpdateService.instance.state.removeListener(_backgroundListener!);
      _backgroundListener = null;
    }
  }

  static Future<void> show(BuildContext context, RemoteVersionEntity version, ReleaseAsset asset) async {
    if (!context.mounted) return;
    _backgroundDownload = false;
    _clearBackgroundListener();
    await _showStateDialog(context, version, asset);
  }

  static Future<void> _showStateDialog(BuildContext context, RemoteVersionEntity version, ReleaseAsset asset) async {
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => DesktopUpdateDialog(version: version, asset: asset),
    );
  }

  void _downloadInBackground(BuildContext context) {
    _backgroundDownload = true;
    final service = DesktopUpdateService.instance;

    // 移除旧监听
    _clearBackgroundListener();

    void listener() {
      if (!_backgroundDownload) return;
      final state = service.state.value;
      if (state.phase == DesktopUpdatePhase.readyToInstall ||
          state.phase == DesktopUpdatePhase.failed ||
          state.phase == DesktopUpdatePhase.cancelled) {
        _backgroundDownload = false;
        _clearBackgroundListener();

        Future.delayed(const Duration(milliseconds: 200), () {
          final ctx = NavigatorHelper().navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            _showStateDialog(ctx, version, asset);
          }
        });
      }
    }

    _backgroundListener = listener;
    service.state.addListener(listener);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final service = DesktopUpdateService.instance;
    final localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.appUpdateDialogTitle),
      content: ValueListenableBuilder<DesktopUpdateState>(
        valueListenable: service.state,
        builder: (context, state, _) {
          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 230, maxWidth: 380, minWidth: 300),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_message(context, state)),
                  const SizedBox(height: 16),
                  if (_isBusy(state.phase)) ...[
                    if (state.phase == DesktopUpdatePhase.downloading)
                      LinearProgressIndicator(value: state.progress)
                    else
                      const LinearProgressIndicator(),
                    const SizedBox(height: 10),
                    Text(
                      _progressText(state),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
                    ),
                  ],
                  if (state.phase == DesktopUpdatePhase.failed && (state.errorMessage ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      state.errorMessage!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  if (state.phase == DesktopUpdatePhase.readyToInstall) ...[
                    const SizedBox(height: 10),
                    Text(
                      _t(context, '应用将退出并重启以完成更新。', 'The app will quit and restart to complete the update.'),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
      actions: [
        ValueListenableBuilder<DesktopUpdateState>(
          valueListenable: service.state,
          builder: (context, state, _) {
            if (state.phase == DesktopUpdatePhase.readyToInstall) {
              return Wrap(spacing: 8, alignment: WrapAlignment.end, children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(localizations.appUpdateLaterBtnTxt),
                ),
                FilledButton(
                  onPressed: service.installAndQuit,
                  child: Text(localizations.appUpdateInstallNow),
                ),
              ]);
            }

            if (state.phase == DesktopUpdatePhase.failed) {
              return Wrap(spacing: 8, alignment: WrapAlignment.end, children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(localizations.cancel),
                ),
                TextButton(
                  onPressed: _openDownloadPage,
                  child: Text(localizations.appUpdateOpenDownloadPage),
                ),
                FilledButton(
                  onPressed: () => service.start(version, asset),
                  child: Text(localizations.appUpdateRetry),
                ),
              ]);
            }

            if (state.phase == DesktopUpdatePhase.cancelled) {
              return TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(localizations.close),
              );
            }

            if (state.phase == DesktopUpdatePhase.downloading) {
              return Wrap(spacing: 8, alignment: WrapAlignment.end, children: [
                TextButton(
                  onPressed: () => _downloadInBackground(context),
                  child: Text(localizations.appUpdateBackgroundDownload),
                ),
                TextButton(
                  onPressed: service.cancel,
                  child: Text(localizations.cancel),
                ),
              ]);
            }

            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }

  bool _isBusy(DesktopUpdatePhase phase) {
    return phase == DesktopUpdatePhase.downloading || phase == DesktopUpdatePhase.launchingInstaller;
  }

  String _message(BuildContext context, DesktopUpdateState state) {
    switch (state.phase) {
      case DesktopUpdatePhase.idle:
        return _t(context, '正在准备更新...', 'Preparing update...');
      case DesktopUpdatePhase.downloading:
        return _t(context, '正在下载更新...', 'Downloading update...');
      case DesktopUpdatePhase.readyToInstall:
        return _t(context, '更新已下载完成，可立即安装', 'Update downloaded and ready to install');
      case DesktopUpdatePhase.launchingInstaller:
        return _t(context, '正在启动安装...', 'Launching installer...');
      case DesktopUpdatePhase.failed:
        return _t(context, '更新失败', 'Update failed');
      case DesktopUpdatePhase.cancelled:
        return _t(context, '更新已取消', 'Update cancelled');
    }
  }

  String _progressText(DesktopUpdateState state) {
    final received = _formatBytes(state.receivedBytes);
    final total = state.totalBytes != null && state.totalBytes! > 0 ? _formatBytes(state.totalBytes!) : '--';
    final percent = state.progress != null ? ' ${(state.progress! * 100).clamp(0, 100).toStringAsFixed(0)}%' : '';
    return '$received / $total$percent';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)}GB';
  }

  Future<void> _openDownloadPage() async {
    final uri = Uri.tryParse(version.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// 入口：启动下载并展示进度对话框。
Future<void> showDesktopUpdateDialog(BuildContext context, RemoteVersionEntity version, ReleaseAsset asset) async {
  final service = DesktopUpdateService.instance;
  unawaited(service.start(version, asset));
  if (!context.mounted) return;
  await DesktopUpdateDialog.show(context, version, asset);
}
