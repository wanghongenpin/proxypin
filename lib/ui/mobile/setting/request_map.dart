import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/request_map_manager.dart';
import 'package:proxypin/ui/component/app_dialog.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/mobile/setting/request_map/map_local.dart';
import 'package:proxypin/ui/mobile/setting/request_map/map_scipt.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../network/util/logger.dart';
import '../../../utils/platform.dart';

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
  });
}

class MobileRequestMapPage extends StatefulWidget {
  const MobileRequestMapPage({super.key});

  @override
  State<StatefulWidget> createState() => _RequestMapPageState();
}

class _RequestMapPageState extends State<MobileRequestMapPage> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            title: Text(localizations.requestMap, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            toolbarHeight: 36,
            centerTitle: true),
        body: Padding(
            padding: const EdgeInsets.all(10),
            child: futureWidget(
                RequestMapManager.instance,
                loading: true,
                (data) => Column(children: [
                      Row(children: [
                        Expanded(
                            child: ListTile(
                                title: Text("${localizations.enable} ${localizations.requestMap}"),
                                subtitle: Text(localizations.requestMapDescribe, style: const TextStyle(fontSize: 12)),
                                trailing: SwitchWidget(
                                    value: data.enabled,
                                    scale: 0.8,
                                    onChanged: (value) {
                                      data.enabled = value;
                                      _refreshConfig();
                                    }))),
                      ]),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        const SizedBox(width: 10),
                        TextButton.icon(
                            icon: const Icon(Icons.add, size: 18), onPressed: showEdit, label: Text(localizations.add)),
                        const SizedBox(width: 10),
                        TextButton.icon(
                          icon: const Icon(Icons.input_rounded, size: 18),
                          onPressed: import,
                          label: Text(localizations.import),
                        ),
                        const SizedBox(width: 10),
                      ]),
                      const SizedBox(height: 10),
                      Expanded(child: RequestMapList(list: data.rules)),
                    ]))));
  }

  //导入js
  Future<void> import() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.isEmpty) {
      return;
    }
    var file = result.files.single.xFile;

    try {
      List json = jsonDecode(utf8.decode(await file.readAsBytes()));

      var manager = (await RequestMapManager.instance);
      for (var item in json) {
        var mapRule = RequestMapRule.fromJson(item);
        var requestMapItem = RequestMapItem.fromJson(item['item']);
        await manager.addRule(mapRule, requestMapItem);
      }

      if (mounted) {
        CustomToast.success(localizations.importSuccess).show(context);
      }
      setState(() {});
    } catch (e, t) {
      logger.e('[RequestMap] import fail $file', error: e, stackTrace: t);
      if (mounted) {
        CustomToast.error("${localizations.importFailed} $e").show(context);
      }
    }
  }

  /// 添加脚本
  Future<void> showEdit() async {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const MobileRequestMapEdit())).then((value) {
      if (value != null) {
        setState(() {});
      }
    });
  }
}

/// 脚本列表
class RequestMapList extends StatefulWidget {
  final List<RequestMapRule> list;

  const RequestMapList({super.key, required this.list});

  @override
  State<RequestMapList> createState() => _RequestMapListState();
}

class _RequestMapListState extends State<RequestMapList> {
  Set<int> selected = {};
  bool multiple = false;
  bool changed = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void dispose() {
    if (changed) {
      _refreshConfig(force: true);
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        persistentFooterButtons: [multiple ? globalMenu() : const SizedBox()],
        body: Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.2))),
            child: Scrollbar(
                child: ListView(children: [
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
            ]))));
  }

  List<Widget> rows(List<RequestMapRule> list) {
    var primaryColor = Theme.of(context).colorScheme.primary;
    bool isEN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'en');

    return List.generate(list.length, (index) {
      return InkWell(
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          hoverColor: primaryColor.withOpacity(0.3),
          onLongPress: () => showMenus(index),
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
                  SizedBox(width: 60, child: Text(list[index].name ?? '', style: const TextStyle(fontSize: 13))),
                  SizedBox(
                      width: 35,
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
                  const SizedBox(width: 3),
                  SizedBox(
                      width: 60,
                      child: Text(isEN ? list[index].type.name.camelCaseToSpaced() : list[index].type.label,
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
                ],
              )));
    });
  }

  Stack globalMenu() {
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
                          export(selected.toList());
                          setState(() {
                            selected.clear();
                            multiple = false;
                          });
                        },
                        icon: const Icon(Icons.share, size: 18),
                        label: Text(localizations.export, style: const TextStyle(fontSize: 14))),
                    TextButton.icon(
                        onPressed: () => remove(selected.toList()),
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

  //点击菜单
  void showMenus(int index) {
    setState(() {
      selected.add(index);
    });

    showModalBottomSheet(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        context: context,
        enableDrag: true,
        builder: (ctx) {
          return Wrap(alignment: WrapAlignment.center, children: [
            BottomSheetItem(
                text: localizations.multiple,
                onPressed: () {
                  setState(() => multiple = true);
                }),
            const Divider(thickness: 0.5, height: 5),
            BottomSheetItem(text: localizations.edit, onPressed: () => showEdit(index)),
            const Divider(thickness: 0.5, height: 5),
            BottomSheetItem(text: localizations.export, onPressed: () => export([index])),
            const Divider(thickness: 0.5, height: 5),
            BottomSheetItem(
                text: widget.list[index].enabled ? localizations.disabled : localizations.enable,
                onPressed: () {
                  widget.list[index].enabled = !widget.list[index].enabled;
                  _refreshConfig();
                }),
            const Divider(thickness: 0.5, height: 5),
            BottomSheetItem(
                text: localizations.delete,
                onPressed: () async {
                  var manager = await RequestMapManager.instance;
                  await manager.deleteRule(index);
                  _refreshConfig();
                }),
          ]);
        }).then((value) {
      if (multiple) {
        return;
      }
      setState(() {
        selected.remove(index);
      });
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
            builder: (_) => MobileRequestMapEdit(rule: index == null ? null : widget.list[index], item: item))
        .then((value) {
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

    var manager = await RequestMapManager.instance;
    List<dynamic> json = [];
    for (var idx in indexes) {
      var item = widget.list[idx];
      var map = item.toJson();
      map.remove("itemPath");
      map['item'] = (await manager.getMapItem(item))?.toJson();
      json.add(map);
    }

    RenderBox? box;
    if (await Platforms.isIpad() && mounted) {
      box = context.findRenderObject() as RenderBox?;
    }

    final XFile file = XFile.fromData(utf8.encode(jsonEncode(json)), mimeType: 'config');
    ShareParams shareParams = ShareParams(
      files: [file],
      fileNameOverrides: [fileName],
      sharePositionOrigin: box?.paintBounds,
    );
    await SharePlus.instance.share(shareParams);
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
class MobileRequestMapEdit extends StatefulWidget {
  final RequestMapRule? rule;
  final RequestMapItem? item;
  final String? url;
  final String? title;

  const MobileRequestMapEdit({super.key, this.rule, this.item, this.url, this.title});

  @override
  State<StatefulWidget> createState() {
    return _RequestMapEditState();
  }
}

class _RequestMapEditState extends State<MobileRequestMapEdit> {
  final mapLocalKey = GlobalKey<MobileMapLocaleState>();
  final mapScriptKey = GlobalKey<MobileMapScriptState>();
  final ScrollController scrollController = ScrollController();

  late RequestMapRule rule;

  late RequestMapType mapType;
  late TextEditingController nameInput;
  late TextEditingController urlInput;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    rule = widget.rule ?? RequestMapRule(url: widget.url ?? '', name: widget.title, type: RequestMapType.local);
    mapType = rule.type;
    nameInput = TextEditingController(text: rule.name);
    urlInput = TextEditingController(text: rule.url);
  }

  @override
  void dispose() {
    urlInput.dispose();
    nameInput.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    GlobalKey formKey = GlobalKey<FormState>();
    bool isEN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'en');

    return Scaffold(
        appBar: AppBar(
            title: Row(children: [
              Text(localizations.requestRewriteRule, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            ]),
            actions: [
              TextButton(
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

                    if (mounted) {
                      Navigator.of(this.context).pop(rule);
                    }
                  })
            ]),
        body: Container(
          padding: const EdgeInsets.all(15),
          child: NestedScrollView(
            controller: scrollController,
            headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
              return <Widget>[
                SliverToBoxAdapter(
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
                                              child:
                                                  Text(isEN ? e.name : e.label, style: const TextStyle(fontSize: 13))))
                                          .toList(),
                                      onChanged: onChangeType,
                                    )),
                                const SizedBox(width: 10),
                              ]),
                              const SizedBox(height: 10),
                            ])))
              ];
            },
            body: mapRule(),
          ),
        ));
  }

  void onChangeType(RequestMapType? val) async {
    if (mapType == val) return;
    mapType = val!;
    setState(() {});
  }

  Widget mapRule() {
    if (mapType == RequestMapType.script) {
      return MobileMapScript(key: mapScriptKey, script: widget.item?.script);
    }

    return MobileMapLocal(scrollController: scrollController, key: mapLocalKey, item: widget.item);
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
