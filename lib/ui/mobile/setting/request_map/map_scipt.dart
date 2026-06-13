import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:re_highlight/languages/javascript.dart';

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
  late CodeForgeController script;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  String getScriptCode() {
    return script.text;
  }

  @override
  void initState() {
    super.initState();
    script = CodeForgeController()..text = widget.script ?? template;
  }

  @override
  void dispose() {
    script.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 380,
      child: CodeForge(
        controller: script,
        language: langJavascript,
        editorTheme: monokaiSublimeTheme,
        autoFocus: true,
        textStyle: const TextStyle(fontSize: 13),
      ),
    );
  }
}
