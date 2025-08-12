import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:proxypin/l10n/app_localizations.dart';

class DesktopMapScript extends StatefulWidget {
  final String? script;

  const DesktopMapScript({super.key, this.script});

  @override
  State<StatefulWidget> createState() => MapScriptState();
}

class MapScriptState extends State<DesktopMapScript> {
  static String template = """
async function onRequest(context, request) {
  console.log(request.url);
  //use fetch API request
  // var result = await fetch('https://www.baidu.com/');
  var response = {
    statusCode: 200,
    body: 'Hello, world!',
    headers: {
      'Content-Type': 'text/plain',
      'X-My-Header': 'My-Value'
    }
  };
  return response;
}
  """;
  late CodeController script;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  String getScriptCode() {
    return script.text;
  }

  @override
  void initState() {
    super.initState();
    script = CodeController(language: javascript, text: widget.script ?? template);
  }

  @override
  void dispose() {
    script.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        height: 320,
        child: CodeTheme(
            data: CodeThemeData(styles: monokaiSublimeTheme),
            child:
                SingleChildScrollView(child: CodeField(textStyle: const TextStyle(fontSize: 13), controller: script))));
  }
}
