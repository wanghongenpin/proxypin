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
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:proxypin/network/components/request_block_manager.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';

class RequestBlock extends StatefulWidget {
  final RequestBlockManager requestBlockManager;

  const RequestBlock({super.key, required this.requestBlockManager});

  @override
  State<RequestBlock> createState() => _RequestBlockState();
}

class _RequestBlockState extends State<RequestBlock> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;
  bool changed = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    if (changed) {
      widget.requestBlockManager.flushConfig();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
        titlePadding: const EdgeInsets.only(left: 20, top: 10, right: 15),
        contentPadding: const EdgeInsets.only(left: 20, right: 20),
        scrollable: true,
        title: Row(children: [
          Text(localizations.requestBlock, style: const TextStyle(fontSize: 16)),
          const Expanded(child: Align(alignment: Alignment.topRight, child: CloseButton()))
        ]),
        content: SizedBox(
            width: 550,
            height: 500,
            child: Column(children: [
              Row(children: [
                const SizedBox(width: 8),
                Text(localizations.enable),
                const SizedBox(width: 10),
                SwitchWidget(
                    scale: 0.8,
                    value: widget.requestBlockManager.enabled,
                    onChanged: (value) {
                      widget.requestBlockManager.enabled = value;
                      changed = true;
                    }),
                const Expanded(child: SizedBox()),
                FilledButton.icon(
                    icon: const Icon(Icons.add, size: 14),
                    onPressed: showEdit,
                    label: Text(localizations.add, style: const TextStyle(fontSize: 12))),
                const SizedBox(width: 5),
              ]),
              const SizedBox(height: 8),
              Container(
                  height: 430,
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.2))),
                  child: Column(children: [
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(width: 15),
                        const Expanded(child: Text('URL', style: TextStyle(fontSize: 14))),
                        SizedBox(width: 80, child: Text(localizations.enable, style: const TextStyle(fontSize: 14))),
                        Container(width: 18),
                        SizedBox(width: 120, child: Text(localizations.action, style: const TextStyle(fontSize: 14))),
                      ],
                    ),
                    const Divider(thickness: 0.5),
                    Expanded(
                        child: ListView.builder(
                            itemCount: widget.requestBlockManager.list.length, itemBuilder: (_, index) => row(index)))
                  ]))
            ])));
  }

  Widget row(int index) {
    var primaryColor = Theme.of(context).colorScheme.primary;
    bool isCN = localizations.localeName == 'zh';
    var list = widget.requestBlockManager.list;

    return InkWell(
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        hoverColor: primaryColor.withOpacity(0.3),
        onSecondaryTapDown: (details) => showMenus(details, index),
        onDoubleTap: () => showEdit(index),
        child: Container(
            color: index.isEven ? Colors.grey.withOpacity(0.1) : null,
            height: 38,
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                const SizedBox(width: 10),
                Expanded(child: Text(list[index].url, style: const TextStyle(fontSize: 14))),
                const SizedBox(width: 20),
                SwitchWidget(
                    scale: 0.65,
                    value: list[index].enabled,
                    onChanged: (val) {
                      list[index].enabled = val;
                      setState(() {
                        changed = true;
                      });
                    }),
                const SizedBox(width: 40),
                SizedBox(
                    width: 130,
                    child: Text(isCN ? list[index].type.label : list[index].type.name,
                        style: const TextStyle(fontSize: 14)))
              ],
            )));
  }

  //点击菜单
  showMenus(TapDownDetails details, int index) {
    var list = widget.requestBlockManager.list;

    showContextMenu(context, details.globalPosition, items: [
      PopupMenuItem(height: 35, child: Text(localizations.edit), onTap: () => showEdit(index)),
      PopupMenuItem(
          height: 35,
          child: list[index].enabled ? Text(localizations.disabled) : Text(localizations.enable),
          onTap: () {
            list[index].enabled = !list[index].enabled;
            changed = true;
            setState(() {});
          }),
      const PopupMenuDivider(),
      PopupMenuItem(
          height: 35,
          child: Text(localizations.delete),
          onTap: () async {
            await widget.requestBlockManager.removeBlockRequest(index);
            setState(() {});
          })
    ]);
  }

  showEdit([int? index]) {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return RequestBlockAddDialog(requestBlockManager: widget.requestBlockManager, index: index);
        }).then((value) {
      if (value != null) {
        setState(() {
          changed = true;
        });
      }
    });
  }
}

class RequestBlockAddDialog extends StatelessWidget {
  final RequestBlockManager requestBlockManager;
  final int? index;

  const RequestBlockAddDialog({super.key, required this.requestBlockManager, this.index});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    bool isCN = localizations.localeName == 'zh';

    GlobalKey formKey = GlobalKey<FormState>();
    RequestBlockItem item =
        index == null ? RequestBlockItem(true, '', BlockType.values.first) : requestBlockManager.list.elementAt(index!);
    bool enabled = item.enabled;
    return AlertDialog(
        scrollable: true,
        content: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Form(
                key: formKey,
                child: Column(children: <Widget>[
                  SwitchWidget(title: localizations.enable, value: item.enabled, onChanged: (val) => enabled = val),
                  const SizedBox(height: 20),
                  TextFormField(
                      initialValue: item.url,
                      decoration: const InputDecoration(
                          labelText: 'URL', hintText: 'https://example.com/*', border: OutlineInputBorder()),
                      validator: (val) => val == null || val.trim().isEmpty ? localizations.cannotBeEmpty : null,
                      onSaved: (val) => item.url = val!.trim()),
                  const SizedBox(height: 20),
                  DropdownButtonFormField(
                      value: item.type,
                      decoration: InputDecoration(labelText: localizations.type, border: const OutlineInputBorder()),
                      items: BlockType.values
                          .map((e) => DropdownMenuItem(
                              value: e, child: Text(isCN ? e.label : e.name, style: const TextStyle(fontSize: 14))))
                          .toList(),
                      onSaved: (val) => item.type = val!,
                      onChanged: (val) {}),
                ]))),
        actions: [
          FilledButton(
              child: Text(localizations.save),
              onPressed: () {
                if (!(formKey.currentState as FormState).validate()) {
                  return;
                }
                (formKey.currentState as FormState).save();

                item.enabled = enabled;
                item.urlReg = null;
                if (index != null) {
                  requestBlockManager.list[index!] = item;
                } else {
                  requestBlockManager.addBlockRequest(item);
                }
                Navigator.of(context).pop(item);
              }),
          ElevatedButton(child: Text(localizations.close), onPressed: () => Navigator.of(context).pop())
        ]);
  }
}
