import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/request_map_manager.dart';
import 'package:proxypin/ui/component/app_dialog.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/desktop/toolbar/setting/request_map/map_local.dart';
import 'package:proxypin/ui/desktop/toolbar/setting/request_map/map_scipt.dart';
import 'package:proxypin/utils/lang.dart';

import '../../../../network/util/logger.dart';

bool _refresh = false;

/// 刷新配置
void _refreshConfig({bool force = false}) {
  if (_refresh && !force) {
    return;
  }
  _refresh = true;
  Future.delayed(const Duration(milliseconds: 1500), () async {
    _refresh = false;
    await RequestMapManager.instance.then((manager) => manager.flushConfig());
    await DesktopMultiWindow.invokeMethod(0, "refreshRequestMap");
  });
}

class RequestMapPage extends StatefulWidget {
  final int? windowId;

  const RequestMapPage({super.key, this.windowId});

  @override
  State<StatefulWidget> createState() => _RequestMapPageState();
}

class _RequestMapPageState extends State<RequestMapPage> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(onKeyEvent);
    super.dispose();
  }

  bool onKeyEvent(KeyEvent event) {
    if (HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.escape) && Navigator.canPop(context)) {
      Navigator.maybePop(context);
      return true;
    }

    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      HardwareKeyboard.instance.removeHandler(onKeyEvent);
      WindowController.fromWindowId(widget.windowId!).close();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            title: Text(localizations.requestMap, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            toolbarHeight: 36,
            centerTitle: true),
        body: Padding(
            padding: const EdgeInsets.only(left: 15, right: 10),
            child: futureWidget(
                RequestMapManager.instance,
                loading: true,
                (data) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Row(children: [
                            SizedBox(
                                width: 350,
                                child: ListTile(
                                    title: Text("${localizations.enable} ${localizations.requestMap}"),
                                    subtitle:
                                        Text(localizations.requestMapDescribe, style: const TextStyle(fontSize: 12)),
                                    trailing: SwitchWidget(
                                        value: data.enabled,
                                        scale: 0.8,
                                        onChanged: (value) {
                                          data.enabled = value;
                                          _refreshConfig();
                                        }))),
                            Expanded(
                                child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                const SizedBox(width: 10),
                                TextButton.icon(
                                    icon: const Icon(Icons.add, size: 18),
                                    onPressed: showEdit,
                                    label: Text(localizations.add)),
                                const SizedBox(width: 10),
                                TextButton.icon(
                                  icon: const Icon(Icons.input_rounded, size: 18),
                                  onPressed: import,
                                  label: Text(localizations.import),
                                ),
                                const SizedBox(width: 10),
                              ],
                            )),
                            const SizedBox(width: 15)
                          ]),
                          const SizedBox(height: 5),
                          RequestMapList(list: data.rules, windowId: widget.windowId),
                        ]))));
  }

  //导入js
  Future<void> import() async {
    String? path;
    if (Platform.isMacOS) {
      path = await DesktopMultiWindow.invokeMethod(0, "pickFiles", {
        "allowedExtensions": ['json']
      });
      WindowController.fromWindowId(widget.windowId!).show();
    } else {
      FilePickerResult? result =
          await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      path = result?.files.single.path;
    }

    if (path == null) {
      return;
    }
    try {
      var json = jsonDecode(await File(path).readAsString());
      var manager = (await RequestMapManager.instance);
      if (json is List<dynamic>) {
        for (var item in json) {
          var mapRule = RequestMapRule.fromJson(item);
          var requestMapItem = RequestMapItem.fromJson(item['item']);
          await manager.addRule(mapRule, requestMapItem);
        }
      }

      if (mounted) {
        CustomToast.success(localizations.importSuccess).show(context);
      }
      setState(() {});
    } catch (e, t) {
      logger.e('[RequestMap] import fail $path', error: e, stackTrace: t);
      if (mounted) {
        CustomToast.error("${localizations.importFailed} $e").show(context);
      }
    }
  }

  /// 添加脚本
  Future<void> showEdit() async {
    showDialog(barrierDismissible: false, context: context, builder: (_) => const RequestMapEdit()).then((value) {
      if (value != null) {
        setState(() {});
      }
    });
  }
}

/// 脚本列表
class RequestMapList extends StatefulWidget {
  final int? windowId;
  final List<RequestMapRule> list;

  const RequestMapList({super.key, required this.list, required this.windowId});

  @override
  State<RequestMapList> createState() => _RequestMapListState();
}

class _RequestMapListState extends State<RequestMapList> {
  Set<int> selected = {};
  bool isPressed = false;
  Offset? lastPressPosition;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onSecondaryTap: () {
          if (lastPressPosition == null) {
            return;
          }
          showGlobalMenu(lastPressPosition!);
        },
        onTapDown: (details) {
          if (selected.isEmpty) {
            return;
          }
          if (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) {
            return;
          }
          setState(() {
            selected.clear();
          });
        },
        child: Listener(
            onPointerUp: (event) => isPressed = false,
            onPointerDown: (event) {
              lastPressPosition = event.localPosition;
              if (event.buttons == kPrimaryMouseButton) {
                isPressed = true;
              }
            },
            child: Container(
                padding: const EdgeInsets.only(top: 10),
                height: 530,
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.2))),
                child: SingleChildScrollView(
                    child: Column(children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Container(width: 130, padding: const EdgeInsets.only(left: 10), child: Text(localizations.name)),
                      SizedBox(width: 50, child: Text(localizations.enable, textAlign: TextAlign.center)),
                      const VerticalDivider(),
                      const Expanded(child: Text("URL")),
                      SizedBox(width: 100, child: Text(localizations.action, textAlign: TextAlign.center)),
                    ],
                  ),
                  const Divider(thickness: 0.5),
                  Column(children: rows(widget.list))
                ])))));
  }

  List<Widget> rows(List<RequestMapRule> list) {
    var primaryColor = Theme.of(context).colorScheme.primary;
    bool isEN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'en');

    return List.generate(list.length, (index) {
      return InkWell(
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          hoverColor: primaryColor.withOpacity(0.3),
          onSecondaryTapDown: (details) => showMenus(details, index),
          onDoubleTap: () => showEdit(index),
          onHover: (hover) {
            if (isPressed && !selected.contains(index)) {
              setState(() {
                selected.add(index);
              });
            }
          },
          onTap: () {
            if (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) {
              setState(() {
                selected.contains(index) ? selected.remove(index) : selected.add(index);
              });
              return;
            }
            if (selected.isEmpty) {
              return;
            }
            setState(() {
              selected.clear();
            });
          },
          child: Container(
              color: selected.contains(index)
                  ? primaryColor.withOpacity(0.6)
                  : index.isEven
                      ? Colors.grey.withOpacity(0.1)
                      : null,
              height: 30,
              padding: const EdgeInsets.all(5),
              child: Row(
                children: [
                  SizedBox(width: 130, child: Text(list[index].name ?? '', style: const TextStyle(fontSize: 13))),
                  SizedBox(
                      width: 40,
                      child: Transform.scale(
                          scale: 0.6,
                          child: SwitchWidget(
                              value: list[index].enabled,
                              onChanged: (val) {
                                list[index].enabled = val;
                                _refreshConfig();
                              }))),
                  const SizedBox(width: 20),
                  Expanded(
                      child:
                          Text(list[index].url, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                  SizedBox(
                      width: 100,
                      child: Text(isEN ? list[index].type.name.camelCaseToSpaced() : list[index].type.label,
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
                ],
              )));
    });
  }

  void showGlobalMenu(Offset offset) {
    showContextMenu(context, offset, items: [
      PopupMenuItem(height: 35, child: Text(localizations.newBuilt), onTap: () => showEdit()),
      PopupMenuItem(height: 35, child: Text(localizations.export), onTap: () => export(selected.toList())),
      const PopupMenuDivider(),
      PopupMenuItem(height: 35, child: Text(localizations.enableSelect), onTap: () => enableStatus(true)),
      PopupMenuItem(height: 35, child: Text(localizations.disableSelect), onTap: () => enableStatus(false)),
      const PopupMenuDivider(),
      PopupMenuItem(height: 35, child: Text(localizations.deleteSelect), onTap: () => remove(selected.toList())),
    ]);
  }

  //点击菜单
  void showMenus(TapDownDetails details, int index) {
    if (selected.length > 1) {
      showGlobalMenu(details.globalPosition);
      return;
    }
    setState(() {
      selected.add(index);
    });

    showContextMenu(context, details.globalPosition, items: [
      PopupMenuItem(height: 35, child: Text(localizations.edit), onTap: () => showEdit(index)),
      PopupMenuItem(height: 35, child: Text(localizations.export), onTap: () => export([index])),
      PopupMenuItem(
          height: 35,
          child: widget.list[index].enabled ? Text(localizations.disabled) : Text(localizations.enable),
          onTap: () {
            widget.list[index].enabled = !widget.list[index].enabled;
            _refreshConfig();
          }),
      const PopupMenuDivider(),
      PopupMenuItem(
          height: 35,
          child: Text(localizations.delete),
          onTap: () async {
            var manager = await RequestMapManager.instance;
            await manager.deleteRule(index);
            _refreshConfig();
          }),
    ]).then((value) {
      if (mounted) {
        setState(() {
          selected.remove(index);
        });
      }
    });
  }

  Future<void> showEdit([int? index]) async {
    final item = index == null ? null : await (await RequestMapManager.instance).getMapItem(widget.list[index]);
    if (!mounted) {
      return;
    }

    showDialog(
        barrierDismissible: false,
        context: context,
        builder: (_) => RequestMapEdit(rule: index == null ? null : widget.list[index], item: item)).then((value) {
      if (value != null) {
        setState(() {});
      }
    });
  }

  //导出
  Future<void> export(List<int> indexes) async {
    if (indexes.isEmpty) return;
    //文件名称
    String fileName = 'request_map.json';
    String? path;
    if (Platform.isMacOS) {
      path = await DesktopMultiWindow.invokeMethod(0, "saveFile", {"fileName": fileName});

      if (widget.windowId != null) WindowController.fromWindowId(widget.windowId!).show();
    } else {
      path = await FilePicker.platform.saveFile(fileName: fileName);
    }
    if (path == null) {
      return;
    }

    var manager = await RequestMapManager.instance;
    List<dynamic> json = [];
    for (var idx in indexes) {
      var item = widget.list[idx];
      var map = item.toJson();
      map.remove("itemPath");
      map['item'] = (await manager.getMapItem(item))?.toJson();
      json.add(map);
    }

    await File(path).writeAsBytes(utf8.encode(jsonEncode(json)));

    if (mounted) FlutterToastr.show(localizations.exportSuccess, context);
  }

  void enableStatus(bool enable) {
    for (var idx in selected) {
      widget.list[idx].enabled = enable;
    }
    setState(() {});
    _refreshConfig();
  }

  Future<void> remove(List<int> indexes) async {
    if (indexes.isEmpty) return;
    showConfirmDialog(context, content: localizations.confirmContent, onConfirm: () async {
      var manager = await RequestMapManager.instance;
      for (var idx in indexes) {
        await manager.deleteRule(idx);
      }

      setState(() {
        selected.clear();
      });
      _refreshConfig(force: true);

      if (mounted) FlutterToastr.show(localizations.deleteSuccess, context);
    });
  }
}

///请求重写规则添加对话框
class RequestMapEdit extends StatefulWidget {
  final RequestMapRule? rule;
  final RequestMapItem? item;
  final int? windowId;
  final String? url;
  final String? title;

  const RequestMapEdit({super.key, this.rule, this.windowId, this.item, this.url, this.title});

  @override
  State<StatefulWidget> createState() {
    return _RequestMapEditState();
  }
}

class _RequestMapEditState extends State<RequestMapEdit> {
  final mapLocalKey = GlobalKey<MapLocaleState>();
  final mapScriptKey = GlobalKey<MapScriptState>();

  late RequestMapRule rule;

  late RequestMapType mapType;
  late TextEditingController nameInput;
  late TextEditingController urlInput;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    rule = widget.rule ?? RequestMapRule(url: widget.url ?? '', type: RequestMapType.local);
    mapType = rule.type;
    nameInput = TextEditingController(text: rule.name ?? widget.title);
    urlInput = TextEditingController(text: rule.url);
  }

  @override
  void dispose() {
    urlInput.dispose();
    nameInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    GlobalKey formKey = GlobalKey<FormState>();
    bool isEN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'en');

    return AlertDialog(
        scrollable: true,
        titlePadding: const EdgeInsets.only(top: 10, left: 20),
        actionsPadding: const EdgeInsets.only(right: 15, bottom: 15),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        title: Row(children: [
          Text(localizations.requestRewriteRule, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ]),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        content: Container(
            width: 550,
            constraints: const BoxConstraints(minHeight: 200, maxHeight: 530),
            child: Form(
                key: formKey,
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(children: [
                        SizedBox(width: 55, child: Text('${localizations.enable}:')),
                        SwitchWidget(value: rule.enabled, onChanged: (val) => rule.enabled = val, scale: 0.8)
                      ]),
                      const SizedBox(height: 5),
                      textField('${localizations.name}:', nameInput, localizations.pleaseEnter),
                      const SizedBox(height: 5),
                      textField('URL:', urlInput, 'https://www.example.com/api/*', required: true),
                      const SizedBox(height: 5),
                      Row(children: [
                        SizedBox(width: 60, child: Text('${localizations.action}:')),
                        SizedBox(
                            width: 150,
                            height: 33,
                            child: DropdownButtonFormField<RequestMapType>(
                              onSaved: (val) => rule.type = val!,
                              value: mapType,
                              decoration: InputDecoration(
                                  errorStyle: const TextStyle(height: 0, fontSize: 0),
                                  contentPadding: const EdgeInsets.only(left: 7, right: 7),
                                  focusedBorder: focusedBorder(),
                                  border: const OutlineInputBorder()),
                              items: RequestMapType.values
                                  .map((e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(isEN ? e.name : e.label, style: const TextStyle(fontSize: 13))))
                                  .toList(),
                              onChanged: onChangeType,
                            )),
                        const SizedBox(width: 10),
                      ]),
                      const SizedBox(height: 10),
                      mapRule(),
                    ]))),
        actions: [
          ElevatedButton(child: Text(localizations.close), onPressed: () => Navigator.of(context).pop()),
          FilledButton(
              child: Text(localizations.save),
              onPressed: () async {
                if (!(formKey.currentState as FormState).validate()) {
                  FlutterToastr.show(localizations.cannotBeEmpty, context, position: FlutterToastr.center);
                  return;
                }

                (formKey.currentState as FormState).save();
                rule.name = nameInput.text;
                rule.url = urlInput.text;
                rule.type = mapType;
                RequestMapItem item;
                if (mapType == RequestMapType.local) {
                  item = mapLocalKey.currentState!.getRequestMapItem();
                } else {
                  String? scriptCode = mapScriptKey.currentState?.getScriptCode();
                  item = widget.item ?? RequestMapItem();
                  item.script = scriptCode;
                }

                var requestMapManager = await RequestMapManager.instance;
                var index = requestMapManager.rules.indexOf(rule);
                if (index >= 0) {
                  await requestMapManager.updateRule(rule, item);
                } else {
                  await requestMapManager.addRule(rule, item);
                }

                DesktopMultiWindow.invokeMethod(0, "refreshRequestMap");
                if (mounted) {
                  Navigator.of(this.context).pop(rule);
                }
              })
        ]);
  }

  void onChangeType(RequestMapType? val) async {
    if (mapType == val) return;
    mapType = val!;
    setState(() {});
  }

  Widget mapRule() {
    if (mapType == RequestMapType.script) {
      return DesktopMapScript(key: mapScriptKey, script: widget.item?.script);
    }

    return DesktopMapLocal(key: mapLocalKey, item: widget.item, windowId: widget.windowId);
  }

  Widget textField(String label, TextEditingController controller, String hint,
      {bool required = false, FormFieldSetter<String>? onSaved}) {
    return Row(children: [
      SizedBox(width: 60, child: Text(label)),
      Expanded(
          child: TextFormField(
        controller: controller,
        style: const TextStyle(fontSize: 14),
        validator: (val) => val?.isNotEmpty == true || !required ? null : "",
        onSaved: onSaved,
        decoration: InputDecoration(
            hintText: hint,
            constraints: const BoxConstraints(minHeight: 38),
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
