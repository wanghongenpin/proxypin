/*
 * Copyright 2024 Hongen Wang All rights reserved.
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

/// 匹配文本高亮
/// @author: Hongen Wang
class HighlightTextEditingController extends TextEditingController {
  RegExp? highlightPattern;
  String? splitPattern;

  //
  bool highlightEnabled = true;

  HighlightTextEditingController({super.text});

  bool highlight(String? value, {bool caseSensitive = true}) {
    highlightPattern = value == null ? null : RegExp(value, caseSensitive: caseSensitive);
    return highlightPattern?.hasMatch(text) ?? false;
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final text = this.text;

    if (!highlightEnabled || highlightPattern == null || !highlightPattern!.hasMatch(text)) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }

    Color color = Theme.of(context).colorScheme.primary;
    final highlightStyle = style?.copyWith(color: color);
    final normalStyle = style;
    List<TextSpan> spans = [];
    if (splitPattern != null) {
      var texts = text.split(splitPattern!);
      for (var i = 0; i < texts.length; i++) {
        matchHighlight(texts[i], spans, normalStyle: normalStyle, highlightStyle: highlightStyle);
        spans.add(TextSpan(text: splitPattern, style: normalStyle));
      }
    } else {
      matchHighlight(text, spans, normalStyle: normalStyle, highlightStyle: highlightStyle);
    }
    return TextSpan(children: spans, style: style);
  }

  matchHighlight(String text, List<TextSpan> spans, {TextStyle? normalStyle, TextStyle? highlightStyle}) {
    int start = 0;
    for (final match in highlightPattern!.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start), style: normalStyle));
      }
      spans.add(TextSpan(text: match.group(0), style: highlightStyle));
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: normalStyle));
    }
  }
}

InputDecoration decoration(BuildContext context, {String? label, String? hintText, Widget? suffixIcon}) {
  Color color = Theme.of(context).colorScheme.primary;
  return InputDecoration(
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelText: label,
      hintText: hintText,
      suffixIcon: suffixIcon,
      hintStyle: TextStyle(color: Colors.grey.shade500),
      border: OutlineInputBorder(borderSide: BorderSide(width: 0.8, color: color)),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(width: 1.3, color: color)),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(width: 2, color: color)));
}
