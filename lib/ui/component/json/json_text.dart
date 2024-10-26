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
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:proxypin/ui/component/json/theme.dart';
import 'package:proxypin/ui/component/utils.dart';

class JsonText extends StatefulWidget {
  final ColorTheme colorTheme;
  final dynamic json;
  final String indent;
  final ScrollController? scrollController;

  const JsonText({super.key, required this.json, this.indent = '  ', required this.colorTheme, this.scrollController});

  @override
  State<StatefulWidget> createState() => _JsonTextSate();
}

class _JsonTextSate extends State<JsonText> {
  late ColorTheme colorTheme;
  late dynamic json;
  late String indent;
  late ScrollController? scrollController;

  @override
  void initState() {
    super.initState();
    colorTheme = widget.colorTheme;
    json = widget.json;
    indent = widget.indent;
    scrollController = trackingScroll(widget.scrollController);
  }

  @override
  void dispose() {
    scrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var jsnParser = JsnParser(json, colorTheme, indent);
    var future =
        compute((message) => message.getJsonTree(), jsnParser).catchError((error) => <Text>[Text(error.toString())]);

    return FutureBuilder(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
            var textList = snapshot.data as List<Text>;

            Widget widget;
            if (textList.length < 2000) {
              widget = Column(crossAxisAlignment: CrossAxisAlignment.start, children: textList);
            } else {
              widget = SizedBox(
                  width: double.infinity,
                  height: MediaQuery.of(context).size.height - 160,
                  child: ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      controller: scrollController,
                      cacheExtent: 1000,
                      itemBuilder: (context, index) => textList[index],
                      itemCount: textList.length));
            }
            return SelectionArea(child: widget);
          }

          return Container();
        });
  }
}

class JsnParser {
  final dynamic json;
  final ColorTheme colorTheme;
  final String indent;

  JsnParser(this.json, this.colorTheme, this.indent);

  List<Text> getJsonTree() {
    List<Text> textList = [];
    if (json is Map) {
      textList.add(const Text('{'));
      textList.addAll(getMapText(json, prefix: indent));
    } else if (json is List) {
      textList.add(const Text('['));
      textList.addAll(getArrayText(json));
    } else {
      textList.add(Text(json == null ? '' : json.toString()));
    }
    return textList;
  }

  /// 获取Map json
  List<Text> getMapText(Map<String, dynamic> map, {String openPrefix = '', String prefix = '', String suffix = ''}) {
    var result = <Text>[];
    // result.add(Text('$openPrefix{'));

    var entries = map.entries;
    for (int i = 0; i < entries.length; i++) {
      var entry = entries.elementAt(i);
      String postfix = '${i == entries.length - 1 ? '' : ','} ';

      var textSpan = TextSpan(text: prefix, children: [
        TextSpan(text: '"${entry.key}"', style: TextStyle(color: colorTheme.propertyKey)),
        const TextSpan(text: ': '),
        getBasicValue(entry.value, postfix),
      ]);
      result.add(Text.rich(textSpan));

      if (entry.value is Map<String, dynamic>) {
        result.addAll(getMapText(entry.value, openPrefix: prefix, prefix: '$prefix$indent', suffix: postfix));
      } else if (entry.value is List) {
        result.addAll(getArrayText(entry.value, openPrefix: prefix, prefix: '$prefix$indent', suffix: postfix));
      }
    }

    result.add(Text('$openPrefix}$suffix'));
    return result;
  }

  /// 获取数组json
  List<Text> getArrayText(List<dynamic> list, {String openPrefix = '', String prefix = '', String suffix = ''}) {
    var result = <Text>[];
    // result.add(Text('$openPrefix['));

    for (int i = 0; i < list.length; i++) {
      var value = list[i];
      String postfix = i == list.length - 1 ? '' : ',';

      result.add(Text.rich(getBasicValue(value, postfix, prefix: prefix)));

      if (value is Map<String, dynamic>) {
        result.addAll(getMapText(value, openPrefix: '$openPrefix ', prefix: '$prefix$indent', suffix: postfix));
      } else if (value is List) {
        result.addAll(getArrayText(value, openPrefix: '$openPrefix ', prefix: '$prefix$indent', suffix: postfix));
      }
    }

    result.add(Text('$openPrefix]$suffix'));
    return result;
  }

  /// 获取基本类型值 复杂类型会忽略
  InlineSpan getBasicValue(dynamic value, String suffix, {String? prefix}) {
    if (value == null) {
      return TextSpan(
          text: prefix,
          children: [TextSpan(text: 'null', style: TextStyle(color: colorTheme.keyword)), TextSpan(text: suffix)]);
    }

    if (value is String) {
      return TextSpan(
          text: prefix,
          children: [TextSpan(text: '"$value"', style: TextStyle(color: colorTheme.string)), TextSpan(text: suffix)]);
    }

    if (value is num) {
      return TextSpan(text: prefix, children: [
        TextSpan(text: value.toString(), style: TextStyle(color: colorTheme.number)),
        TextSpan(text: suffix)
      ]);
    }

    if (value is bool) {
      return TextSpan(text: prefix, children: [
        TextSpan(text: value.toString(), style: TextStyle(color: colorTheme.keyword)),
        TextSpan(text: suffix)
      ]);
    }

    if (value is List) {
      return TextSpan(text: "${prefix ?? ''}[");
    }

    return TextSpan(text: "${prefix ?? ''}{");
  }
}
