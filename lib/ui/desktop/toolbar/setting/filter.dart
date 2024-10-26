/*
 * Copyright 2023 Hongen Wang
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
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';

/// @author wanghongen
/// 2023/10/8
class FilterDialog extends StatefulWidget {
  final Configuration configuration;

  const FilterDialog({super.key, required this.configuration});

  @override
  State<FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<FilterDialog> {
  final ValueNotifier<bool> hostEnableNotifier = ValueNotifier(false);

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void dispose() {
    hostEnableNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        titlePadding: const EdgeInsets.only(left: 20, top: 10, right: 15),
        contentPadding: const EdgeInsets.only(left: 20, right: 20),
        scrollable: true,
        title: Row(children: [
          Text(localizations.domainFilter, style: const TextStyle(fontSize: 18)),
          const Expanded(child: Align(alignment: Alignment.topRight, child: CloseButton()))
        ]),
        content: SizedBox(
          width: 680,
          height: 510,
          child: Flex(
            direction: Axis.horizontal,
            children: [
              Expanded(
                  flex: 1,
                  child: DomainFilter(
                      title: localizations.domainWhitelist,
                      subtitle: localizations.domainWhitelistDescribe,
                      hostList: HostFilter.whitelist,
                      configuration: widget.configuration,
                      hostEnableNotifier: hostEnableNotifier)),
              const SizedBox(width: 10),
              Expanded(
                  flex: 1,
                  child: DomainFilter(
                      title: localizations.domainBlacklist,
                      subtitle: localizations.domainBlacklistDescribe,
                      hostList: HostFilter.blacklist,
                      configuration: widget.configuration,
                      hostEnableNotifier: hostEnableNotifier)),
            ],
          ),
        ));
  }
}

class DomainFilter extends StatefulWidget {
  final String title;
  final String subtitle;
  final HostList hostList;
  final Configuration configuration;
  final ValueNotifier<bool> hostEnableNotifier;

  const DomainFilter(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.hostList,
      required this.hostEnableNotifier,
      required this.configuration});

  @override
  State<StatefulWidget> createState() {
    return _DomainFilterState();
  }
}

class _DomainFilterState extends State<DomainFilter> {
  bool changed = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void dispose() {
    if (changed) {
      widget.configuration.flushConfig();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          title: Text(widget.title),
          isThreeLine: true,
          subtitle: Text(widget.subtitle, style: const TextStyle(fontSize: 12)),
          titleAlignment: ListTileTitleAlignment.center,
        ),
        Row(children: [
          const SizedBox(width: 8),
          Text(localizations.enable),
          const SizedBox(width: 10),
          SwitchWidget(
              scale: 0.8,
              value: widget.hostList.enabled,
              onChanged: (value) {
                widget.hostList.enabled = value;
                changed = true;
              }),
          const Expanded(child: SizedBox()),
          FilledButton.icon(
              icon: const Icon(Icons.add, size: 14),
              onPressed: add,
              label: Text(localizations.add, style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 10),
          FilledButton.icon(
              icon: const Icon(Icons.input_rounded, size: 14),
              onPressed: import,
              label: Text(localizations.import, style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 5),
        ]),
        DomainList(widget.hostList, onChange: () => changed = true)
      ],
    );
  }

  //导入
  import() async {
    final FilePickerResult? result =
        await FilePicker.platform.pickFiles(allowedExtensions: ['config'], type: FileType.custom);
    var file = result?.files.single;
    if (file == null) {
      return;
    }

    try {
      List json = jsonDecode(await file.xFile.readAsString());
      for (var item in json) {
        widget.hostList.add(item);
      }

      changed = true;
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

  void add() {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => DomainAddDialog(hostList: widget.hostList)).then((value) {
      if (value != null) {
        setState(() {
          changed = true;
        });
      }
    });
  }
}

class DomainAddDialog extends StatelessWidget {
  final HostList hostList;
  final int? index;

  const DomainAddDialog({super.key, required this.hostList, this.index});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    GlobalKey formKey = GlobalKey<FormState>();
    String? host = index == null ? null : hostList.list.elementAt(index!).pattern.replaceAll(".*", "*");
    return AlertDialog(
        scrollable: true,
        content: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Form(
                key: formKey,
                child: Column(children: <Widget>[
                  TextFormField(
                      initialValue: host,
                      decoration: const InputDecoration(labelText: 'Host', hintText: '*.example.com'),
                      validator: (val) => val == null || val.trim().isEmpty ? localizations.cannotBeEmpty : null,
                      onChanged: (val) => host = val)
                ]))),
        actions: [
          TextButton(
              child: Text(localizations.add),
              onPressed: () {
                if (!(formKey.currentState as FormState).validate()) {
                  return;
                }
                try {
                  if (index != null) {
                    hostList.list[index!] = RegExp(host!.trim().replaceAll("*", ".*"));
                  } else {
                    hostList.add(host!.trim());
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                }
                Navigator.of(context).pop(host);
              }),
          TextButton(child: Text(localizations.close), onPressed: () => Navigator.of(context).pop())
        ]);
  }
}

///域名列表
class DomainList extends StatefulWidget {
  final HostList hostList;
  final Function onChange;

  const DomainList(this.hostList, {super.key, required this.onChange});

  @override
  State<StatefulWidget> createState() => _DomainListState();
}

class _DomainListState extends State<DomainList> {
  Map<int, bool> selected = {};

  AppLocalizations get localizations => AppLocalizations.of(context)!;
  bool isPress = false;
  bool changed = false;

  onChanged() {
    changed = true;
    widget.onChange.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onSecondaryTapDown: (details) => showGlobalMenu(details.globalPosition),
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
            onPointerUp: (details) => isPress = false,
            onPointerDown: (details) => isPress = true,
            child: Container(
                padding: const EdgeInsets.only(top: 10),
                height: 380,
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.2))),
                child: SingleChildScrollView(
                    child: Column(children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Container(width: 15),
                      const Expanded(child: Text('Host')),
                    ],
                  ),
                  const Divider(thickness: 0.5),
                  Column(children: rows(widget.hostList.list))
                ])))));
  }

  List<Widget> rows(List<RegExp> list) {
    var primaryColor = Theme.of(context).colorScheme.primary;

    return List.generate(list.length, (index) {
      return InkWell(
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          hoverColor: primaryColor.withOpacity(0.3),
          onSecondaryTapDown: (details) => showMenus(details, index),
          //right click menus
          onDoubleTap: () => showEdit(index),
          onHover: (hover) {
            if (isPress && selected[index] != true) {
              setState(() {
                selected[index] = true;
              });
            }
          },
          onTap: () {
            if (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) {
              setState(() {
                selected[index] = !(selected[index] ?? false);
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
              color: selected[index] == true
                  ? primaryColor.withOpacity(0.8)
                  : index.isEven
                      ? Colors.grey.withOpacity(0.1)
                      : null,
              height: 38,
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  const SizedBox(width: 15),
                  Expanded(
                      child: Text(list[index].pattern.replaceAll(".*", "*"), style: const TextStyle(fontSize: 14))),
                ],
              )));
    });
  }

  //导出
  export(List<int> indexes) async {
    if (indexes.isEmpty) return;

    String fileName = 'host-filters.config';
    String? saveLocation = (await FilePicker.platform.saveFile(fileName: fileName));
    if (saveLocation == null) {
      return;
    }

    var list = [];
    for (var index in indexes) {
      String rule = widget.hostList.list[index].pattern.replaceAll(".*", "*");
      list.add(rule);
    }

    await File(saveLocation).writeAsBytes(utf8.encode(jsonEncode(list)));

    if (mounted) {
      FlutterToastr.show(localizations.exportSuccess, context);
    }
  }

  //删除
  Future<void> remove(List<int> indexes) async {
    if (indexes.isEmpty) return;
    return showConfirmDialog(context, content: localizations.requestRewriteDeleteConfirm(indexes.length),
        onConfirm: () async {
      widget.hostList.removeIndex(indexes);
      onChanged();
      setState(() {
        selected.clear();
      });
      if (mounted) FlutterToastr.show(localizations.deleteSuccess, context);
    });
  }

  showEdit([int? index]) {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return DomainAddDialog(hostList: widget.hostList, index: index);
        }).then((value) {
      if (value != null) {
        setState(() {
          onChanged();
        });
      }
    });
  }

  showGlobalMenu(Offset offset) {
    showContextMenu(context, offset, items: [
      PopupMenuItem(height: 35, child: Text(localizations.newBuilt), onTap: () => showEdit()),
      PopupMenuItem(
          height: 35,
          enabled: selected.isNotEmpty,
          child: Text(localizations.export),
          onTap: () => export(selected.keys.toList())),
      const PopupMenuDivider(),
      PopupMenuItem(
          height: 35,
          enabled: selected.isNotEmpty,
          child: Text(localizations.deleteSelect),
          onTap: () => remove(selected.keys.toList())),
    ]);
  }

  //点击菜单
  showMenus(TapDownDetails details, int index) {
    if (selected.length > 1) {
      showGlobalMenu(details.globalPosition);
      return;
    }

    setState(() {
      selected[index] = true;
    });

    showContextMenu(context, details.globalPosition, items: [
      PopupMenuItem(
          height: 35,
          child: Text(localizations.copy),
          onTap: () {
            Clipboard.setData(ClipboardData(text: widget.hostList.list[index].pattern.replaceAll(".*", "*")));
            FlutterToastr.show(localizations.copied, context);
          }),
      PopupMenuItem(height: 35, child: Text(localizations.edit), onTap: () => showEdit(index)),
      PopupMenuItem(height: 35, onTap: () => export([index]), child: Text(localizations.export)),
      const PopupMenuDivider(),
      PopupMenuItem(
          height: 35,
          child: Text(localizations.delete),
          onTap: () {
            widget.hostList.removeIndex([index]);
            onChanged();
          })
    ]).then((value) {
      setState(() {
        selected.remove(index);
      });
    });
  }
}
