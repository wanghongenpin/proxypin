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
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:highlight/languages/http.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/utils/platform.dart';

/// A reusable panel to display request/response headers.
///
/// Supports two modes:
/// - table mode: each header shown as name/value rows
/// - text mode: raw header lines in a read-only code field
class HeadersWidget extends StatefulWidget {
  final String title;
  final HttpMessage? message;
  final TextStyle valueTextStyle;
  final bool initiallyExpanded;

  /// Optional shared controller for raw-text mode, so caller can reuse
  /// controllers between rebuilds (e.g. separate for Request/Response).
  final CodeController? controller;

  const HeadersWidget({
    super.key,
    required this.title,
    required this.message,
    this.valueTextStyle = const TextStyle(fontSize: 14),
    this.initiallyExpanded = true,
    this.controller,
  });

  @override
  State<HeadersWidget> createState() => _HeadersWidgetState();
}

class _HeadersWidgetState extends State<HeadersWidget> {
  // 静态缓存：按 title 区分的展开状态（保持同一进程内跨页面实例）
  static final Map<String, bool> _lastExpanded = {};
  late CodeController _controller;

  // 当前实例展开状态
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? CodeController(readOnly: true, language: http, text: _buildRawHeaders(widget.message));
    // 优先使用按 type 缓存，其次使用全局配置，最后使用 widget 默认
    final key = widget.title;
    _expanded = _lastExpanded[key] ?? AppConfiguration.current?.headerExpanded ?? widget.initiallyExpanded;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
      iconSize: 18,
      tooltip: isText ? 'Headers: Text' : 'Headers: Table',
      onPressed: () => setMode(!isText),
      icon: Icon(isText ? Icons.text_snippet : Icons.table_rows),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTextMode = (AppConfiguration.current?.headerViewMode ?? 'table') == 'text';
    return ExpansionTile(
      tilePadding: const EdgeInsets.only(left: 0),
      dense: true,
      title: Row(
        children: [
          Expanded(
              child:
                  Text('${widget.title} Headers', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14))),
          _buildHeaderModeToggle(context),
        ],
      ),
      // 使用实例状态作为当前的展开状态
      initiallyExpanded: _expanded,
      onExpansionChanged: (expanded) {
        if (_expanded == expanded) return;
        _expanded = expanded;
        _lastExpanded[widget.title] = expanded;
        if (mounted) setState(() {});
      },
      shape: const Border(),
      children: !isTextMode ? _buildHeaderRows(widget.message) : buildTextMode(widget.message),
    );
  }

  List<Widget> buildTextMode(HttpMessage? message) {
    final text = _buildRawHeaders(message);
    if (_controller.text != text) {
      _controller = CodeController(readOnly: true, language: http, text: text);
    }

    return [
      CodeTheme(
        data: CodeThemeData(
            styles: Theme.brightnessOf(context) == Brightness.light ? atomOneLightTheme : atomOneDarkTheme),
        child: CodeField(
          background: Colors.transparent,
          readOnly: Platforms.isMobile(),
          wrap: true,
          gutterStyle: const GutterStyle(margin: 0, width: 52, showErrors: false),
          textStyle: const TextStyle(fontSize: 15.3),
          controller: _controller,
        ),
      ),
    ];
  }

  List<Widget> _buildHeaderRows(HttpMessage? message) {
    final rows = <Widget>[];
    message?.headers.forEach((name, values) {
      for (final v in values) {
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(name,
                contextMenuBuilder: contextMenu,
                style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.deepOrangeAccent, fontSize: 15)),
            const Text(': ',
                style: TextStyle(fontWeight: FontWeight.w500, color: Colors.deepOrangeAccent, fontSize: 15)),
            Expanded(
              child: SelectableText(
                v,
                style: widget.valueTextStyle,
                contextMenuBuilder: contextMenu,
                maxLines: 8,
                minLines: 1,
              ),
            ),
          ],
        ));
        rows.add(const Divider(thickness: 0.1, height: 10));
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
