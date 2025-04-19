import 'package:flutter/material.dart';
import 'package:proxypin/ui/component/state_component.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:proxypin/utils/keyword_highlight.dart';

///配置关键词高亮
///@Author: WangHongEn
class DesktopKeywordHighlight extends StatefulWidget {
  const DesktopKeywordHighlight({super.key});

  @override
  State<DesktopKeywordHighlight> createState() => _KeywordHighlightState();
}

class _KeywordHighlightState extends State<DesktopKeywordHighlight> {
  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    var colors = {
      Colors.red: localizations.red,
      Colors.yellow.shade600: localizations.yellow,
      Colors.blue: localizations.blue,
      Colors.green: localizations.green,
      Colors.grey: localizations.gray,
    };

    Map<Color, String> map = Map.of(KeywordHighlights.keywords);

    return AlertDialog(
      title: ListTile(
          title: Text(localizations.keyword + localizations.highlight,
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500))),
      titlePadding: const EdgeInsets.all(0),
      actionsPadding: const EdgeInsets.only(right: 10, bottom: 10),
      contentPadding: const EdgeInsets.only(left: 10, right: 10, top: 0, bottom: 5),
      actions: [
        TextButton(
          child: Text(localizations.cancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
          child: Text(localizations.done),
          onPressed: () {
            KeywordHighlights.saveKeywords(map);
            Navigator.of(context).pop();
          },
        ),
      ],
      content: SizedBox(
        height: 180,
        width: 400,
        child: DefaultTabController(
          length: colors.length,
          child: Scaffold(
            appBar: TabBar(tabs: colors.entries.map((e) => Tab(text: e.value)).toList()),
            body: TabBarView(
                children: colors.entries
                    .map((e) => KeepAliveWrapper(
                        child: Padding(
                            padding: const EdgeInsets.all(15),
                            child: TextFormField(
                              minLines: 2,
                              maxLines: 2,
                              initialValue: map[e.key],
                              onChanged: (value) {
                                if (value.isEmpty) {
                                  map.remove(e.key);
                                } else {
                                  map[e.key] = value;
                                }
                              },
                              decoration: decoration(localizations.keyword),
                            ))))
                    .toList()),
          ),
        ),
      ),
    );
  }

  InputDecoration decoration(String label, {String? hintText}) {
    return InputDecoration(
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelText: label,
      isDense: true,
      border: const OutlineInputBorder(),
    );
  }
}
