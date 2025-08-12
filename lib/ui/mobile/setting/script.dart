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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:proxypin/network/components/manager/script_manager.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/mobile/widgets/floating_window.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// @author wanghongen
/// 2023/10/19
/// js脚本
class MobileScript extends StatefulWidget {
  const MobileScript({super.key});

  @override
  State<StatefulWidget> createState() => _MobileScriptState();
}

bool _refresh = false;

/// 刷新脚本
void _refreshScript({bool force = false}) {
  if (_refresh && !force) {
    return;
  }
  _refresh = true;
  Future.delayed(const Duration(milliseconds: 1500), () async {
    _refresh = false;
    (await ScriptManager.instance).flushConfig();
  });
}

class _MobileScriptState extends State<MobileScript> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text(localizations.script, style: const TextStyle(fontSize: 16))),
        body: Padding(
            padding: const EdgeInsets.only(left: 15, right: 10),
            child: futureWidget(
                ScriptManager.instance,
                loading: true,
                (data) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          SizedBox(
                              child: ListTile(
                                  title: Text(localizations.enableScript),
                                  subtitle: Text(localizations.scriptUseDescribe),
                                  trailing: SwitchWidget(
                                    value: data.enabled,
                                    onChanged: (value) {
                                      data.enabled = value;
                                      _refreshScript();
                                    },
                                  ))),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                  icon: const Icon(Icons.add, size: 18),
                                  onPressed: scriptEdit,
                                  label: Text(localizations.add)),
                              const SizedBox(width: 5),
                              TextButton.icon(
                                icon: const Icon(Icons.input_rounded, size: 18),
                                onPressed: import,
                                label: Text(localizations.import),
                              ),
                              const SizedBox(width: 5),
                              TextButton.icon(
                                icon: const Icon(Icons.terminal, size: 18),
                                onPressed: consoleLog,
                                label: Text(localizations.logger),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Expanded(child: ScriptList(scripts: data.list)),
                        ]))));
  }

  consoleLog() {
    // FloatingWindowManager().show(context);
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ScriptConsoleLog()));
  }

  //导入js
  import() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.isEmpty) {
      return;
    }
    var file = result.files.single.xFile;
    try {
      var scriptManager = (await ScriptManager.instance);
      var json = jsonDecode(utf8.decode(await file.readAsBytes()));

      if (json is List<dynamic>) {
        for (var item in json) {
          var scriptItem = ScriptItem.fromJson(item);
          await scriptManager.addScript(scriptItem, item['script']);
        }
      } else {
        var scriptItem = ScriptItem.fromJson(json);
        await scriptManager.addScript(scriptItem, json['script']);
      }

      _refreshScript();
      if (mounted) {
        FlutterToastr.show(localizations.importSuccess, context);
      }
      setState(() {});
    } catch (e, t) {
      logger.e('导入失败 $file', error: e, stackTrace: t);
      if (mounted) {
        FlutterToastr.show("${localizations.importFailed} $e", context);
      }
    }
  }

  /// 添加脚本
  scriptEdit() async {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ScriptEdit())).then((value) {
      if (value != null) {
        setState(() {});
      }
    });
  }
}

///控制台日志
class ScriptConsoleLog extends StatefulWidget {
  const ScriptConsoleLog({super.key});

  @override
  State<StatefulWidget> createState() => _ScriptConsoleLogState();
}

class _ScriptConsoleLogState extends State<ScriptConsoleLog> {
  static final List<LogInfo> logs = [];
  static FloatingWindowManager floatingWindowManager = FloatingWindowManager();

  final ScrollController _scrollController = ScrollController();

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((d) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });

    if (floatingWindowManager.isShow) {
      return;
    }

    LogHandler logHandler = LogHandler(
        channelId: hashCode,
        handle: (log) {
          logs.add(log);

          if (!mounted && !floatingWindowManager.isShow) {
            logs.clear();
            //关闭日志监听
            ScriptManager.removeLogHandler(hashCode);
            return;
          }

          if (mounted) {
            setState(() {});
          }
        });

    ScriptManager.registerLogHandler(logHandler);
  }

  @override
  void dispose() {
    super.dispose();
    if (!floatingWindowManager.isShow) {
      logs.clear();
      ScriptManager.removeLogHandler(hashCode);
    }
    _scrollController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text(localizations.logger, style: const TextStyle(fontSize: 16)), actions: [
          IconButton(
              tooltip: localizations.windowMode,
              onPressed: () {
                if (floatingWindowManager.isShow) {
                  floatingWindowManager.hide();
                  return;
                }
                floatingWindowManager.show(context,
                    widget: ScriptLogSmallWindow(floatingWindowManager: floatingWindowManager));
              },
              icon: const Icon(Icons.picture_in_picture_alt_rounded)),
          const SizedBox(width: 5),
          IconButton(
              tooltip: localizations.clear,
              onPressed: () => setState(() {
                    logs.clear();
                  }),
              icon: const Icon(Icons.delete)),
          const SizedBox(width: 10)
        ]),
        body: Container(
          padding: const EdgeInsets.only(top: 10, bottom: 10, right: 3),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.2))),
          child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              thickness: 6,
              interactive: true,
              child: loggerContent()),
        ));
  }

  Widget loggerContent() {
    return ListView.builder(
        controller: _scrollController,
        itemCount: logs.length,
        itemBuilder: (context, index) {
          var log = logs[index];
          Color? color;
          if (log.level == 'error') {
            color = Colors.red;
          } else if (log.level == 'warn') {
            color = Colors.orange;
          }

          return Padding(
              padding: const EdgeInsets.only(bottom: 5, left: 3, right: 3),
              child: Row(
                children: [
                  Text(log.time.timeFormat(), style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(width: 8),
                  Text(log.level, style: TextStyle(fontSize: 13, color: color)),
                  const SizedBox(width: 8),
                  Expanded(child: SelectableText(log.output, style: TextStyle(fontSize: 13, color: color))),
                ],
              ));
        });
  }
}

class ScriptLogSmallWindow extends StatefulWidget {
  final FloatingWindowManager floatingWindowManager;

  const ScriptLogSmallWindow({super.key, required this.floatingWindowManager});

  @override
  State<StatefulWidget> createState() => _ScriptLogSmallWindowState();
}

class _ScriptLogSmallWindowState extends State<ScriptLogSmallWindow> {
  final List<LogInfo> logs = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    LogHandler logHandler = LogHandler(
        channelId: hashCode,
        handle: (log) {
          logs.add(log);
          if (!mounted) {
            ScriptManager.removeLogHandler(hashCode);
            return;
          }
          setState(() {});
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        });
    ScriptManager.registerLogHandler(logHandler);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    ScriptManager.removeLogHandler(hashCode);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FloatingWindow(
        top: 320,
        right: 8,
        child: Material(
            child: Container(
                height: 320,
                width: 180,
                decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.3),
                    border: Border.all(color: Colors.grey.withOpacity(0.8)),
                    borderRadius: const BorderRadius.all(Radius.circular(10))),
                child: Stack(
                  children: [
                    Positioned(
                        top: -12,
                        left: -5,
                        child: IconButton(
                            onPressed: () {
                              Navigator.of(context)
                                  .push(MaterialPageRoute(builder: (context) => const ScriptConsoleLog()));
                            },
                            icon: const Icon(Icons.picture_in_picture, size: 20))),
                    Positioned(
                        top: -12,
                        right: -8,
                        child: IconButton(
                            onPressed: () => widget.floatingWindowManager.hide(),
                            icon: const Icon(Icons.close, size: 20))),
                    list()
                  ],
                ))));
  }

  Widget list() {
    return Padding(
        padding: const EdgeInsets.only(bottom: 5, top: 18),
        child: Scrollbar(
            child: ListView.builder(
                controller: _scrollController,
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  var log = logs[index];
                  return Padding(
                      padding: const EdgeInsets.only(bottom: 3, left: 3, right: 3),
                      child: Text(log.output,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: log.level == 'error' ? Colors.red : null)));
                })));
  }
}

/// 编辑脚本
class ScriptEdit extends StatefulWidget {
  final ScriptItem? scriptItem;
  final String? script;
  final String? url;
  final String? title;

  const ScriptEdit({super.key, this.scriptItem, this.script, this.url, this.title});

  @override
  State<StatefulWidget> createState() => _ScriptEditState();
}

class _ScriptEditState extends State<ScriptEdit> {
  late CodeController script;
  late TextEditingController nameController;
  late TextEditingController urlController;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    script = CodeController(language: javascript, text: widget.script ?? ScriptManager.template);
    nameController = TextEditingController(text: widget.scriptItem?.name ?? widget.title);
    urlController = TextEditingController(text: widget.scriptItem?.url ?? widget.url);
  }

  @override
  void dispose() {
    script.dispose();
    nameController.dispose();
    urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    GlobalKey formKey = GlobalKey<FormState>();
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    return Scaffold(
        appBar: AppBar(
            title: Row(children: [
              Text(localizations.scriptEdit, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              const SizedBox(width: 10),
              Text.rich(TextSpan(
                  text: localizations.useGuide,
                  style: const TextStyle(color: Colors.blue, fontSize: 14),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => launchUrl(
                        mode: LaunchMode.externalApplication,
                        Uri.parse(isCN
                            ? 'https://gitee.com/wanghongenpin/proxypin/wikis/%E8%84%9A%E6%9C%AC'
                            : 'https://github.com/wanghongenpin/proxypin/wiki/Script')))),
            ]),
            actions: [
              TextButton(
                  onPressed: () async {
                    if (!(formKey.currentState as FormState).validate()) {
                      FlutterToastr.show("${localizations.name} URL ${localizations.cannotBeEmpty}", context,
                          position: FlutterToastr.top);
                      return;
                    }
                    //新增
                    var scriptManager = await ScriptManager.instance;
                    if (widget.scriptItem == null) {
                      var scriptItem = ScriptItem(true, nameController.text, urlController.text);
                      await scriptManager.addScript(scriptItem, script.text);
                    } else {
                      widget.scriptItem?.name = nameController.text;
                      widget.scriptItem?.url = urlController.text;
                      widget.scriptItem?.urlReg = null;
                      await scriptManager.updateScript(widget.scriptItem!, script.text);
                    }

                    _refreshScript(force: true);
                    if (context.mounted) {
                      FlutterToastr.show(localizations.saveSuccess, context);
                      Navigator.of(context).maybePop(true);
                    }
                  },
                  child: Text(localizations.save)),
            ]),
        body: Form(
            key: formKey,
            child: ListView(
              children: [
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: textField("${localizations.name}:", nameController, localizations.pleaseEnter)),
                const SizedBox(height: 10),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: textField("URL:", urlController, "github.com/api/*", keyboardType: TextInputType.url)),
                const SizedBox(height: 10),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text("${localizations.script}:")),
                const SizedBox(height: 5),
                CodeTheme(
                    data: CodeThemeData(styles: monokaiSublimeTheme),
                    child: SingleChildScrollView(
                        child: CodeField(
                            textStyle: const TextStyle(fontSize: 13),
                            enableSuggestions: true,
                            gutterStyle: const GutterStyle(width: 50, margin: 0),
                            onTapOutside: (event) => FocusScope.of(context).unfocus(),
                            controller: script)))
              ],
            )));
  }

  Widget textField(String label, TextEditingController controller, String hint, {TextInputType? keyboardType}) {
    return Row(children: [
      SizedBox(width: 50, child: Text(label)),
      Expanded(
          child: TextFormField(
        controller: controller,
        validator: (val) => val?.isNotEmpty == true ? null : "",
        keyboardType: keyboardType,
        decoration: InputDecoration(
            hintText: hint,
            contentPadding: const EdgeInsets.all(10),
            errorStyle: const TextStyle(height: 0, fontSize: 0),
            focusedBorder: focusedBorder(),
            isDense: true,
            border: const OutlineInputBorder()),
      ))
    ]);
  }

  InputBorder focusedBorder() {
    return OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2));
  }
}

/// 脚本列表
class ScriptList extends StatefulWidget {
  final List<ScriptItem> scripts;

  const ScriptList({super.key, required this.scripts});

  @override
  State<ScriptList> createState() => _ScriptListState();
}

class _ScriptListState extends State<ScriptList> {
  Set<int> selected = {};
  bool multiple = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        persistentFooterButtons: [multiple ? globalMenu() : const SizedBox()],
        body: Container(
            padding: const EdgeInsets.only(top: 10, bottom: 30),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.2))),
            child: Scrollbar(
                child: ListView(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Container(width: 100, padding: const EdgeInsets.only(left: 10), child: Text(localizations.name)),
                  SizedBox(width: 50, child: Text(localizations.enable, textAlign: TextAlign.center)),
                  const VerticalDivider(),
                  const Expanded(child: Text("URL")),
                ],
              ),
              const Divider(thickness: 0.5),
              Column(children: rows(widget.scripts))
            ]))));
  }

  globalMenu() {
    return Stack(children: [
      Container(
          height: 50,
          width: double.infinity,
          margin: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.2)))),
      Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Center(
              child: TextButton(
                  onPressed: () {},
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    TextButton.icon(
                        onPressed: () {
                          export(context, selected.toList());
                          setState(() {
                            selected.clear();
                            multiple = false;
                          });
                        },
                        icon: const Icon(Icons.share, size: 18),
                        label: Text(localizations.export, style: const TextStyle(fontSize: 14))),
                    TextButton.icon(
                        onPressed: () => removeScripts(selected.toList()),
                        icon: const Icon(Icons.delete, size: 18),
                        label: Text(localizations.delete, style: const TextStyle(fontSize: 14))),
                    TextButton.icon(
                        onPressed: () {
                          setState(() {
                            multiple = false;
                            selected.clear();
                          });
                        },
                        icon: const Icon(Icons.cancel, size: 18),
                        label: Text(localizations.cancel, style: const TextStyle(fontSize: 14))),
                  ]))))
    ]);
  }

  List<Widget> rows(List<ScriptItem> list) {
    var primaryColor = Theme.of(context).colorScheme.primary;

    return List.generate(list.length, (index) {
      return InkWell(
          splashColor: primaryColor.withOpacity(0.3),
          onTap: () async {
            if (multiple) {
              setState(() {
                if (!selected.add(index)) {
                  selected.remove(index);
                }
              });
              return;
            }
            showEdit(index);
          },
          onLongPress: () => showMenus(index),
          child: Container(
              color: selected.contains(index)
                  ? primaryColor.withOpacity(0.8)
                  : index.isEven
                      ? Colors.grey.withOpacity(0.1)
                      : null,
              height: 45,
              padding: const EdgeInsets.all(5),
              child: Row(
                children: [
                  SizedBox(
                      width: 100,
                      child: Text(list[index].name!,
                          style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                  SizedBox(
                      width: 50,
                      child: Transform.scale(
                          scale: 0.65,
                          child: SwitchWidget(
                              value: list[index].enabled,
                              onChanged: (val) {
                                list[index].enabled = val;
                                _refreshScript();
                              }))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(list[index].url.fixAutoLines(), style: const TextStyle(fontSize: 13))),
                ],
              )));
    });
  }

  //点击菜单
  showMenus(int index) {
    setState(() {
      selected.add(index);
    });

    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        enableDrag: true,
        builder: (context) {
          return Wrap(
            alignment: WrapAlignment.center,
            children: [
              BottomSheetItem(
                  text: localizations.multiple,
                  onPressed: () {
                    setState(() => multiple = true);
                  }),
              const Divider(thickness: 0.5, height: 1),
              BottomSheetItem(text: localizations.edit, onPressed: () => showEdit(index)),
              const Divider(thickness: 0.5, height: 1),
              BottomSheetItem(text: localizations.share, onPressed: () => export(context, [index])),
              const Divider(thickness: 0.5, height: 1),
              BottomSheetItem(
                  text: widget.scripts[index].enabled ? localizations.disabled : localizations.enable,
                  onPressed: () {
                    widget.scripts[index].enabled = !widget.scripts[index].enabled;
                    _refreshScript();
                  }),
              const Divider(thickness: 0.5, height: 1),
              BottomSheetItem(
                  text: localizations.delete,
                  onPressed: () async {
                    await (await ScriptManager.instance).removeScript(index);
                    _refreshScript(force: true);
                    if (context.mounted) FlutterToastr.show(localizations.importSuccess, context);
                  }),
              Container(color: Theme.of(context).hoverColor, height: 8),
              TextButton(
                child: Container(
                    height: 45,
                    width: double.infinity,
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(localizations.cancel, textAlign: TextAlign.center)),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        }).then((value) {
      if (multiple) {
        return;
      }
      setState(() {
        selected.remove(index);
      });
    });
  }

  showEdit([int? index]) async {
    String? script = index == null ? null : await (await ScriptManager.instance).getScript(widget.scripts[index]);
    if (!mounted) {
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (context) => ScriptEdit(scriptItem: index == null ? null : widget.scripts[index], script: script)))
        .then((value) {
      if (value != null) {
        setState(() {});
      }
    });
  }

  //导出js
  export(BuildContext context, List<int> indexes) async {
    if (indexes.isEmpty) return;
    //文件名称
    String fileName = 'proxypin-scripts.json';
    var scriptManager = await ScriptManager.instance;
    List<dynamic> json = [];
    for (var idx in indexes) {
      var item = widget.scripts[idx];
      var map = item.toJson();
      map.remove("scriptPath");
      map['script'] = await scriptManager.getScript(item);
      json.add(map);
    }

    RenderBox? box;
    if (await Platforms.isIpad() && context.mounted) {
      box = context.findRenderObject() as RenderBox?;
    }

    final XFile file = XFile.fromData(utf8.encode(jsonEncode(json)), mimeType: 'json');
    Share.shareXFiles([file], fileNameOverrides: [fileName], sharePositionOrigin: box?.paintBounds);
  }

  enableStatus(bool enable) {
    for (var idx in selected) {
      widget.scripts[idx].enabled = enable;
    }
    setState(() {});
    _refreshScript();
  }

  removeScripts(List<int> indexes) async {
    if (indexes.isEmpty) return;
    showConfirmDialog(context, content: localizations.confirmContent, onConfirm: () async {
      var scriptManager = await ScriptManager.instance;
      for (var idx in indexes) {
        await scriptManager.removeScript(idx);
      }

      setState(() {
        selected.clear();
      });
      _refreshScript(force: true);

      if (mounted) FlutterToastr.show(localizations.deleteSuccess, context);
    });
  }
}
