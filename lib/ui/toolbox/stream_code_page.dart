import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/stream_code_manager.dart';
import 'package:proxypin/network/components/stream_code/stream_code_data.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/desktop/desktop.dart';
import 'package:proxypin/ui/mobile/mobile.dart';
import 'package:proxypin/utils/listenable_list.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:intl/intl.dart';

/// Stream code extractor page
/// Displays captured Douyin live streaming push codes with copy and refresh functionality
class StreamCodePage extends StatefulWidget {
  final int? windowId;
  final ListenableList<HttpRequest>? trafficContainer;

  const StreamCodePage({super.key, this.windowId, this.trafficContainer});

  @override
  State<StatefulWidget> createState() {
    return _StreamCodePageState();
  }
}

class _StreamCodePageState extends State<StreamCodePage> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  StreamCodeManager? _manager;
  bool _isRefreshing = false;
  bool _isExtracting = false;

  @override
  void initState() {
    super.initState();
    _initManager();

    if (Platforms.isDesktop() && widget.windowId != null) {
      HardwareKeyboard.instance.addHandler(onKeyEvent);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(onKeyEvent);
    super.dispose();
  }

  Future<void> _initManager() async {
    try {
      _manager = await StreamCodeManager.instance;
      // Clean up old data on page open
      await _manager!.cleanupOldData();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Failed to initialize StreamCodeManager: $e');
    }
  }

  bool onKeyEvent(KeyEvent event) {
    if (widget.windowId == null) return false;
    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      HardwareKeyboard.instance.removeHandler(onKeyEvent);
      WindowController.fromWindowId(widget.windowId!).close();
      return true;
    }

    return false;
  }

  Future<void> _handleRefresh() async {
    if (_manager == null || _isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      await _manager!.refreshStreamCode();
      if (mounted) {
        _showNotification(localizations.refreshSuccess);
      }
    } on Exception catch (e) {
      if (mounted) {
        _showNotification(e.toString().replaceFirst('Exception: ', ''), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      _showNotification('${localizations.copied} $label');
    }
  }

  void _showNotification(String message, {bool isError = false}) {
    if (Platforms.isMobile()) {
      FlutterToastr.show(message, context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : null,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: Platforms.isMobile()
          ? AppBar(
              title: Text(localizations.streamCodeExtractor, style: const TextStyle(fontSize: 16)),
              centerTitle: true,
            )
          : null,
      body: _manager == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(Platforms.isDesktop() ? 24.0 : 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildManualExtractButton(),
                  const SizedBox(height: 24),
                  ValueListenableBuilder<StreamCodeData?>(
                    valueListenable: _manager!.lastStreamCodeNotifier,
                    builder: (context, streamCode, child) {
                      if (streamCode == null) {
                        return _buildEmptyState();
                      }
                      return _buildStreamCodeDisplay(streamCode);
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _handleManualExtract() async {
    if (_manager == null || _isExtracting) return;

    // Auto-detect the appropriate traffic container based on platform
    final ListenableList<HttpRequest> container;
    if (widget.trafficContainer != null) {
      // Use provided container (typically mobile)
      container = widget.trafficContainer!;
    } else if (Platforms.isDesktop()) {
      // Access desktop container via DesktopApp
      container = DesktopApp.container;
    } else {
      // Fallback to mobile container if not provided
      container = MobileApp.container;
    }

    if (container.source.isEmpty) {
      _showNotification('无可用流量数据\n请先抓取网络请求', isError: true);
      return;
    }

    setState(() {
      _isExtracting = true;
    });

    try {
      await _manager!.extractFromTraffic(container.source);
      if (mounted) {
        _showNotification(localizations.extractSuccess);
      }
    } on Exception catch (e) {
      if (mounted) {
        _showNotification(e.toString().replaceFirst('Exception: ', ''), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExtracting = false;
        });
      }
    }
  }

  Widget _buildManualExtractButton() {
    // In desktop multi-window mode, extraction happens in main window
    // Don't show button in multi-window mode
    if (widget.windowId != null && Platforms.isDesktop()) {
      return const SizedBox.shrink();
    }

    // Normal mode: show extract button
    return Center(
      child: ElevatedButton.icon(
        onPressed: _isExtracting ? null : _handleManualExtract,
        icon: _isExtracting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.search, size: 18),
        label: Text(localizations.getStreamCode),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildImageWithFallback(String? imageUrl, IconData fallbackIcon, {double size = 60}) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          fallbackIcon,
          size: size * 0.5,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                      : null,
                ),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              fallbackIcon,
              size: size * 0.5,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAccountSection(StreamCodeData data) {
    if (data.accountNickname == null && data.accountAvatarUrl == null) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            _buildImageWithFallback(data.accountAvatarUrl, Icons.person),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.accountNickname ?? localizations.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (data.accountShortId != null && data.accountShortId!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '抖音号: ${data.accountShortId}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.stream,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              localizations.noStreamCodeHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamCodeDisplay(StreamCodeData data) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final formattedDate = dateFormat.format(data.capturedAt);
    final hasRoomInfo = data.roomTitle != null || data.coverImageUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Account section (if available)
        _buildAccountSection(data),
        if (data.accountNickname != null || data.accountAvatarUrl != null)
          const SizedBox(height: 16),

        // Unified stream code card with optional live room header
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Live room header (if available)
                if (hasRoomInfo) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildImageWithFallback(data.coverImageUrl, Icons.live_tv, size: 80),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Room title (larger, bold)
                            Text(
                              data.roomTitle ?? localizations.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // Room ID (if available)
                            if (data.roomId != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      '${localizations.roomIdLabel}: ${data.roomId}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy_outlined, size: 16),
                                    onPressed: () => _copyToClipboard(data.roomId!, localizations.roomIdLabel),
                                    tooltip: '${localizations.copy} ${localizations.roomIdLabel}',
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                ],

                // Stream code section
                _buildStreamCodeRow(
                  localizations.pushAddress,
                  data.pushAddress,
                ),
                const SizedBox(height: 16),
                _buildStreamCodeRow(
                  localizations.streamKey,
                  data.streamKey,
                ),
                const SizedBox(height: 12),

                // Footer with timestamp and refresh button
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${localizations.lastUpdateTime}: $formattedDate',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _isRefreshing ? null : _handleRefresh,
                      icon: _isRefreshing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 16),
                      label: Text(localizations.refresh),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStreamCodeRow(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () => _copyToClipboard(value, label),
              tooltip: '${localizations.copy} $label',
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: SelectableText(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
