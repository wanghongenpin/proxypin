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

  Widget _buildImageWithFallback(String? imageUrl, IconData fallbackIcon) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          fallbackIcon,
          size: 32,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: 60,
            height: 60,
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
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              fallbackIcon,
              size: 32,
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
                    localizations.accountInfo,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.accountNickname ?? localizations.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveRoomSection(StreamCodeData data) {
    if (data.roomTitle == null && data.coverImageUrl == null) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            _buildImageWithFallback(data.coverImageUrl, Icons.live_tv),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizations.liveRoomInfo,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.roomTitle ?? localizations.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Account section (if available)
        _buildAccountSection(data),
        if (data.accountNickname != null || data.accountAvatarUrl != null)
          const SizedBox(height: 16),

        // Live room section (if available)
        _buildLiveRoomSection(data),
        if (data.roomTitle != null || data.coverImageUrl != null)
          const SizedBox(height: 16),

        // Timestamp
        Text(
          '${localizations.lastUpdateTime}: $formattedDate',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 16),

        // Stream code card
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStreamCodeRow(
                  localizations.pushAddress,
                  data.pushAddress,
                ),
                const SizedBox(height: 16),
                _buildStreamCodeRow(
                  localizations.streamKey,
                  data.streamKey,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Refresh button
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _isRefreshing ? null : _handleRefresh,
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(localizations.refresh),
            ),
            const Spacer(),
          ],
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
