import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/stream_code_manager.dart';
import 'package:proxypin/network/components/stream_code/stream_code_data.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:intl/intl.dart';

/// Stream code extractor page
/// Displays captured Douyin live streaming push codes with copy and refresh functionality
class StreamCodePage extends StatefulWidget {
  final int? windowId;

  const StreamCodePage({super.key, this.windowId});

  @override
  State<StatefulWidget> createState() {
    return _StreamCodePageState();
  }
}

class _StreamCodePageState extends State<StreamCodePage> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  StreamCodeManager? _manager;
  bool _isRefreshing = false;

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
                  if (Platforms.isDesktop()) ...[
                    Row(
                      children: [
                        Text(
                          localizations.streamCodeExtractor,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const Spacer(),
                        if (widget.windowId != null)
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              WindowController.fromWindowId(widget.windowId!).close();
                            },
                          ),
                      ],
                    ),
                    const Divider(),
                  ],
                  _buildAutoExtractToggle(),
                  const Divider(),
                  const SizedBox(height: 16),
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

  Widget _buildAutoExtractToggle() {
    return ValueListenableBuilder<bool>(
      valueListenable: _manager!.autoExtractEnabledNotifier,
      builder: (context, enabled, child) {
        return SwitchListTile(
          title: Text(localizations.autoExtract),
          subtitle: Text(localizations.autoExtractDesc),
          value: enabled,
          onChanged: (value) async {
            await _manager!.setAutoExtractEnabled(value);
          },
        );
      },
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
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              localizations.noStreamCodeHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
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
        Text(
          '${localizations.lastUpdateTime}: $formattedDate',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 16),
        _buildStreamCodeRow(
          localizations.pushAddress,
          data.pushAddress,
        ),
        const SizedBox(height: 16),
        _buildStreamCodeRow(
          localizations.streamKey,
          data.streamKey,
        ),
        const SizedBox(height: 24),
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
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: SelectableText(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
