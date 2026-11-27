import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:code_forge/code_forge.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/component/theme_presets.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/ui/component/search/finder.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:proxypin/network/components/js/file.dart';
import 'package:proxypin/network/components/js/md5.dart';
import 'package:proxypin/network/components/js/xhr.dart';

class JavaScript extends StatefulWidget {
  final String? windowId;

  const JavaScript({super.key, this.windowId});

  @override
  State<StatefulWidget> createState() {
    return _JavaScriptState();
  }
}

class _JavaScriptState extends State<JavaScript> {
  //重置环境
  static bool resetEnvironment = true;

  static JavascriptRuntime? flutterJs;

  late CodeForgeController code;

  final List<({String text, bool error})> outLines = [];

  ScrollController outputScrollController = ScrollController();

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    if (resetEnvironment || flutterJs == null) {
      flutterJs = getJavascriptRuntime(xhr: false);
    }
    // register channel callback
    final channelCallbacks = JavascriptRuntime.channelFunctionsRegistered[flutterJs!.getEngineInstanceId()];
    channelCallbacks!["ConsoleLog"] = consoleLog;
    Md5Bridge.registerMd5(flutterJs!);
    FileBridge.registerFile(flutterJs!);
    flutterJs?.enableFetch2(enabledProxy: true);

    code = CodeForgeController()..text = 'console.log("Hello, World!")';
  }

  @override
  void dispose() {
    code.dispose();
    outputScrollController.dispose();
    if (resetEnvironment) {
      flutterJs?.dispose();
      flutterJs = null;
    }
    super.dispose();
  }

  dynamic consoleLog(dynamic args) async {
    var level = args.removeAt(0);
    String output = args.join(' ');
    if (level == 'info') level = 'warn';
    setState(() {
      outLines.add((text: output, error: level == 'error'));
      print(outLines);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final primaryColor = colors.primary;
    final editorTheme = codeEditorTheme(context);
    return Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(title: const Text("JavaScript", style: TextStyle(fontSize: 16)), centerTitle: true),
        body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (Platforms.isMobile()) {
                FocusScope.of(context).unfocus();
                SystemChannels.textInput.invokeMethod('TextInput.hide');
              }
            },
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  //选择文件
                  ElevatedButton.icon(
                      onPressed: () async {
                        final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['js']);
                        final path = picked?.path;

                        if (path != null) {
                          File file = File(path);
                          String content = await file.readAsString();
                          code.text = content;
                          setState(() {});
                        }
                      },
                      icon: const Icon(Icons.folder_open),
                      label: const Text("File")),
                  const SizedBox(width: 15),
                  FilledButton.icon(
                      onPressed: () async {
                        outLines.clear();
                        //失去焦点
                        FocusScope.of(context).unfocus();
                        var jsResult = await flutterJs!.evaluateAsync(code.text);
                        if (jsResult.isPromise || jsResult.rawResult is Future) {
                          jsResult = await flutterJs!.handlePromise(jsResult);
                        }
                        if (jsResult.isError) {
                          setState(() {
                            outLines.add((text: jsResult.toString(), error: true));
                          });
                        }
                      },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text("Run")),
                  const SizedBox(width: 10),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                  height: MediaQuery.of(context).size.height * 0.43,
                  child: CodeForge(
                    key: codeEditorThemeKey(null, editorTheme),
                    controller: code,
                    language: langJavascript,
                    editorTheme: editorTheme,
                    autoFocus: true,
                    enableGuideLines: false,
                    finderBuilder: (c, controller) => FindPanelView(controller: controller),
                    textStyle: const TextStyle(fontSize: 13),
                  )),
              Row(children: [
                const SizedBox(width: 10),
                Text("${localizations.output}:",
                    style: TextStyle(fontSize: 16, color: primaryColor, fontWeight: FontWeight.w500)),
                const SizedBox(width: 15),
                //copy
                IconButton(
                    icon: Icon(Icons.copy, color: primaryColor, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: outLines.map((line) => line.text).join("\n")));
                      FlutterToastr.show(localizations.copied, context, duration: 3);
                    }),
              ]),
              Expanded(
                  child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      color: colors.surfaceContainer,
                      child: Scrollbar(
                          controller: outputScrollController,
                          thumbVisibility: true,
                          trackVisibility: true,
                          child: SingleChildScrollView(
                              controller: outputScrollController,
                              child: SelectionArea(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                for (final line in outLines)
                                  Text(line.text,
                                      style: TextStyle(
                                        color: line.error ? colors.error : colors.onSurface,
                                        fontSize: 13,
                                      )),
                              ])))))),
            ])));
  }
}
