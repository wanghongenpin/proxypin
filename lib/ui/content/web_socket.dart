import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/num.dart';

import '../../l10n/app_localizations.dart';
import '../../network/http/http.dart';
import '../../network/http/websocket.dart';
import '../../utils/platform.dart';
import '../component/app_dialog.dart';
import '../component/json/json_text.dart';
import '../component/json/json_viewer.dart';
import '../component/json/theme.dart';

///以聊天对话框样式展示websocket消息
class Websocket extends StatelessWidget {
  final ValueWrap<HttpRequest> request;
  final ValueWrap<HttpResponse> response;

  const Websocket(this.request, this.response, {super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    var request = this.request.get();
    if (request == null) {
      return const SizedBox();
    }
    List<WebSocketFrame> messages = List.from(request.messages);
    var response = this.response.get();
    if (response != null) {
      messages.addAll(response.messages);
    }
    messages.sort((a, b) => a.time.compareTo(b.time));

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 15),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        var message = messages[index];
        var avatar = SelectionContainer.disabled(
            child: CircleAvatar(
                backgroundColor: message.isFromClient ? Colors.green : Colors.blue,
                child:
                    Text(message.isFromClient ? 'C' : 'S', style: const TextStyle(fontSize: 18, color: Colors.white))));

        var previewButton = IconButton(
          tooltip: "Preview",
          onPressed: () {
            showDialog(context: context, builder: (context) => _PreviewDialog(bytes: message.payloadData));
          },
          icon: Icon(Icons.expand_more, color: ColorScheme.of(context).primary),
        );

        return Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              mainAxisAlignment: message.isFromClient ? MainAxisAlignment.start : MainAxisAlignment.end,
              children: [
                if (message.isFromClient) avatar,
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                      crossAxisAlignment: message.isFromClient ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                      children: [
                        SelectionContainer.disabled(
                            child:
                                Text(message.time.format(), style: const TextStyle(fontSize: 12, color: Colors.grey))),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          if (!message.isFromClient) previewButton,
                          Flexible(
                            child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: message.isFromClient
                                      ? Colors.green.withOpacity(0.26)
                                      : Colors.blue.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: SelectableText(
                                  "${message.payloadDataAsString}${message.isBinary ? ' ${getPackage(message.payloadLength)}' : ''}",
                                  maxLines: 1,
                                  contextMenuBuilder: (context, editableTextState) =>
                                      contextMenu(context, editableTextState,
                                          customItem: ContextMenuButtonItem(
                                            label: localizations.download,
                                            onPressed: () async {
                                              String? path = (await FilePicker.platform
                                                  .saveFile(fileName: "websocket.txt", bytes: message.payloadData));
                                              if (path != null && context.mounted) {
                                                CustomToast.success(localizations.saveSuccess).show(context);
                                              }
                                            },
                                            type: ContextMenuButtonType.custom,
                                          )),
                                )),
                          ),
                          if (message.isFromClient) previewButton,
                        ])
                      ]),
                ),
                const SizedBox(width: 8),
                if (!message.isFromClient) avatar,
              ],
            ));
      },
    );
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
        width: min(MediaQuery.of(context).size.width * 0.8, 700),
        height: min(MediaQuery.of(context).size.height * 0.6, 650),
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

    return JsonText(json: jsonData, indent: Platforms.isDesktop() ? '    ' : '  ', colorTheme: ColorTheme.of(context));
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

  /// Format bytes as hex-dump string: 4 bytes per group (8 hex digits), space between groups, line break every 16 bytes
  String formatHexDump(List<int> bytes) {
    final buffer = StringBuffer();

    // 每8个字节为一组，用空格分隔，组之间换行
    for (int i = 0; i < bytes.length; i++) {
      // 添加当前十六进制部分
      buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
      if ((i + 1) % 2 == 0 && i != bytes.length - 1) {
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  /// Decode bytes to string, non-printable as '.'
  String safeTextPreview(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return bytes.map((b) => b >= 32 && b <= 126 ? String.fromCharCode(b) : '.').join();
    }
  }
}
