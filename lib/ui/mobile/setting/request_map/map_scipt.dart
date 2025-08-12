import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:proxypin/l10n/app_localizations.dart';

class MobileMapScript extends StatefulWidget {
  final String? script;

  const MobileMapScript({super.key, this.script});

  @override
  State<MobileMapScript> createState() => MobileMapScriptState();
}

class MobileMapScriptState extends State<MobileMapScript> {
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
        // height: double.infinity,
        child: CodeTheme(
            data: CodeThemeData(styles: monokaiSublimeTheme),
            child: SingleChildScrollView(
              child: CodeField(
                  textStyle: const TextStyle(fontSize: 13),
                  enableSuggestions: true,
                  gutterStyle: const GutterStyle(width: 50, margin: 0),
                  onTapOutside: (event) => FocusScope.of(context).unfocus(),
                  controller: script),
            )));
  }
}
