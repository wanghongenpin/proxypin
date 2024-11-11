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
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/components/manager/hosts_manager.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';

///hosts设置
///@author Hongen Wang
class HostsDialog extends StatefulWidget {
  final HostsManager hostsManager;

  const HostsDialog({super.key, required this.hostsManager});

  @override
  State<HostsDialog> createState() => _HostsDialogState();
}

class _HostsDialogState extends State<HostsDialog> {
  Set<HostsItem> selected = {};
  Set<String> offstage = {};

  bool isPressed = false;
  Offset? lastPressPosition;

  bool saving = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  saveConfig() {
    if (saving) return;
    saving = true;
    Future.delayed(const Duration(milliseconds: 3000), () {
      widget.hostsManager.flushConfig();
      saving = false;
    });
  }

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
            child: AlertDialog(
                titlePadding: const EdgeInsets.only(left: 20, top: 10, right: 15),
                contentPadding: const EdgeInsets.symmetric(horizontal: 15),
                scrollable: true,
                title: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Expanded(child: SizedBox()),
                  Text('Hosts', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                  const Expanded(child: SizedBox()),
                  Align(alignment: Alignment.topRight, child: CloseButton())
                ]),
                content: SizedBox(
                  width: 550,
                  height: 500,
                  child: Column(children: [
                    Row(children: [
                      Container(width: 15),
                      Text(localizations.enable),
                      const SizedBox(width: 10),
                      SwitchWidget(
                          scale: 0.8,
                          value: widget.hostsManager.enabled,
                          onChanged: (value) {
                            widget.hostsManager.enabled = value;
                            saveConfig();
                          }),
                      const Expanded(child: SizedBox()),
                      TextButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          onPressed: showEdit,
                          label: Text(localizations.newBuilt)),
                      const SizedBox(width: 5),
                      TextButton.icon(
                          icon: const Icon(Icons.folder_outlined, size: 18),
                          onPressed: newFolder,
                          label: Text(localizations.newFolder)),
                      const SizedBox(width: 5),
                      TextButton.icon(
                          icon: const Icon(Icons.input_rounded, size: 18),
                          onPressed: import,
                          label: Text(localizations.import)),
                      const SizedBox(width: 5),
                    ]),
                    const SizedBox(height: 8),
                    Container(
                        height: 430,
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.2))),
                        child: Column(children: [
                          const SizedBox(height: 5),
                          Row(children: [
                            Container(width: 15),
                            SizedBox(
                                width: 50, child: Text(localizations.enable, style: const TextStyle(fontSize: 14))),
                            Container(width: 15),
                            Expanded(child: Text(localizations.domain, style: TextStyle(fontSize: 14))),
                            Container(width: 15),
                            Expanded(child: Text(localizations.toAddress, style: const TextStyle(fontSize: 14))),
                          ]),
                          const Divider(thickness: 0.5),
                          Expanded(
                              child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: widget.hostsManager.list.length,
                                  padding: const EdgeInsets.only(right: 10),
                                  itemBuilder: (_, index) => row(widget.hostsManager.list[index], index.isEven)))
                        ])),
                  ]),
                ))));
  }

  Widget row(HostsItem item, bool isEven, {EdgeInsetsGeometry? padding}) {
    var primaryColor = Theme.of(context).colorScheme.primary;

    return Column(children: [
      InkWell(
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          hoverColor: primaryColor.withOpacity(0.3),
          onSecondaryTapDown: (details) => showMenus(details, item),
          onDoubleTap: item.isFolder ? null : () => showEdit(item: item),
          onTap: () {
            if (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) {
              setState(() {
                selected.contains(item) ? selected.remove(item) : selected.add(item);
              });
              return;
            }

            if (!isPressed && selected.isNotEmpty) {
              setState(() {
                selected.clear();
              });
              return;
            }

            if (item.isFolder) {
              setState(() {
                offstage.contains(item.id) ? offstage.remove(item.id) : offstage.add(item.id);
              });
            }
          },
          onHover: (hover) {
            if (isPressed && !selected.contains(item)) {
              setState(() {
                selected.add(item);
              });
            }
          },
          child: Container(
              color: selected.contains(item)
                  ? primaryColor.withOpacity(0.6)
                  : isEven
                      ? Colors.grey.withOpacity(0.1)
                      : null,
              height: 35,
              padding: padding ?? const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SwitchWidget(
                      scale: 0.6,
                      value: item.enabled,
                      onChanged: (val) {
                        setState(() {
                          item.enabled = val;
                          saveConfig();
                        });
                      }),
                  Container(width: 15),
                  Expanded(
                      child: IconText(
                          icon: item.isFolder
                              ? Icon(offstage.contains(item.id) ? Icons.folder : Icons.folder_outlined, size: 18)
                              : null,
                          text: item.host,
                          textStyle: const TextStyle(fontSize: 14))),
                  Container(width: 15),
                  Expanded(child: Text(item.toAddress ?? '', style: const TextStyle(fontSize: 14)))
                ],
              ))),
      if (item.isFolder)
        Offstage(
            offstage: offstage.contains(item.id),
            child: Column(
                children: widget.hostsManager
                    .getFolderList(item.id)
                    .map((e) => row(e, !isEven, padding: EdgeInsets.only(left: 60)))
                    .toList()))
    ]);
  }

  newFolder() {
    showEdit(isFolder: true);
  }

  enableStatus(bool enable) {
    if (selected.isEmpty) return;

    for (var item in selected) {
      if (item.enabled == enable) continue;
      item.enabled = enable;
    }
    setState(() {
      saveConfig();
    });
  }

  showGlobalMenu(Offset offset) {
    showContextMenu(context, offset, items: [
      PopupMenuItem(height: 35, child: Text(localizations.newBuilt), onTap: () => showEdit()),
      PopupMenuItem(
          height: 35, enabled: selected.isNotEmpty, child: Text(localizations.export), onTap: () => export(selected)),
      const PopupMenuDivider(),
      PopupMenuItem(height: 35, child: Text(localizations.enableSelect), onTap: () => enableStatus(true)),
      PopupMenuItem(height: 35, child: Text(localizations.disableSelect), onTap: () => enableStatus(false)),
      const PopupMenuDivider(),
      PopupMenuItem(
          height: 35,
          enabled: selected.isNotEmpty,
          child: Text(localizations.deleteSelect),
          onTap: () => removeHosts(selected)),
    ]);
  }

  //点击菜单
  showMenus(TapDownDetails details, HostsItem item) {
    if (selected.length > 1) {
      showGlobalMenu(details.globalPosition);
      return;
    }

    setState(() {
      selected.add(item);
    });

    showContextMenu(context, details.globalPosition, items: [
      if (item.isFolder)
        PopupMenuItem(height: 35, child: Text(localizations.newBuilt), onTap: () => showEdit(parent: item)),
      PopupMenuItem(height: 35, child: Text(localizations.edit), onTap: () => showEdit(item: item)),
      PopupMenuItem(height: 35, onTap: () => export([item]), child: Text(localizations.export)),
      PopupMenuItem(
          height: 35,
          child: item.enabled ? Text(localizations.disabled) : Text(localizations.enable),
          onTap: () {
            setState(() {
              item.enabled = !item.enabled;
              saveConfig();
            });
          }),
      const PopupMenuDivider(),
      PopupMenuItem(
          height: 35,
          child: Text(localizations.delete),
          onTap: () async {
            setState(() {
              widget.hostsManager.removeHosts([item]);
            });
          })
    ]).then((value) {
      setState(() {
        selected.remove(item);
      });
    });
  }

  showEdit({HostsItem? item, HostsItem? parent, bool? isFolder}) {
    isFolder ??= item?.isFolder == true;
    showDialog(
        context: context,
        builder: (BuildContext context) => isFolder == true
            ? FolderDialog(hostsManager: widget.hostsManager, folder: item)
            : HostsEditDialog(item: item, parent: parent)).then((value) {
      if (value != null) {
        setState(() {
          saveConfig();
        });
      }
    });
  }

  //删除
  Future<void> removeHosts(Set<HostsItem> items) async {
    if (items.isEmpty) return;
    return showConfirmDialog(context, onConfirm: () async {
      await widget.hostsManager.removeHosts(items);
      setState(() {
        items.clear();
      });
      if (mounted) FlutterToastr.show(localizations.deleteSuccess, context);
    });
  }

  //导入
  import() async {
    final FilePickerResult? result =
        await FilePicker.platform.pickFiles(allowedExtensions: ['json'], type: FileType.custom);
    var file = result?.files.single;
    if (file == null) {
      return;
    }

    try {
      List json = jsonDecode(await file.xFile.readAsString());
      Map<String, String> idMap = {};

      for (var item in json) {
        //生成新的id 保存映射关系
        String newId = HostsItem.generateId();
        idMap[item['id']] = newId;
        item['id'] = newId;
        var hostsItem = HostsItem.fromJson(item);

        if (hostsItem.parent != null) {
          hostsItem.parent = idMap[hostsItem.parent!];
        }

        widget.hostsManager.addHosts(hostsItem);
      }

      saveConfig();
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

  //导出
  export(Iterable<HostsItem> items) async {
    if (items.isEmpty) return;

    String fileName = 'hosts.json';
    var path = await FilePicker.platform.saveFile(fileName: fileName);
    if (path == null) {
      return;
    }

    var list = [];
    for (var item in items) {
      var json = item.toJson();
      list.add(json);
    }

    await File(path).writeAsBytes(utf8.encode(jsonEncode(list)));
    if (mounted) FlutterToastr.show(localizations.exportSuccess, context);
  }
}

class FolderDialog extends StatelessWidget {
  final HostsManager hostsManager;
  final HostsItem? folder;

  const FolderDialog({super.key, required this.hostsManager, this.folder});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    bool enabled = folder?.enabled ?? true;
    String name = folder?.host ?? '';

    return AlertDialog(
      title: Text(localizations.newFolder, style: const TextStyle(fontSize: 16)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          SizedBox(width: 55, child: Text(localizations.enable)),
          SwitchWidget(scale: 0.8, value: enabled, onChanged: (value) => enabled = value)
        ]),
        SizedBox(height: 10),
        Row(children: [
          SizedBox(width: 55, child: Text(localizations.name)),
          Expanded(
              child: TextFormField(
                  initialValue: name,
                  onChanged: (val) => name = val,
                  decoration: InputDecoration(border: OutlineInputBorder())))
        ])
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(localizations.cancel)),
        TextButton(
            onPressed: () {
              HostsItem item;
              if (folder == null) {
                item = HostsItem(isFolder: true, host: name, enabled: enabled);
                hostsManager.addHosts(item);
              } else {
                folder!.enabled = enabled;
                folder!.host = name;
                item = folder!;
              }
              Navigator.pop(context, item);
            },
            child: Text(localizations.save)),
      ],
    );
  }
}

class HostsEditDialog extends StatefulWidget {
  final HostsItem? item;
  final HostsItem? parent;

  const HostsEditDialog({super.key, this.item, this.parent});

  @override
  State<HostsEditDialog> createState() => _HostsEditDialogState();
}

class _HostsEditDialogState extends State<HostsEditDialog> {
  GlobalKey formKey = GlobalKey<FormState>();

  bool enabled = true;
  TextEditingController hostController = TextEditingController();
  TextEditingController toAddressController = TextEditingController();

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    if (widget.item != null) {
      enabled = widget.item!.enabled;
      hostController.text = widget.item!.host;
      toAddressController.text = widget.item!.toAddress ?? '';
    }
  }

  @override
  void dispose() {
    hostController.dispose();
    toAddressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
        contentPadding: const EdgeInsets.only(left: 20, right: 20, top: 10),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(localizations.cancel)),
          TextButton(
              onPressed: () {
                if (!(formKey.currentState as FormState).validate()) {
                  FlutterToastr.show(
                      "${localizations.domain} ${localizations.toAddress} ${localizations.cannotBeEmpty}", context,
                      position: FlutterToastr.center);
                  return;
                }

                HostsItem? hostItem;
                if (widget.item == null) {
                  hostItem = HostsItem(
                      enabled: enabled,
                      parent: widget.parent?.id,
                      host: hostController.text,
                      toAddress: toAddressController.text);
                  HostsManager.instance.then((it) => it.addHosts(hostItem!));
                } else {
                  widget.item!.enabled = enabled;
                  widget.item!.host = hostController.text;
                  widget.item!.toAddress = toAddressController.text;
                  hostItem = widget.item;
                }

                Navigator.pop(context, hostItem);
              },
              child: Text(localizations.save)),
        ],
        content: SizedBox(
          width: 300,
          height: 180,
          child: Form(
              key: formKey,
              child: Column(children: [
                Row(children: [
                  SizedBox(width: 80, child: Text(localizations.enable)),
                  Expanded(child: SwitchWidget(scale: 0.8, value: enabled, onChanged: (value) => enabled = value)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  SizedBox(width: 80, child: Text(localizations.domain)),
                  Expanded(
                      child: TextFormField(
                          controller: hostController,
                          validator: (val) => val == null || val.trim().isEmpty ? localizations.cannotBeEmpty : null,
                          decoration: const InputDecoration(
                              hintText: '*.example.com',
                              hintStyle: TextStyle(color: Colors.grey),
                              errorStyle: TextStyle(height: 0, fontSize: 0),
                              border: OutlineInputBorder()))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  SizedBox(width: 80, child: Text(localizations.toAddress)),
                  Expanded(
                      child: TextFormField(
                          controller: toAddressController,
                          validator: (val) => val == null || val.trim().isEmpty ? localizations.cannotBeEmpty : null,
                          decoration: const InputDecoration(
                              hintText: '202.108.22.5',
                              errorStyle: TextStyle(height: 0, fontSize: 0),
                              hintStyle: TextStyle(color: Colors.grey),
                              border: OutlineInputBorder()))),
                ]),
              ])),
        ));
  }
}
