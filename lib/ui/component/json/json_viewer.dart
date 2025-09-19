/*
 * Copyright 2023 Hongen Wang All rights reserved.
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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/component/json/theme.dart';
import 'package:proxypin/ui/component/json/toast.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/platform.dart';

import '../search/search_controller.dart';

class JsonViewer extends StatelessWidget {
  final dynamic jsonObj;
  final ColorTheme colorTheme;
  final SearchTextController? searchController;

  const JsonViewer(this.jsonObj, {super.key, required this.colorTheme, this.searchController});

  @override
  Widget build(BuildContext context) {
    final matchKeys = <GlobalKey>[];
    if (searchController == null) {
      return DefaultTextStyle.merge(
          style: const TextStyle(fontWeight: FontWeight.w600),
          child: getContentWidget(jsonObj, matchTotalCount: ValueWrap.of(0), matchKeys: matchKeys));
    }
    return AnimatedBuilder(
        animation: searchController ?? ValueNotifier(0),
        builder: (context, child) {
          final matchTotalCount = ValueWrap.of(0);
          matchKeys.clear();
          final contentWidget = DefaultTextStyle.merge(
              style: const TextStyle(fontWeight: FontWeight.w600),
              child: getContentWidget(jsonObj, matchTotalCount: matchTotalCount, matchKeys: matchKeys));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            searchController?.updateMatchCount(matchTotalCount.get()!);
            scrollToMatch(matchKeys);
          });
          return contentWidget;
        });
  }

  Widget getContentWidget(dynamic content,
      {required ValueWrap<int> matchTotalCount, required List<GlobalKey> matchKeys}) {
    if (content is List) {
      return JsonArrayViewer(content,
          colorTheme: colorTheme,
          searchController: searchController,
          matchTotalCount: matchTotalCount,
          matchKeys: matchKeys);
    } else if (content is Map<String, dynamic>) {
      return JsonObjectViewer(content,
          colorTheme: colorTheme,
          searchController: searchController,
          matchTotalCount: matchTotalCount,
          matchKeys: matchKeys);
    } else {
      return SelectableText(showCursor: true, content?.toString() ?? '');
    }
  }

  void scrollToMatch(List<GlobalKey> matchKeys) {
    if (searchController != null && matchKeys.isNotEmpty) {
      final currentIndex = searchController!.currentMatchIndex.value;
      if (currentIndex >= 0 && currentIndex < matchKeys.length) {
        final key = matchKeys[currentIndex];
        final context = key.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 300),
            alignment: 0.5, // 高亮项在视图中的位置
          );
        }
      }
    }
  }
}

class JsonObjectViewer extends StatefulWidget {
  final ColorTheme colorTheme;
  final Map<String, dynamic> jsonObj;
  final bool notRoot;
  final SearchTextController? searchController;
  final ValueWrap<int> matchTotalCount;
  final List<GlobalKey> matchKeys;

  const JsonObjectViewer(this.jsonObj,
      {super.key,
      this.notRoot = false,
      required this.colorTheme,
      this.searchController,
      required this.matchTotalCount,
      required this.matchKeys});

  @override
  JsonObjectViewerState createState() => JsonObjectViewerState();
}

class JsonObjectViewerState extends State<JsonObjectViewer> {
  Map<String, bool> openFlag = {};

  @override
  void didUpdateWidget(covariant JsonObjectViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    openFlag = {};
  }

  @override
  Widget build(BuildContext context) {
    if (widget.notRoot) {
      return Container(
        padding: const EdgeInsets.only(left: 14.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _getList()),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: _getList());
  }

  List<Widget> _getList() {
    List<Widget> list = [];
    for (MapEntry entry in widget.jsonObj.entries) {
      if (openFlag[entry.key] == null) {
        openFlag[entry.key] = widget.notRoot == false && _isExtensible(entry.value);
      }

      list.add(Row(
        children: <Widget>[
          getKeyWidget(entry),
          Text(':', style: TextStyle(color: widget.colorTheme.colon)),
          const SizedBox(width: 3),
          _copyValue(
              context,
              _getValueWidget(entry.value, widget.colorTheme,
                  searchController: widget.searchController,
                  matchTotalCount: widget.matchTotalCount,
                  matchKeys: widget.matchKeys),
              entry.value),
        ],
      ));
      list.add(const SizedBox(height: 4));

      if ((openFlag[entry.key] ?? false) && entry.value != null) {
        list.add(getContentWidget(entry.value, widget.colorTheme,
            searchController: widget.searchController,
            matchTotalCount: widget.matchTotalCount,
            matchKeys: widget.matchKeys));
      }
    }
    return list;
  }

  // key
  Widget getKeyWidget(MapEntry entry) {
    final keyText = entry.key;

    final keyWidget = Container(
        constraints: BoxConstraints(maxWidth: 350),
        child: SelectableText.rich(
            showCursor: true,
            TextSpan(
                children: _highlightText(keyText, TextStyle(color: widget.colorTheme.propertyKey),
                    searchController: widget.searchController,
                    colorTheme: widget.colorTheme,
                    matchTotalCount: widget.matchTotalCount,
                    matchKeys: widget.matchKeys))));

    //是否有子层级
    if (_isExtensible(entry.value)) {
      return InkWell(
          onTap: () {
            setState(() {
              openFlag[entry.key] = !(openFlag[entry.key] ?? false);
            });
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              (openFlag[entry.key] ?? false)
                  ? const Icon(Icons.keyboard_arrow_down, size: 18)
                  : const Icon(Icons.keyboard_arrow_right, size: 18),
              keyWidget,
            ],
          ));
    }

    return Row(children: [
      const Icon(Icons.keyboard_arrow_right, color: Color.fromARGB(0, 0, 0, 0), size: 18),
      keyWidget,
    ]);
  }

  static Widget getContentWidget(dynamic content, ColorTheme colorTheme,
      {SearchTextController? searchController,
      required ValueWrap<int> matchTotalCount,
      required List<GlobalKey> matchKeys}) {
    if (content is List) {
      return JsonArrayViewer(content,
          notRoot: true,
          colorTheme: colorTheme,
          searchController: searchController,
          matchTotalCount: matchTotalCount,
          matchKeys: matchKeys);
    } else {
      return JsonObjectViewer(content,
          notRoot: true,
          colorTheme: colorTheme,
          searchController: searchController,
          matchTotalCount: matchTotalCount,
          matchKeys: matchKeys);
    }
  }
}

class JsonArrayViewer extends StatefulWidget {
  final ColorTheme colorTheme;
  final List<dynamic> jsonArray;
  final bool notRoot;
  final SearchTextController? searchController;
  final ValueWrap<int> matchTotalCount;
  final List<GlobalKey> matchKeys;

  const JsonArrayViewer(this.jsonArray,
      {super.key,
      this.notRoot = false,
      required this.colorTheme,
      this.searchController,
      required this.matchTotalCount,
      required this.matchKeys});

  @override
  State<JsonArrayViewer> createState() => _JsonArrayViewerState();
}

class _JsonArrayViewerState extends State<JsonArrayViewer> {
  late List<bool> openFlag;

  @override
  Widget build(BuildContext context) {
    if (widget.notRoot) {
      return Container(
          padding: const EdgeInsets.only(left: 14.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _getList()));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: _getList());
  }

  @override
  void initState() {
    super.initState();
    openFlag = List.filled(widget.jsonArray.length, false);
  }

  List<Widget> _getList() {
    List<Widget> list = [];
    int i = 0;
    for (dynamic content in widget.jsonArray) {
      list.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          getKeyWidget(content, i),
          Text(':', style: TextStyle(color: widget.colorTheme.colon)),
          const SizedBox(width: 3),
          _copyValue(
              context,
              _getValueWidget(content, widget.colorTheme,
                  searchController: widget.searchController,
                  matchTotalCount: widget.matchTotalCount,
                  matchKeys: widget.matchKeys),
              content)
        ],
      ));
      list.add(const SizedBox(height: 4));
      if (openFlag[i]) {
        list.add(JsonObjectViewerState.getContentWidget(content, widget.colorTheme,
            searchController: widget.searchController,
            matchTotalCount: widget.matchTotalCount,
            matchKeys: widget.matchKeys));
      }
      i++;
    }
    return list;
  }

  // key
  Widget getKeyWidget(dynamic content, int index) {
    //是否有子层级
    if (_isExtensible(content)) {
      return InkWell(
          onTap: () {
            setState(() {
              openFlag[index] = !(openFlag[index]);
            });
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              openFlag[index]
                  ? const Icon(Icons.keyboard_arrow_down, size: 18)
                  : const Icon(Icons.keyboard_arrow_right, size: 18),
              Text('[$index]', style: TextStyle(color: widget.colorTheme.propertyKey)),
            ],
          ));
    }

    return Row(children: [
      const Icon(Icons.arrow_right, color: Color.fromARGB(0, 0, 0, 0), size: 18),
      Text('[$index]', style: TextStyle(color: widget.colorTheme.propertyKey)),
    ]);
  }
}

Widget _getValueWidget(dynamic value, ColorTheme colorTheme,
    {SearchTextController? searchController,
    required ValueWrap<int> matchTotalCount,
    required List<GlobalKey> matchKeys}) {
  String valueStr;
  TextStyle style;
  if (value == null) {
    valueStr = 'null';
    style = TextStyle(color: colorTheme.keyword);
  } else if (value is num) {
    valueStr = value.toString();
    style = TextStyle(color: colorTheme.keyword);
  } else if (value is String) {
    valueStr = '"$value"';
    style = TextStyle(color: colorTheme.string);
  } else if (value is bool) {
    valueStr = value.toString();
    style = TextStyle(color: colorTheme.keyword);
  } else if (value is List) {
    if (value.isEmpty) {
      valueStr = 'Array[0]';
      style = const TextStyle();
    } else {
      valueStr = 'Array<${_getTypeName(value[0])}>[${value.length}]';
      style = const TextStyle();
    }
  } else {
    valueStr = 'Object';
    style = const TextStyle(fontSize: 13);
  }

  if (searchController?.shouldSearch() == true) {
    return SelectableText.rich(
      showCursor: true,
      TextSpan(
          children: _highlightText(valueStr, style,
              searchController: searchController,
              colorTheme: colorTheme,
              matchTotalCount: matchTotalCount,
              matchKeys: matchKeys)),
    );
  }

  return SelectableText(showCursor: true, valueStr, style: style);
}

List<InlineSpan> _highlightText(String text, TextStyle textStyle,
    {SearchTextController? searchController,
    required ColorTheme colorTheme,
    required ValueWrap<int> matchTotalCount,
    required List<GlobalKey> matchKeys}) {
  if (searchController == null || searchController.shouldSearch() == false) {
    return [TextSpan(text: text, style: textStyle)];
  }

  final pattern = searchController.value.pattern;
  final regex = searchController.value.isRegExp
      ? RegExp(pattern, caseSensitive: searchController.value.isCaseSensitive)
      : RegExp(RegExp.escape(pattern), caseSensitive: searchController.value.isCaseSensitive);

  final spans = <InlineSpan>[];
  int start = 0;
  var allMatches = regex.allMatches(text).toList();
  final currentIndex = searchController.currentMatchIndex.value;
  for (int i = 0; i < allMatches.length; i++) {
    final match = allMatches[i];
    if (match.start > start) {
      spans.add(TextSpan(text: text.substring(start, match.start), style: textStyle));
    }
    // 为每个高亮项分配一个 GlobalKey
    final key = GlobalKey();
    matchKeys.add(key);
    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      baseline: TextBaseline.ideographic,
      child: Text(
          key: key,
          text.substring(match.start, match.end),
          style: textStyle.copyWith(
            backgroundColor: matchTotalCount.get() == currentIndex
                ? colorTheme.searchMatchCurrentColor
                : colorTheme.searchMatchColor,
          )),
    ));
    start = match.end;

    matchTotalCount.set(matchTotalCount.get()! + 1);
  }

  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start), style: textStyle));
  }
  return spans;
}

///获取值的类型
String _getTypeName(dynamic content) {
  if (content is int) {
    return 'int';
  } else if (content is String) {
    return 'String';
  } else if (content is bool) {
    return 'bool';
  } else if (content is double) {
    return 'double';
  } else if (content is List) {
    return 'List';
  }
  return 'Object';
}

/// 复制值
Widget _copyValue(BuildContext context, Widget child, Object? value) {
  return Flexible(
      child: GestureDetector(
          onSecondaryTapDown: (details) => showJsonCopyMenu(context, details.globalPosition, value),
          onTapDown:
              Platforms.isDesktop() ? null : (details) => showJsonCopyMenu(context, details.globalPosition, value),
          child: child));
}

void showJsonCopyMenu(BuildContext context, Offset position, Object? value) {
  AppLocalizations localizations = AppLocalizations.of(context)!;

  //显示复制菜单
  showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
            height: 30,
            child: Text(localizations.copy),
            onTap: () {
              if (value == null) {
                return;
              }
              Clipboard.setData(ClipboardData(text: value is String ? value : jsonEncode(value)))
                  .then((value) => Toast.show(localizations.copied, context));
            })
      ]);
}

/// 是否可展开
bool _isExtensible(dynamic content) {
  if (content == null) {
    return false;
  } else if (content is int) {
    return false;
  } else if (content is String) {
    return false;
  } else if (content is bool) {
    return false;
  } else if (content is double) {
    return false;
  }
  return true;
}
