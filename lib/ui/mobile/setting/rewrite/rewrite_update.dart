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
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:get/get.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/rewrite_rule.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/utils/code_editor_compat.dart';
import 'package:proxypin/utils/flutter_compat.dart';
import 'package:proxypin/utils/lang.dart';

class MobileRewriteUpdate extends StatefulWidget {
  final RuleType ruleType;
  final List<RewriteItem>? items;
  final HttpRequest? request;

  const MobileRewriteUpdate({super.key, required this.ruleType, this.items, required this.request});

  @override
  State<MobileRewriteUpdate> createState() => RewriteUpdateState();
}

class RewriteUpdateState extends State<MobileRewriteUpdate> {
  late RuleType ruleType;
  List<RewriteItem> items = [];

  AppLocalizations get i18n => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    initItems(widget.ruleType, widget.items);
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   add();
    // });
  }

  ///初始化重写项
  void initItems(RuleType ruleType, List<RewriteItem>? items) {
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
    return ListView(
      physics: ClampingScrollPhysics(),
      children: [
        Row(
          children: [
            SizedBox(
                width: 260,
                child: Text(i18n.requestRewriteRule,
                    maxLines: 1, style: const TextStyle(fontSize: 13, color: Colors.grey))),
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

  void add() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => RewriteUpdateEdit(ruleType: ruleType, request: widget.request)))
        .then((value) {
      if (value != null) {
        setState(() {
          items.add(value);
        });
      }
    });
  }
}

class RewriteUpdateEdit extends StatefulWidget {
  final RewriteItem? item;
  final RuleType ruleType;
  final HttpRequest? request;

  const RewriteUpdateEdit({super.key, this.item, required this.ruleType, this.request});

  @override
  State<RewriteUpdateEdit> createState() => _RewriteUpdateAddState();
}

class _RewriteUpdateAddState extends State<RewriteUpdateEdit> {
  late RewriteType rewriteType;
  GlobalKey formKey = GlobalKey<FormState>();
  late RewriteItem rewriteItem;

  var keyController = TextEditingController();
  var valueController = TextEditingController();
  final CodeController _codeDataController = CodeController();
  late CodeSearchController _findController;

  bool jsonFormatted = false;
  bool useRegex = true;

  AppLocalizations get i18n => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    rewriteType = widget.item?.type ?? RewriteType.updateBody;
    rewriteItem = widget.item ?? RewriteItem(rewriteType, true);
    useRegex = widget.item?.useRegex ?? true;

    keyController.text = rewriteItem.key ?? '';
    valueController.text = rewriteItem.value ?? '';

    _findController = CodeSearchController(codeController: _codeDataController);
    _findController.isRegex = useRegex;

    initTestData();
    keyController.addListener(onInputChangeMatch);
  }

  @override
  void dispose() {
    keyController.dispose();
    valueController.dispose();
    _codeDataController.dispose();
    _findController.dispose();
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
      keyTips = i18n.matchRule;
      valueTips = i18n.emptyMatchAll;
    } else if (rewriteType == RewriteType.updateQueryParam || rewriteType == RewriteType.updateHeader) {
      keyTips = rewriteType == RewriteType.updateQueryParam ? "name=123" : "Content-Type: application/json";
      valueTips = rewriteType == RewriteType.updateQueryParam ? "name=456" : "Content-Type: application/xml";
    }

    var typeList = widget.ruleType == RuleType.requestUpdate ? RewriteType.updateRequest : RewriteType.updateResponse;
    bool isCN = Localizations.localeOf(context).languageCode == "zh";
    return Scaffold(
        appBar: AppBar(
            centerTitle: true,
            title: Text(i18n.requestRewriteRule, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            actions: [
              TextButton(
                  onPressed: () {
                    if (!(formKey.currentState as FormState).validate()) {
                      FlutterToastr.show(i18n.cannotBeEmpty, context, position: FlutterToastr.center);
                      return;
                    }
                    (formKey.currentState as FormState).save();
                    rewriteItem.key = keyController.text;
                    rewriteItem.value = valueController.text;
                    rewriteItem.type = rewriteType;
                    rewriteItem.useRegex = useRegex;
                    Navigator.of(context).pop(rewriteItem);
                  },
                  child: Text(i18n.confirm)),
              SizedBox(width: 5)
            ]),
        body: Form(
            key: formKey,
            child: ListView(padding: const EdgeInsets.all(10), children: [
              Row(
                children: [
                  Text(i18n.type),
                  const SizedBox(width: 15),
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
                              child: Text(e.getDescribe(isCN),
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
              textField(isUpdate ? i18n.match : i18n.name, keyTips, controller: keyController, required: !isDelete,
                  suffix: (isUpdate || isDelete)
                      ? InkWell(
                          onTap: () {
                            setState(() => useRegex = !useRegex);
                            _findController.isRegex = useRegex;
                            onInputChangeMatch();
                          },
                          child: Tooltip(
                            message: i18n.regExp,
                            padding: const EdgeInsets.only(right: 2, left: 2),
                            child: Text(
                              '.*',
                              style: TextStyle(
                                fontSize: 14,
                                color: useRegex ? Theme.of(context).colorScheme.primary : Colors.grey,
                                fontWeight: useRegex ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        )
                      : null),
              const SizedBox(height: 15),
              textField(isUpdate ? i18n.replace : i18n.value, valueTips, controller: valueController),
              const SizedBox(height: 10),
              Row(children: [
                Align(
                    alignment: Alignment.centerLeft, child: Text(i18n.testData, style: const TextStyle(fontSize: 14))),
                const SizedBox(width: 10),
                Obx(() => isMatch.value
                    ? SizedBox()
                    : Text(i18n.noChangesDetected, style: TextStyle(color: Colors.red, fontSize: 14))),
                Expanded(child: SizedBox()),
                IconButton(
                  tooltip: 'JSON Format',
                  icon: Icon(Icons.data_object,
                      size: 20, color: jsonFormatted ? Theme.of(context).colorScheme.primary : null),
                  onPressed: () {
                    setState(() {
                      jsonFormatted = !jsonFormatted;
                      _codeDataController.text = jsonFormatted
                          ? JSON.pretty(_codeDataController.text)
                          : JSON.compact(_codeDataController.text);
                    });
                  },
                ),
                const SizedBox(width: 3),
              ]),
              const SizedBox(height: 5),
              Container(
                  height: MediaQuery.of(context).size.height * 0.45,
                  decoration: BoxDecoration(border: Border.all(color: Colors.black12)),
                  child: CodeField(
                    controller: _codeDataController,
                    cursorColor: Theme.of(context).colorScheme.primary,
                    textStyle: const TextStyle(fontSize: 14),
                  )),
            ])));
  }

  //判断是否是json格式
  bool isJsonText() {
    var bodyString = _codeDataController.text;
    return (bodyString.startsWith('{') && bodyString.endsWith('}') ||
        bodyString.startsWith('[') && bodyString.endsWith(']'));
  }

  void initTestData() {
    // dataController.splitPattern = null;
    bool isRemove = [RewriteType.removeHeader, RewriteType.removeQueryParam].contains(rewriteType);

    valueController.removeListener(onInputChangeMatch);
    if (isRemove) {
      valueController.addListener(onInputChangeMatch);
    }

    if (widget.request == null) return;

    if (rewriteType == RewriteType.updateBody) {
      _codeDataController.text = (widget.ruleType == RuleType.requestUpdate
          ? widget.request?.getBodyString()
          : widget.request?.response?.getBodyString()) ??
          '';
      return;
    }

    if (rewriteType == RewriteType.updateQueryParam || rewriteType == RewriteType.removeQueryParam) {
      // dataController.splitPattern = '&';
      _codeDataController.text = Uri.decodeQueryComponent(widget.request?.requestUri?.query ?? '');
      return;
    }

    if (rewriteType == RewriteType.updateHeader || rewriteType == RewriteType.removeHeader) {
      var headerData = widget.ruleType == RuleType.requestUpdate
          ? widget.request?.headers.toRawHeaders()
          : widget.request?.response?.headers.toRawHeaders();
      _codeDataController.text = headerData ?? '';
      return;
    }

    _codeDataController.text = '';
  }

  bool onMatch = false; //是否正在匹配
  RxBool isMatch = true.obs;

  void onInputChangeMatch() {
    bool highlightEnabled = rewriteType != RewriteType.addQueryParam && rewriteType != RewriteType.addHeader;
    if (onMatch || highlightEnabled == false) {
      return;
    }
    onMatch = true;

    //高亮显示
    Future.delayed(const Duration(milliseconds: 800), () {
      onMatch = false;
      if (_codeDataController.text.isEmpty) {
        if (isMatch.value) return;
        isMatch.value = true;
        return;
      }

      if (!mounted) return;
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

      // 使用简单正则匹配检测 key 是否存在于文本中
      if (key.isEmpty) {
        isMatch.value = true;
      } else {
        final pattern = RegExp(RegExp.escape(key), caseSensitive: false);
        isMatch.value = pattern.hasMatch(_codeDataController.text);
      }
    });
  }

  Widget textField(String label, String hint, {bool required = false, int? lines, TextEditingController? controller, Widget? suffix}) {
    return Row(children: [
      SizedBox(width: 55, child: Text(label)),
      Expanded(child: formField(hint, required: required, lines: lines, controller: controller, suffix: suffix)),
    ]);
  }

  Widget formField(String hint, {bool required = false, int? lines, TextEditingController? controller, Widget? suffix}) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(fontSize: 14),
      onTapOutside: (event) => FocusScope.of(context).unfocus(),
      minLines: lines ?? 1,
      maxLines: lines ?? 1,
      validator: (val) => val?.isNotEmpty == true || !required ? null : "",
      decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          contentPadding: const EdgeInsets.all(10),
          errorStyle: const TextStyle(height: 0, fontSize: 0),
          focusedBorder: focusedBorder(),
          isDense: true,
          suffix: suffix,
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
  AppLocalizations get i18n => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.withValues(alpha: 0.2))),
        child: Column(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(width: 130, padding: const EdgeInsets.only(left: 10), child: Text(i18n.type)),
              SizedBox(width: 50, child: Text(i18n.enable, textAlign: TextAlign.center)),
              const VerticalDivider(),
              Expanded(child: Text(i18n.modify)),
            ],
          ),
          const Divider(thickness: 0.5),
          Column(children: rows(widget.items))
        ]));
  }

  int selected = -1;

  List<Widget> rows(List<RewriteItem> list) {
    var primaryColor = Theme.of(context).colorScheme.primary;

    return List.generate(list.length, (index) {
      return InkWell(
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          hoverColor: primaryColor.withValues(alpha: 0.3),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) =>
                      RewriteUpdateEdit(item: list[index], ruleType: widget.ruleType, request: widget.request)))
              .then((value) {
            if (value != null) setState(() {});
          }),
          onLongPress: () => showMenus(index),
          child: Container(
              color: selected == index
                  ? primaryColor
                  : index.isEven
                  ? Colors.grey.withValues(alpha: 0.1)
                  : null,
              constraints: const BoxConstraints(minHeight: 38, maxHeight: 45),
              padding: const EdgeInsets.all(5),
              child: Row(
                children: [
                  SizedBox(
                      width: 130,
                      child: Text(list[index].type.getDescribe(i18n.localeName == 'zh'),
                          style: const TextStyle(fontSize: 13))),
                  SizedBox(
                      width: 40,
                      child: SwitchWidget(
                          scale: 0.6,
                          value: list[index].enabled,
                          onChanged: (val) {
                            list[index].enabled = val;
                          })),
                  const SizedBox(width: 20),
                  Expanded(
                      child:
                      Text(getText(list[index]).fixAutoLines(), maxLines: 2, style: const TextStyle(fontSize: 13))),
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

  void showMenus(int index) {
    setState(() {
      selected = index;
    });

    showModalBottomSheet(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        context: context,
        enableDrag: true,
        builder: (ctx) {
          return Wrap(alignment: WrapAlignment.center, children: [
            BottomSheetItem(
                text: i18n.modify,
                onPressed: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (BuildContext context) => RewriteUpdateEdit(
                              item: widget.items[index],
                              ruleType: widget.ruleType,
                              request: widget.request))).then((value) {
                    if (value != null) {
                      setState(() {});
                    }
                  });
                }),
            const Divider(thickness: 0.5),
            BottomSheetItem(
                text: widget.items[index].enabled ? i18n.disabled : i18n.enable,
                onPressed: () => widget.items[index].enabled = !widget.items[index].enabled),
            const Divider(thickness: 0.5),
            BottomSheetItem(
                text: i18n.delete,
                onPressed: () async {
                  widget.items.removeAt(index);
                  if (mounted) FlutterToastr.show(i18n.deleteSuccess, context);
                }),
            Container(color: Theme.of(context).hoverColor, height: 8),
            TextButton(
                child: Container(
                    height: 50,
                    width: double.infinity,
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(i18n.cancel, textAlign: TextAlign.center)),
                onPressed: () {
                  Navigator.of(context).pop();
                }),
          ]);
        }).then((value) {
      setState(() {
        selected = -1;
      });
    });
  }
}
