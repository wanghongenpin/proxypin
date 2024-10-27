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

import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/components/rewrite/rewrite_rule.dart';
import 'package:proxypin/network/http/http.dart';

import 'package:proxypin/ui/component/text_field.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:proxypin/utils/lang.dart';

/// @author wanghongen
/// 2023/10/8
class DesktopRewriteUpdate extends StatefulWidget {
  final RuleType ruleType;
  final List<RewriteItem>? items;
  final HttpRequest? request;

  const DesktopRewriteUpdate({super.key, required this.ruleType, this.items, this.request});

  @override
  State<DesktopRewriteUpdate> createState() => RewriteUpdateState();
}

class RewriteUpdateState extends State<DesktopRewriteUpdate> {
  late RuleType ruleType;
  List<RewriteItem> items = [];

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();

    initItems(widget.ruleType, widget.items);
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   add();
    // });
  }

  ///初始化重写项
  initItems(RuleType ruleType, List<RewriteItem>? items) {
    this.ruleType = ruleType;
    this.items.clear();

    if (items != null) {
      this.items.addAll(items);
    }
  }

  List<RewriteItem> getItems() {
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(localizations.requestRewriteRule, style: const TextStyle(fontSize: 13, color: Colors.grey)),
            Expanded(
                child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [IconButton(onPressed: add, icon: const Icon(Icons.add)), const SizedBox(width: 10)],
            ))
          ],
        ),
        UpdateList(items: items, ruleType: ruleType, request: widget.request),
      ],
    );
  }

  add() {
    showDialog(
        context: context,
        builder: (context) => RewriteUpdateAddDialog(ruleType: ruleType, request: widget.request)).then((value) {
      if (value != null) {
        setState(() {
          items.add(value);
        });
      }
    });
  }
}

class RewriteUpdateAddDialog extends StatefulWidget {
  final RewriteItem? item;
  final RuleType ruleType;
  final HttpRequest? request;

  const RewriteUpdateAddDialog({super.key, this.item, required this.ruleType, this.request});

  @override
  State<RewriteUpdateAddDialog> createState() => _RewriteUpdateAddState();
}

class _RewriteUpdateAddState extends State<RewriteUpdateAddDialog> {
  late RewriteType rewriteType;
  GlobalKey formKey = GlobalKey<FormState>();
  late RewriteItem rewriteItem;

  AppLocalizations get localizations => AppLocalizations.of(context)!;
  var keyController = TextEditingController();
  var valueController = TextEditingController();
  var dataController = HighlightTextEditingController();

  @override
  void initState() {
    super.initState();
    rewriteType = widget.item?.type ?? RewriteType.updateBody;
    rewriteItem = widget.item ?? RewriteItem(rewriteType, true);
    keyController.text = rewriteItem.key ?? '';
    valueController.text = rewriteItem.value ?? '';

    initTestData();
    keyController.addListener(onInputChangeMatch);
    dataController.addListener(onInputChangeMatch);
  }

  @override
  void dispose() {
    keyController.dispose();
    valueController.dispose();
    dataController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isDelete = rewriteType == RewriteType.removeQueryParam || rewriteType == RewriteType.removeHeader;
    bool isUpdate =
        [RewriteType.updateBody, RewriteType.updateHeader, RewriteType.updateQueryParam].contains(rewriteType);

    String keyTips = "";
    String valueTips = "";
    if (isDelete) {
      keyTips = localizations.matchRule;
      valueTips = localizations.emptyMatchAll;
    } else if (rewriteType == RewriteType.updateQueryParam || rewriteType == RewriteType.updateHeader) {
      keyTips = rewriteType == RewriteType.updateQueryParam ? "name=123" : "Content-Type: application/json";
      valueTips = rewriteType == RewriteType.updateQueryParam ? "name=456" : "Content-Type: application/xml";
    }

    var typeList = widget.ruleType == RuleType.requestUpdate ? RewriteType.updateRequest : RewriteType.updateResponse;

    return AlertDialog(
        scrollable: true,
        titlePadding: const EdgeInsets.only(top: 10, left: 20),
        actionsPadding: const EdgeInsets.only(right: 15, bottom: 15),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        title: Text(localizations.add,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(localizations.cancel)),
          TextButton(
              onPressed: () {
                if (!(formKey.currentState as FormState).validate()) {
                  FlutterToastr.show(localizations.cannotBeEmpty, context, position: FlutterToastr.center);
                  return;
                }
                rewriteItem.key = keyController.text;
                rewriteItem.value = valueController.text;
                rewriteItem.type = rewriteType;
                Navigator.of(context).pop(rewriteItem);
              },
              child: Text(localizations.confirm)),
        ],
        content: Container(
            width: 500,
            constraints: const BoxConstraints(maxHeight: 420, minHeight: 400),
            child: Form(
                key: formKey,
                child: Column(children: [
                  Row(
                    children: [
                      Text(localizations.type),
                      const SizedBox(width: 20),
                      SizedBox(
                          width: 140,
                          child: DropdownButtonFormField<RewriteType>(
                              value: rewriteType,
                              focusColor: Colors.transparent,
                              itemHeight: 48,
                              decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.all(10), isDense: true, border: InputBorder.none),
                              items: typeList
                                  .map((e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(e.getDescribe(localizations.localeName == 'zh'),
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))))
                                  .toList(),
                              onChanged: (val) {
                                setState(() {
                                  rewriteType = val!;
                                });
                                initTestData();
                              })),
                    ],
                  ),
                  const SizedBox(height: 15),
                  textField(isUpdate ? localizations.match : localizations.name, keyTips,
                      controller: keyController, required: !isDelete),
                  const SizedBox(height: 15),
                  textField(isUpdate ? localizations.replace : localizations.value, valueTips,
                      controller: valueController),
                  const SizedBox(height: 10),
                  Row(children: [
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Text(localizations.testData, style: const TextStyle(fontSize: 14))),
                    const SizedBox(width: 10),
                    if (!isMatch)
                      Text(localizations.noChangesDetected, style: TextStyle(color: Colors.red, fontSize: 14))
                  ]),
                  const SizedBox(height: 5),
                  formField(localizations.enterMatchData, lines: 10, required: false, controller: dataController),
                ]))));
  }

  initTestData() {
    dataController.splitPattern = null;
    dataController.highlightEnabled = rewriteType != RewriteType.addQueryParam && rewriteType != RewriteType.addHeader;
    bool isRemove = [RewriteType.removeHeader, RewriteType.removeQueryParam].contains(rewriteType);

    valueController.removeListener(onInputChangeMatch);
    if (isRemove) {
      valueController.addListener(onInputChangeMatch);
    }

    if (widget.request == null) return;

    if (rewriteType == RewriteType.updateBody) {
      dataController.text = (widget.ruleType == RuleType.requestUpdate
              ? widget.request?.bodyAsString
              : widget.request?.response?.bodyAsString) ??
          '';
      return;
    }

    if (rewriteType == RewriteType.updateQueryParam || rewriteType == RewriteType.removeQueryParam) {
      dataController.splitPattern = '&';
      dataController.text = Uri.decodeQueryComponent(widget.request?.requestUri?.query ?? '');
      return;
    }

    if (rewriteType == RewriteType.updateHeader || rewriteType == RewriteType.removeHeader) {
      var headerData = widget.ruleType == RuleType.requestUpdate
          ? widget.request?.headers.toRawHeaders()
          : widget.request?.response?.headers.toRawHeaders();
      dataController.text = headerData ?? '';
      return;
    }

    dataController.clear();
  }

  bool onMatch = false; //是否正在匹配
  bool isMatch = true;

  onInputChangeMatch() {
    if (onMatch || dataController.highlightEnabled == false) {
      return;
    }
    onMatch = true;

    //高亮显示
    Future.delayed(const Duration(milliseconds: 600), () {
      onMatch = false;
      if (dataController.text.isEmpty) {
        if (isMatch) return;
        setState(() {
          isMatch = true;
        });
        return;
      }

      setState(() {
        bool isRemove = [RewriteType.removeHeader, RewriteType.removeQueryParam].contains(rewriteType);
        String key = keyController.text;
        if (isRemove && key.isNotEmpty) {
          if (rewriteType == RewriteType.removeHeader) {
            key = '$key: ';
          } else {
            key = '$key=';
          }
          key = '$key${valueController.text}';
        }

        var match = dataController.highlight(key,
            caseSensitive: rewriteType != RewriteType.updateHeader && rewriteType != RewriteType.removeHeader);
        isMatch = match;
      });
    });
  }

  Widget textField(String label, String hint, {bool required = false, int? lines, TextEditingController? controller}) {
    return Row(children: [
      SizedBox(width: 60, child: Text(label)),
      Expanded(child: formField(hint, required: required, lines: lines, controller: controller))
    ]);
  }

  Widget formField(String hint, {bool required = false, int? lines, TextEditingController? controller}) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(fontSize: 14),
      minLines: lines ?? 1,
      maxLines: lines ?? 2,
      validator: (val) => val?.isNotEmpty == true || !required ? null : "",
      decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          contentPadding: const EdgeInsets.all(10),
          errorStyle: const TextStyle(height: 0, fontSize: 0),
          focusedBorder: focusedBorder(),
          isDense: true,
          border: const OutlineInputBorder()),
    );
  }

  InputBorder focusedBorder() {
    return OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2));
  }
}

class UpdateList extends StatefulWidget {
  final List<RewriteItem> items;
  final RuleType ruleType;
  final HttpRequest? request;

  const UpdateList({super.key, required this.items, required this.ruleType, this.request});

  @override
  State<UpdateList> createState() => _UpdateListState();
}

class _UpdateListState extends State<UpdateList> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.only(top: 10),
        constraints: const BoxConstraints(minHeight: 330),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.2))),
        child: SingleChildScrollView(
            child: Column(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(width: 130, padding: const EdgeInsets.only(left: 10), child: Text(localizations.type)),
              SizedBox(width: 50, child: Text(localizations.enable, textAlign: TextAlign.center)),
              const VerticalDivider(),
              Expanded(child: Text(localizations.modify)),
            ],
          ),
          const Divider(thickness: 0.5),
          Column(children: rows(widget.items))
        ])));
  }

  int selected = -1;

  List<Widget> rows(List<RewriteItem> list) {
    var primaryColor = Theme.of(context).colorScheme.primary;
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    return List.generate(list.length, (index) {
      return InkWell(
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          hoverColor: primaryColor.withOpacity(0.3),
          onDoubleTap: () => showDialog(
                      context: context,
                      builder: (context) =>
                          RewriteUpdateAddDialog(item: list[index], ruleType: widget.ruleType, request: widget.request))
                  .then((value) {
                if (value != null) setState(() {});
              }),
          onSecondaryTapDown: (details) => showMenus(details, index),
          child: Container(
              color: selected == index
                  ? primaryColor
                  : index.isEven
                      ? Colors.grey.withOpacity(0.1)
                      : null,
              height: 30,
              padding: const EdgeInsets.all(5),
              child: Row(
                children: [
                  SizedBox(
                      width: 130,
                      child: Text(list[index].type.getDescribe(isCN), style: const TextStyle(fontSize: 13))),
                  SizedBox(
                      width: 40,
                      child: SwitchWidget(
                          scale: 0.6,
                          value: list[index].enabled,
                          onChanged: (val) {
                            list[index].enabled = val;
                          })),
                  const SizedBox(width: 20),
                  Expanded(child: Text(getText(list[index]).fixAutoLines(), style: const TextStyle(fontSize: 13))),
                ],
              )));
    });
  }

  String getText(RewriteItem item) {
    bool isUpdate =
        [RewriteType.updateBody, RewriteType.updateHeader, RewriteType.updateQueryParam].contains(item.type);
    if (isUpdate) {
      return "${item.key} -> ${item.value}";
    }

    return "${item.key}=${item.value}";
  }

  showMenus(TapDownDetails details, int index) {
    setState(() {
      selected = index;
    });

    showContextMenu(context, details.globalPosition, items: [
      PopupMenuItem(
          height: 35,
          child: Text(localizations.edit),
          onTap: () async {
            showDialog(
                context: context,
                barrierDismissible: false,
                builder: (BuildContext context) => RewriteUpdateAddDialog(
                    item: widget.items[index], ruleType: widget.ruleType, request: widget.request)).then((value) {
              if (value != null) {
                setState(() {});
              }
            });
          }),
      PopupMenuItem(
          height: 35,
          child: widget.items[index].enabled ? Text(localizations.disabled) : Text(localizations.enable),
          onTap: () => widget.items[index].enabled = !widget.items[index].enabled),
      const PopupMenuDivider(),
      PopupMenuItem(
          height: 35,
          child: Text(localizations.delete),
          onTap: () async {
            widget.items.removeAt(index);
            if (mounted) FlutterToastr.show(localizations.deleteSuccess, context);
          }),
    ]).then((value) {
      setState(() {
        selected = -1;
      });
    });
  }
}
