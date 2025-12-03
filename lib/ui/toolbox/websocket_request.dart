import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';

import '../../utils/platform.dart';
import '../component/app_dialog.dart';
import '../component/json/json_text.dart';
import '../component/json/json_viewer.dart';
import '../component/json/theme.dart';

/// Simple WebSocket request page: connect to ws/wss URL, send text, view messages
class WebSocketRequestPage extends StatefulWidget {
  final int? windowId; // optional for desktop multi-window
  const WebSocketRequestPage({super.key, this.windowId});

  @override
  State<WebSocketRequestPage> createState() => _WebSocketRequestPageState();
}

class _WebSocketRequestPageState extends State<WebSocketRequestPage> {
  final ScrollController _scrollController = ScrollController();
  bool _scrollScheduled = false;

  // whether the view is considered near the bottom. If false, auto-scroll is disabled
  bool _isNearBottom = true;
  static const double _autoScrollThreshold = 150.0;

  // key for the currently last message widget so we can ensureVisible it
  final GlobalKey _lastMessageKey = GlobalKey();

  // key for the input bar so we can position the jump button just above it
  final GlobalKey _inputBarKey = GlobalKey();
  final TextEditingController _urlController = TextEditingController(text: 'ws://');
  final TextEditingController _sendController = TextEditingController();
  final List<_WsMessage> _messages = [];

  WebSocket? _socket;
  StreamSubscription? _sub;
  bool _connecting = false;
  bool _connected = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    // listen to scroll changes to determine whether we should auto-scroll
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      final offset = _scrollController.offset;
      final near = (max - offset) <= _autoScrollThreshold;
      if (near != _isNearBottom) {
        setState(() {
          _isNearBottom = near;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _socket?.close();
    _scrollController.dispose();
    _urlController.dispose();
    _sendController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || !(url.startsWith('ws://') || url.startsWith('wss://'))) {
      CustomToast.error('Invalid URL').show(context);
      return;
    }
    setState(() {
      _connecting = true;
    });
    try {
      final socket = await WebSocket.connect(url);
      _socket = socket;
      _connected = true;
      _connecting = false;
      _listen();
      setState(() {});
      _addSys('Connected');
    } catch (e) {
      _connecting = false;
      _connected = false;
      setState(() {});
      _addSys('Connect failed: $e');
    }
  }

  void _listen() {
    _sub?.cancel();
    _sub = _socket?.listen((data) {
      // data can be String or List<int>
      if (data is String) {
        _messages.add(_WsMessage(false, utf8.encode(data), false, time: DateTime.now()));
      } else if (data is List<int>) {
        _messages.add(_WsMessage(false, List<int>.from(data), true, time: DateTime.now()));
      } else {
        _messages.add(_WsMessage(false, utf8.encode('$data'), false, time: DateTime.now()));
      }
      setState(() {});
      _scheduleScroll();
    }, onError: (error) {
      _addSys('Error: $error');
    }, onDone: () {
      _connected = false;
      setState(() {});
      _addSys('Closed');
    });
  }

  Future<void> _disconnect() async {
    try {
      await _socket?.close();
    } catch (_) {}
    _connected = false;
    setState(() {});
    _addSys('Disconnected');
  }

  void _sendText() {
    final text = _sendController.text.trim();
    if (!_connected || text.isEmpty) return;
    _socket?.add(text);
    _messages.add(_WsMessage(true, utf8.encode(text), false, time: DateTime.now()));
    _sendController.clear();
    setState(() {});
    _scheduleScroll();
  }

  Future<void> _sendFile() async {
    if (!_connected) return;
    try {
      String? path;
      if (Platforms.isMobile()) {
        final result = await FilePicker.platform.pickFiles(allowMultiple: false);
        if (result == null || result.files.isEmpty) return;
        path = result.files.single.path;
      } else {
        path = path = await DesktopMultiWindow.invokeMethod(0, "pickFiles");
        if (widget.windowId != null) WindowController.fromWindowId(widget.windowId!).show();
      }
      if (path == null) return;
      final file = File(path);
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;
      _socket?.add(bytes);
      _messages.add(_WsMessage(true, bytes.toList(), true, time: DateTime.now()));
      setState(() {});
      _scheduleScroll();
      if (mounted) {
        CustomToast.success(AppLocalizations.of(context)!.send).show(context);
      }
    } catch (e) {
      if (mounted) {
        CustomToast.error('Send file failed: $e').show(context);
      }
    }
  }

  void _addSys(String msg) {
    _messages.add(_WsMessage.system(msg));
    setState(() {});
    _scheduleScroll();
  }

  String _formatTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  String _formatSize(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(size < 10 ? 2 : 1)} ${units[unitIndex]}';
  }

  void _scheduleScroll() {
    // only auto-scroll when the user is already near the bottom
    if (!_isNearBottom) return;
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scrollScheduled = false;
      // give layout a bit more time to settle (helps when many messages are added quickly)
      await Future.delayed(const Duration(milliseconds: 120));
      // prefer Scrollable.ensureVisible on the last message for more natural behavior
      try {
        final ctx = _lastMessageKey.currentContext;
        if (ctx != null) {
          // use alignment slightly above bottom to avoid being hidden by input controls
          await Scrollable.ensureVisible(ctx,
              duration: const Duration(milliseconds: 350), curve: Curves.easeInOut, alignment: 0.9);
          return;
        }
      } catch (_) {}
      await _animateToBottom();
    });
  }

  Future<void> _animateToBottom() async {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    try {
      await _scrollController.animateTo(max - 10, duration: Duration(milliseconds: 350), curve: Curves.easeInOut);
    } catch (_) {
      try {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Use a Stack so we can place a custom-styled "jump to latest" button
    return Scaffold(
      appBar: AppBar(
          title: Text('WebSocket', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          centerTitle: true),
      body: Stack(children: [
        // main content
        Column(children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  decoration: InputDecoration(labelText: 'ws(s)://', border: const OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                  onPressed: _connecting ? null : (_connected ? _disconnect : _connect),
                  child: Text(_connected ? localizations.disconnect : localizations.connect)),
            ]),
          ),
          const Divider(height: 0),
          Expanded(child: _messageList(theme)),
          const Divider(height: 0, thickness: 0.2),
          Padding(
            key: _inputBarKey,
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              IconButton(
                icon: Icon(Icons.attach_file, color: theme.colorScheme.primary),
                onPressed: _connected ? _sendFile : null,
              ),

              const SizedBox(width: 4),
              Expanded(
                child: Shortcuts(
                  shortcuts: {
                    // Enter sends
                    SingleActivator(LogicalKeyboardKey.enter): const _SendIntent(),
                    // Ctrl+Enter inserts newline (also meta/cmd on macOS)
                    SingleActivator(LogicalKeyboardKey.enter, control: true): const _InsertNewlineIntent(),
                    SingleActivator(LogicalKeyboardKey.enter, meta: true): const _InsertNewlineIntent(),
                  },
                  child: Actions(
                    actions: {
                      _SendIntent: CallbackAction<_SendIntent>(onInvoke: (intent) {
                        if (_connected) _sendText();
                        return null;
                      }),
                      _InsertNewlineIntent: CallbackAction<_InsertNewlineIntent>(onInvoke: (intent) {
                        // Insert a newline at the current cursor position
                        final controller = _sendController;
                        final text = controller.text;
                        final sel = controller.selection;
                        final start = sel.start >= 0 ? sel.start : text.length;
                        final end = sel.end >= 0 ? sel.end : text.length;
                        final newText = text.replaceRange(start, end, '\n');
                        controller.value = TextEditingValue(
                          text: newText,
                          selection: TextSelection.collapsed(offset: start + 1),
                        );
                        return null;
                      }),
                    },
                    child: TextField(
                      controller: _sendController,
                      minLines: 1,
                      maxLines: 4,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        labelText: localizations.requestBody,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Telegram-style circular send button
              Tooltip(
                message: localizations.send,
                child: Opacity(
                  opacity: _connected ? 1.0 : 0.5,
                  child: InkWell(
                    onTap: _connected ? _sendText : null,
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 3))
                        ],
                      ),
                      child: const Icon(Icons.send, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
            ]),
          )
        ]),
        // positioned jump-to-latest button (custom style). It is placed above the input area and above
        // the keyboard by using MediaQuery.viewInsets.bottom as extra offset.
        if (!_isNearBottom)
          // pill-shaped jump button placed just above the input bar, aligned to the right
          Positioned(
            right: 16,
            bottom: () {
              final inputContext = _inputBarKey.currentContext;
              final viewInsets = MediaQuery.of(context).viewInsets.bottom;
              if (inputContext != null) {
                final renderBox = inputContext.findRenderObject() as RenderBox?;
                if (renderBox != null) {
                  final h = renderBox.size.height;
                  return (h + 12.0 + viewInsets);
                }
              }
              return 80.0 + viewInsets;
            }(),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: !_isNearBottom ? 1.0 : 0.0,
              child: Semantics(
                label: 'Jump to latest messages',
                button: true,
                child: Material(
                  elevation: 10,
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      await _animateToBottom();
                      if (!_isNearBottom) {
                        setState(() {
                          _isNearBottom = true;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(20.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(20.0),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.24), blurRadius: 8, offset: const Offset(0, 4))
                        ],
                      ),
                      child: const Icon(Icons.arrow_downward, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _messageList(ThemeData theme) {
    // Add extra bottom padding when the jump button is visible to avoid covering content
    double baseBottom = 10;
    double extraBottom = 0;
    if (!_isNearBottom) {
      final inputContext = _inputBarKey.currentContext;
      if (inputContext != null) {
        final renderBox = inputContext.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          // button height ~ 32 (pill) + margin 16; ensure some extra spacing for safe area
          extraBottom = 48; // conservative spacing
        }
      } else {
        extraBottom = 48;
      }
    }
    return ListView.separated(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(10, 10, 10, baseBottom + extraBottom),
      itemBuilder: (context, index) {
        final m = _messages[index];
        if (m.isSystem) {
          return Center(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectionContainer.disabled(
                  child: Text(_formatTime(m.time), style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey))),
              const SizedBox(height: 4),
              Text(m.textPreview(), style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
            ],
          ));
        }
        final displayOnLeft = !m.isClient;
        final avatar = CircleAvatar(
          backgroundColor: m.isClient ? Colors.green : Colors.blue,
          child: Text(m.isClient ? 'C' : 'S', style: const TextStyle(color: Colors.white)),
        );
        final bubbleText = m.isBinary ? '[binary ${_formatSize(m.bytes.length)}]' : m.textPreview();
        final bubble = Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: displayOnLeft ? Colors.green.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(bubbleText),
        );
        final previewButton = IconButton(
          onPressed: () {
            showDialog(context: context, builder: (context) => _PreviewDialog(bytes: m.bytes));
          },
          icon: Icon(Icons.expand_more, color: ColorScheme.of(context).primary),
        );
        // attach key to the last message so we can ensureVisible it
        final widgetKey = index == _messages.length - 1 ? _lastMessageKey : null;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          key: widgetKey,
          child: Row(
            mainAxisAlignment: displayOnLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
            children: [
              if (displayOnLeft) avatar,
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: displayOnLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                  children: [
                    SelectionContainer.disabled(
                        child:
                            Text(_formatTime(m.time), style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey))),
                    const SizedBox(height: 4),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!displayOnLeft) previewButton,
                      Flexible(child: bubble),
                      if (displayOnLeft) previewButton,
                    ]),
                  ],
                ),
              ),
              if (!displayOnLeft) const SizedBox(width: 8),
              if (!displayOnLeft) avatar,
            ],
          ),
        );
      },
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemCount: _messages.length,
    );
  }
}

class _WsMessage {
  final bool isClient;
  final List<int> bytes;
  final bool isBinary;
  final DateTime time;

  _WsMessage(this.isClient, this.bytes, this.isBinary, {DateTime? time}) : time = time ?? DateTime.now();

  bool get isSystem => bytes.isEmpty;

  String textPreview() {
    if (isSystem) return utf8.decode(bytes);
    return utf8.decode(bytes);
  }

  @override
  String toString() {
    return 'Message(isClient: $isClient, bytes: $bytes, isBinary: $isBinary, time: $time)';
  }

  factory _WsMessage.system(String text) {
    return _WsMessage(false, utf8.encode(text), false);
  }
}

class _PreviewDialog extends StatefulWidget {
  final List<int> bytes;

  const _PreviewDialog({required this.bytes});

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  int tabIndex = 0; // 0: HEX, 1: TEXT

  @override
  Widget build(BuildContext context) {
    var tabs = [
      if (isJsonText(widget.bytes)) const Tab(text: "JSON Text"),
      if (isJsonText(widget.bytes)) const Tab(text: "JSON"),
      const Tab(text: "TEXT"),
      const Tab(text: "HEX"),
    ];

    return AlertDialog(
      content: SizedBox(
        width: 700,
        height: 650,
        child: DefaultTabController(
          length: tabs.length,
          initialIndex: tabIndex,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TabBar(
              tabs: tabs,
              onTap: (index) {
                setState(() {
                  tabIndex = index;
                });
              },
            ),
            Expanded(
              child: TabBarView(children: [
                if (isJsonText(widget.bytes))
                  SingleChildScrollView(padding: const EdgeInsets.all(8.0), child: jsonText()),
                if (isJsonText(widget.bytes))
                  SingleChildScrollView(padding: const EdgeInsets.all(8.0), child: jsonView()),
                // TEXT
                SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(safeTextPreview(widget.bytes)),
                ),

                // HEX
                SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(widget.bytes.map(intToHex).join(" ")),
                ),
              ]),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel))
      ],
    );
  }

  Widget jsonText() {
    String body = utf8.decode(widget.bytes, allowMalformed: true);
    dynamic jsonData;
    try {
      jsonData = json.decode(body);
    } catch (e) {
      jsonData = null;
    }

    if (jsonData == null) {
      return SelectableText(safeTextPreview(widget.bytes));
    }

    return JsonText(json: jsonData, indent: '    ', colorTheme: ColorTheme.of(context));
  }

  Widget jsonView() {
    String body = utf8.decode(widget.bytes, allowMalformed: true);
    dynamic jsonData;
    try {
      jsonData = json.decode(body);
    } catch (e) {
      jsonData = null;
    }

    if (jsonData == null) {
      return SelectableText(safeTextPreview(widget.bytes));
    }

    return JsonViewer(json.decode(body), colorTheme: ColorTheme.of(context));
  }

  //判断是否是json格式
  bool isJsonText(List<int> bytes) {
    return bytes.isNotEmpty && (bytes[0] == 0x7B || bytes[0] == 0x5B);
  }

  String intToHex(int b) => b.toRadixString(16).padLeft(2, '0');

  /// Decode bytes to string, non-printable as '.'
  String safeTextPreview(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return bytes.map((b) => b >= 32 && b <= 126 ? String.fromCharCode(b) : '.').join();
    }
  }
}

class _SendIntent extends Intent {
  const _SendIntent();
}

class _InsertNewlineIntent extends Intent {
  const _InsertNewlineIntent();
}
