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
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:share_plus/share_plus.dart';

import '../../../network/components/host_filter.dart';

class MobileFilterWidget extends StatefulWidget {
  final Configuration configuration;
  final HostList hostList;

  const MobileFilterWidget({super.key, required this.configuration, required this.hostList});

  @override
  State<MobileFilterWidget> createState() => _MobileFilterState();
}

class _MobileFilterState extends State<MobileFilterWidget> {
  final ValueNotifier<bool> hostEnableNotifier = ValueNotifier(false);

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void dispose() {
    hostEnableNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var title = widget.hostList.runtimeType == Whites ? localizations.domainWhitelist : localizations.domainBlacklist;
    var subtitle =
        widget.hostList.runtimeType == Whites ? localizations.domainWhitelistDescribe : localizations.domainBlacklist;

    return Scaffold(
        appBar: AppBar(title: Text(localizations.domainFilter, style: const TextStyle(fontSize: 16))),
        body: Container(
          padding: const EdgeInsets.all(10),
          child: DomainFilter(
              title: title,
              subtitle: subtitle,
              hostList: widget.hostList,
              configuration: widget.configuration,
              hostEnableNotifier: hostEnableNotifier),
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
        ListTile(title: Text(widget.title), subtitle: Text(widget.subtitle, style: const TextStyle(fontSize: 12))),
        ValueListenableBuilder(
            valueListenable: widget.hostEnableNotifier,
            builder: (_, bool enable, __) {
              return SwitchListTile(
                  title: Text(localizations.enable),
                  value: widget.hostList.enabled,
                  onChanged: (value) {
                    widget.hostList.enabled = value;
                    changed = true;
                    widget.hostEnableNotifier.value = !widget.hostEnableNotifier.value;
                  });
            }),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          FilledButton.icon(icon: const Icon(Icons.add), onPressed: add, label: Text(localizations.add)),
          const SizedBox(width: 10),
          FilledButton.icon(
              icon: const Icon(Icons.input_rounded), onPressed: import, label: Text(localizations.import)),
          const SizedBox(width: 5),
        ]),
        Expanded(child: DomainList(widget.hostList, onChange: () => changed = true))
      ],
    );
  }

  //导入
  import() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['config', 'json']);
    if (result == null || result.files.isEmpty) {
      return;
    }
    var file = File(result.files.single.path!);
    try {
      List json = jsonDecode(await file.readAsString());
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
    showDialog(context: context, builder: (BuildContext context) => DomainAddDialog(hostList: widget.hostList))
        .then((value) {
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
          FilledButton(
              child: Text(localizations.save),
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
          ElevatedButton(child: Text(localizations.close), onPressed: () => Navigator.of(context).pop())
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
  Set<int> selected = HashSet<int>();

  AppLocalizations get localizations => AppLocalizations.of(context)!;
  bool changed = false;
  bool multiple = false;

  onChanged() {
    changed = true;
    widget.onChange.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        persistentFooterButtons: [multiple ? globalMenu() : const SizedBox()],
        body: Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
            ),
            child: Scrollbar(
                child: ListView(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Container(width: 15),
                  const Expanded(child: Text('Host')),
                ],
              ),
              const Divider(thickness: 0.5),
              Column(children: rows(widget.hostList.list))
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
                          export(selected.toList());
                          setState(() {
                            selected.clear();
                            multiple = false;
                          });
                        },
                        icon: const Icon(Icons.share, size: 18),
                        label: Text(localizations.export, style: const TextStyle(fontSize: 14))),
                    TextButton.icon(
                        onPressed: () => remove(),
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

  List<Widget> rows(List<RegExp> list) {
    var primaryColor = Theme.of(context).colorScheme.primary;

    return List.generate(list.length, (index) {
      return InkWell(
          enableFeedback: false,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          hoverColor: primaryColor.withOpacity(0.3),
          onLongPress: () => showMenus(index),
          // menus
          onDoubleTap: () => showEdit(index),
          onTap: () {
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

  //点击菜单
  showMenus(int index) {
    setState(() {
      selected.add(index);
    });
    HapticFeedback.mediumImpact();

    showCupertinoModalPopup(
        context: context,
        builder: (BuildContext context) {
          return CupertinoActionSheet(
              actions: [
                CupertinoActionSheetAction(
                    child: Text(localizations.multiple),
                    onPressed: () {
                      setState(() => multiple = true);
                      Navigator.of(context).pop();
                    }),
                CupertinoActionSheetAction(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.hostList.list[index].pattern.replaceAll(".*", "*")));
                      FlutterToastr.show(localizations.copied, context);
                      Navigator.of(context).pop();
                    },
                    child: Text(localizations.copy)),
                CupertinoActionSheetAction(
                    onPressed: () {
                      Navigator.of(context).pop();
                      showEdit(index);
                    },
                    child: Text(localizations.edit)),
                CupertinoActionSheetAction(
                    onPressed: () {
                      export([index]);
                      Navigator.of(context).pop();
                    },
                    child: Text(localizations.share)),
                CupertinoActionSheetAction(
                    onPressed: () {
                      widget.hostList.removeIndex([index]);
                      onChanged();
                      Navigator.of(context).pop();
                    },
                    child: Text(localizations.delete)),
              ],
              cancelButton: CupertinoActionSheetAction(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(localizations.cancel)));
        }).then((value) {
      if (multiple) {
        return;
      }
      setState(() {
        selected.remove(index);
      });
    });
  }

  //导出
  export(List<int> indexes) async {
    if (indexes.isEmpty) return;

    String fileName = 'host-filters.config';
    var list = [];
    for (var index in indexes) {
      String rule = widget.hostList.list[index].pattern;
      list.add(rule);
    }

    final XFile file = XFile.fromData(utf8.encode(jsonEncode(list)), mimeType: 'config');
    await Share.shareXFiles([file], fileNameOverrides: [fileName]);
  }

  //删除
  Future<void> remove() async {
    if (selected.isEmpty) return;

    return showConfirmDialog(context, content: localizations.requestRewriteDeleteConfirm(selected.length),
        onConfirm: () async {
      widget.hostList.removeIndex(selected.toList());
      onChanged();
      setState(() {
        multiple = false;
        selected.clear();
      });
      if (mounted) FlutterToastr.show(localizations.deleteSuccess, context);
    });
  }
}
