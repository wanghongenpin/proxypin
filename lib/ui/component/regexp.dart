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
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/ui/component/text_field.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

///正则表达式工具
///@author Hongen Wang
class RegExpPage extends StatefulWidget {
  const RegExpPage({super.key});

  @override
  State<StatefulWidget> createState() {
    return _RegExpPageState();
  }
}

class _RegExpPageState extends State<RegExpPage> {
  var pattern = TextEditingController();
  var input = HighlightTextEditingController();
  var replaceText = TextEditingController();
  String? resultInput;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    pattern.addListener(onInputChangeMatch);
    input.addListener(onInputChangeMatch);
  }

  @override
  void dispose() {
    pattern.dispose();
    input.dispose();
    replaceText.dispose();
    super.dispose();
  }

  ButtonStyle get buttonStyle => ButtonStyle(
      padding: WidgetStateProperty.all<EdgeInsets>(EdgeInsets.symmetric(horizontal: 15, vertical: 8)),
      textStyle: WidgetStateProperty.all<TextStyle>(TextStyle(fontSize: 14)),
      shape: WidgetStateProperty.all<RoundedRectangleBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));

  @override
  Widget build(BuildContext context) {
    Color primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
        appBar: PreferredSize(
            preferredSize: Size.fromHeight(50),
            child: AppBar(
                title: Text(localizations.regExp, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                centerTitle: true)),
        resizeToAvoidBottomInset: false,
        body: ListView(padding: const EdgeInsets.all(10), children: [
          TextField(
            controller: pattern,
            minLines: 1,
            maxLines: 3,
            onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: decoration(context,
                label: 'Pattern',
                hintText: 'Enter a regular expression',
                suffixIcon: IconButton(icon: Icon(Icons.clear), onPressed: () => pattern.clear())),
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => pattern.text += r'\d+', // Only digits
                child: const Text('Digits'),
              ),
              TextButton(
                onPressed: () => pattern.text += r'[a-zA-Z]+', // Only letters
                child: const Text('Letters'),
              ),
              TextButton(
                onPressed: () => pattern.text += r'[a-zA-Z0-9]+', // Alphanumeric
                child: const Text('Alphanumeric'),
              ),
              TextButton(
                onPressed: () => pattern.text += r'\w+@\w+\.\w+', // Email
                child: const Text('Email'),
              ),
              TextButton(
                onPressed: () => pattern.text += r'(https?|ftp)://[^\s/$.?#].[^\s]*', // URL
                child: const Text('URL'),
              ),
              TextButton(
                onPressed: () => pattern.text += r'\d{4}-\d{2}-\d{2}', // Date (YYYY-MM-DD)
                child: const Text('Date (YYYY-MM-DD)'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            Align(alignment: Alignment.centerLeft, child: Text(localizations.testData)),
            const SizedBox(width: 10),
            if (!isMatch) Text(localizations.noChangesDetected, style: TextStyle(color: Colors.red))
          ]),
          const SizedBox(height: 5),
          TextField(
            controller: input,
            minLines: 5,
            maxLines: 8,
            onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: decoration(context, hintText: localizations.enterMatchData),
          ),
          const SizedBox(height: 25),
          //输入替换文本
          Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
                width: 355,
                child: TextField(
                  controller: replaceText,
                  onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: decoration(context, label: 'Replace Text', hintText: 'Enter replacement text'),
                )),
            FilledButton.icon(
                onPressed: () {
                  if (pattern.text.isEmpty) return;
                  setState(() {
                    resultInput = input.text;
                  });
                },
                style: buttonStyle,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Run')),
            const SizedBox(width: 20),
          ]),
          SizedBox(height: 10),

          if (resultInput != null)
            Row(children: [
              Text("Result", style: TextStyle(fontSize: 16, color: primaryColor, fontWeight: FontWeight.w500)),
              const SizedBox(width: 15),
              //copy
              IconButton(
                  icon: Icon(Icons.copy, color: primaryColor, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: resultInput!));
                    FlutterToastr.show(localizations.copied, context, duration: 3);
                  }),
            ]),
          if (resultInput != null) SizedBox(height: 5),
          if (resultInput != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.2)),
              child: SelectableText.rich(
                showCursor: true,
                TextSpan(
                  children: _buildHighlightedText(),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
        ]));
  }

  List<InlineSpan> _buildHighlightedText() {
    if (resultInput == null) return [];

    final spans = <InlineSpan>[];
    int start = 0;

    var text = resultInput!;
    var regex = RegExp(pattern.text);
    var replaceText = this.replaceText.text;
    var matches = regex.allMatches(text);

    for (var match in matches) {
      if (start < match.start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      spans.add(TextSpan(text: replaceText, style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)));
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return spans;
  }

  bool onMatch = false; //是否正在匹配
  bool isMatch = true; //是否匹配成功

  onInputChangeMatch() {
    if (onMatch || input.highlightEnabled == false) {
      return;
    }
    onMatch = true;

    //高亮显示
    Future.delayed(const Duration(milliseconds: 500), () {
      onMatch = false;
      if (pattern.text.isEmpty) {
        if (isMatch) return;
        setState(() {
          isMatch = true;
        });
        return;
      }

      setState(() {
        var match = input.highlight(pattern.text);
        isMatch = match;
      });
    });
  }
}
