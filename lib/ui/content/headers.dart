/*
 * Copyright 2025 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/search/highlight_text.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/configuration.dart';

import '../component/search/search_controller.dart';

/// A reusable panel to display request/response headers.
///
/// Supports two modes:
/// - table mode: each header shown as name/value rows
/// - text mode: raw header lines in a read-only code field
class HeadersWidget extends StatefulWidget {
  final String title;
  final HttpMessage? message;
  final TextStyle valueTextStyle;

  /// Optional shared controller for raw-text mode, so caller can reuse
  /// controllers between rebuilds (e.g. separate for Request/Response).
  final CodeForgeController? controller;

  const HeadersWidget({
    super.key,
    required this.title,
    required this.message,
    this.valueTextStyle = const TextStyle(fontSize: 14),
    this.controller,
  });

  @override
  State<HeadersWidget> createState() => _HeadersWidgetState();
}

class _HeadersWidgetState extends State<HeadersWidget> {
  Widget _buildCopyButton(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final text = _buildRawHeaders(widget.message);
    return IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 15,
      tooltip: localizations.copy,
      onPressed: text.isEmpty
          ? null
          : () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              FlutterToastr.show(localizations.copied, context);
            },
      icon: Icon(Icons.copy, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }

  Widget _buildHeaderModeToggle(BuildContext context) {
    final config = AppConfiguration.current;
    if (config == null) return const SizedBox();
    final isText = config.headerViewMode == 'text';
    void setMode(bool text) {
      config.headerViewMode = text ? 'text' : 'table';
      config.flushConfig();
      setState(() {});
    }

    return IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 15,
      tooltip: isText ? 'Headers: Text' : 'Headers: Table',
      onPressed: () => setMode(!isText),
      icon: Icon(isText ? Icons.text_snippet : Icons.table_rows, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTextMode = (AppConfiguration.current?.headerViewMode ?? 'table') == 'text';
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context)!;
    // 设计稿 .d-sec：11px 灰色扁平分区标签（请求头/响应头，不再折叠）
    final label = widget.title == 'Request' ? localizations.requestHeader : localizations.responseHeader;
    final text3 = theme.brightness == Brightness.light ? const Color(0xFF8F959E) : theme.colorScheme.onSurfaceVariant;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.only(left: 14, right: 6, top: 10, bottom: 2),
          child: Row(children: [
            Text(label, style: TextStyle(fontSize: 11, height: 1.5, letterSpacing: 0.3, color: text3)),
            const Spacer(),
            _buildCopyButton(context),
            _buildHeaderModeToggle(context),
          ])),
      if (!isTextMode) ..._buildHeaderRows(context, widget.message) else ...buildTextMode(widget.message),
    ]);
  }

  List<Widget> buildTextMode(HttpMessage? message) {
    final text = _buildRawHeaders(message);

    return [
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: HighlightTextWidget(
            text: text,
            language: 'http',
            searchController: SearchTextController(),
            contextMenuBuilder: contextMenu,
          )),
    ];
  }

  /// 设计稿 .kv：130px 灰色头名（12.5px）+ 等宽值（12px），行间 #F2F3F5 细线
  List<Widget> _buildHeaderRows(BuildContext context, HttpMessage? message) {
    final theme = Theme.of(context);
    final text3 = theme.brightness == Brightness.light ? const Color(0xFF8F959E) : theme.colorScheme.onSurfaceVariant;
    final divider = Divider(height: 1, thickness: 1, color: theme.dividerColor.withValues(alpha: 0.35));

    final rows = <Widget>[];
    message?.headers.forEach((name, values) {
      for (final v in values) {
        if (rows.isNotEmpty) {
          rows.add(divider);
        }
        rows.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: 130,
                  // 长头名（如 Access-Control-Allow-Origin）允许换行，避免溢出遮挡值
                  child: Text(name, style: TextStyle(fontSize: 12.5, height: 1.5, color: text3))),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  v,
                  style: TextStyle(
                      fontFamily: 'monospace', fontSize: 12, height: 1.5, color: theme.colorScheme.onSurface),
                  contextMenuBuilder: contextMenu,
                  maxLines: 8,
                  minLines: 1,
                ),
              ),
            ])));
      }
    });
    return rows;
  }

  String _buildRawHeaders(HttpMessage? message) {
    if (message == null) return '';
    final buffer = StringBuffer();
    message.headers.forEach((name, values) {
      for (final v in values) {
        buffer.writeln('$name: $v');
      }
    });
    return buffer.toString().trimRight();
  }
}
