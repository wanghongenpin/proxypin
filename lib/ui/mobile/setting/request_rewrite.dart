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
import 'dart:collection';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/components/rewrite/request_rewrite_manager.dart';
import 'package:proxypin/network/components/rewrite/rewrite_rule.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/mobile/setting/rewrite/rewrite_update.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'rewrite/rewrite_replace.dart';

class MobileRequestRewrite extends StatefulWidget {
  final RequestRewriteManager requestRewrites;

  const MobileRequestRewrite({super.key, required this.requestRewrites});

  @override
  State<MobileRequestRewrite> createState() => _MobileRequestRewriteState();
}

class _MobileRequestRewriteState extends State<MobileRequestRewrite> {
  bool enabled = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    enabled = widget.requestRewrites.enabled;
  }

  @override
  void dispose() {
    if (enabled != widget.requestRewrites.enabled) {
      widget.requestRewrites.enabled = enabled;
      widget.requestRewrites.flushRequestRewriteConfig();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            centerTitle: true, title: Text(localizations.requestRewriteList, style: const TextStyle(fontSize: 16))),
        body: Container(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(localizations.requestRewriteEnable),
                    SwitchWidget(value: enabled, scale: 0.8, onChanged: (val) => enabled = val),
                  ],
                ),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  FilledButton.icon(
                      icon: const Icon(Icons.add, size: 18), onPressed: add, label: Text(localizations.add)),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    icon: const Icon(Icons.input_rounded, size: 18),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.only(left: 20, right: 20)),
                    onPressed: import,
                    label: Text(localizations.import),
                  ),
                ]),
                const SizedBox(height: 10),
                Expanded(child: RequestRuleList(widget.requestRewrites)),
              ],
            )));
  }

  //导入
  import() async {
    final XFile? file = await openFile();
    if (file == null) {
      return;
    }

    try {
      List json = jsonDecode(utf8.decode(await file.readAsBytes()));

      for (var item in json) {
        var rule = RequestRewriteRule.formJson(item);
        var items = (item['items'] as List).map((e) => RewriteItem.fromJson(e)).toList();
        await widget.requestRewrites.addRule(rule, items);
      }
      widget.requestRewrites.flushRequestRewriteConfig();

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

  void add([int currentIndex = -1]) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const RewriteRule())).then((rule) {
      if (rule != null) {
        setState(() {});
      }
    });
  }
}

///请求重写规则列表
class RequestRuleList extends StatefulWidget {
  final RequestRewriteManager requestRewrites;

  RequestRuleList(this.requestRewrites) : super(key: GlobalKey<_RequestRuleListState>());

  @override
  State<RequestRuleList> createState() => _RequestRuleListState();
}

class _RequestRuleListState extends State<RequestRuleList> {
  Set<int> selected = HashSet<int>();
  late List<RequestRewriteRule> rules;
  bool changed = false;

  bool multiple = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  initState() {
    super.initState();
    rules = widget.requestRewrites.rules;
  }

  @override
  void dispose() {
    if (changed) {
      widget.requestRewrites.flushRequestRewriteConfig();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        persistentFooterButtons: [multiple ? globalMenu() : const SizedBox()],
        body: Container(
            padding: const EdgeInsets.only(top: 10, bottom: 30),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.2))),
            child: Scrollbar(
                child: ListView(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Container(width: 60, padding: const EdgeInsets.only(left: 10), child: Text(localizations.name)),
                    SizedBox(width: 46, child: Text(localizations.enable, textAlign: TextAlign.center)),
                    const VerticalDivider(),
                    const Expanded(child: Text("URL")),
                    SizedBox(width: 60, child: Text(localizations.action, textAlign: TextAlign.center)),
                  ],
                ),
                const Divider(thickness: 0.5),
                Column(children: rows(widget.requestRewrites.rules))
              ],
            ))));
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
                        onPressed: () => removeRewrite(),
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

  List<Widget> rows(List<RequestRewriteRule> list) {
    var primaryColor = Theme.of(context).colorScheme.primary;
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');
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
                  ? primaryColor.withOpacity(0.8)
                  : index.isEven
                      ? Colors.grey.withOpacity(0.1)
                      : null,
              height: 45,
              padding: const EdgeInsets.all(5),
              child: Row(
                children: [
                  SizedBox(
                      width: 60,
                      child: Text(list[index].name ?? "",
                          overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                  SizedBox(
                      width: 35,
                      child: SwitchWidget(
                          scale: 0.65,
                          value: list[index].enabled,
                          onChanged: (val) {
                            list[index].enabled = val;
                            changed = true;
                          })),
                  const SizedBox(width: 20),
                  Expanded(child: Text(list[index].url, style: const TextStyle(fontSize: 13))),
                  const SizedBox(width: 3),
                  SizedBox(
                      width: 60,
                      child: Text(isCN ? list[index].type.label : list[index].type.name.camelCaseToSpaced(),
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
                ],
              )));
    });
  }

  showEdit(int index) async {
    var rule = widget.requestRewrites.rules[index];
    var rewriteItems = await widget.requestRewrites.getRewriteItems(rule);
    if (!mounted) return;

    Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => RewriteRule(rule: rule, items: rewriteItems)))
        .then((value) {
      if (value != null && mounted) {
        setState(() {});
      }
    });
  }

  //点击菜单
  showMenus(int index) {
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
            BottomSheetItem(text: localizations.share, onPressed: () => export([index])),
            const Divider(thickness: 0.5, height: 5),
            BottomSheetItem(
                text: rules[index].enabled ? localizations.disabled : localizations.enable,
                onPressed: () {
                  rules[index].enabled = !rules[index].enabled;
                  changed = true;
                }),
            const Divider(thickness: 0.5, height: 5),
            BottomSheetItem(
                text: localizations.delete,
                onPressed: () async {
                  await widget.requestRewrites.removeIndex([index]);
                  widget.requestRewrites.flushRequestRewriteConfig();
                  if (mounted) FlutterToastr.show(localizations.deleteSuccess, context);
                }),
            Container(color: Theme.of(ctx).hoverColor, height: 8),
            TextButton(
                child: Container(
                    height: 45,
                    width: double.infinity,
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(localizations.cancel, textAlign: TextAlign.center)),
                onPressed: () {
                  Navigator.of(ctx).pop();
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

  //导出js
  Future<void> export(List<int> indexes) async {
    if (indexes.isEmpty) return;
    String fileName = 'proxypin-rewrites.config';

    var list = [];
    for (var index in indexes) {
      var rule = widget.requestRewrites.rules[index];
      var json = rule.toJson();
      json.remove("rewritePath");
      json['items'] = await widget.requestRewrites.getRewriteItems(rule);
      list.add(json);
    }

    final XFile file = XFile.fromData(utf8.encode(jsonEncode(list)), mimeType: 'config');
    await Share.shareXFiles([file], fileNameOverrides: [fileName]);
  }

  //删除
  Future<void> removeRewrite() async {
    if (selected.isEmpty) return;
    return showConfirmDialog(context, content: localizations.requestRewriteDeleteConfirm(selected.length),
        onConfirm: () async {
      var list = selected.toList();
      list.sort((a, b) => b.compareTo(a));
      for (var value in list) {
        await widget.requestRewrites.removeIndex([value]);
      }
      widget.requestRewrites.flushRequestRewriteConfig();
      setState(() {
        multiple = false;
        selected.clear();
      });
      if (mounted) FlutterToastr.show(localizations.deleteSuccess, context);
    });
  }
}

///请求重写规则添加
class RewriteRule extends StatefulWidget {
  final RequestRewriteRule? rule;
  final List<RewriteItem>? items;
  final HttpRequest? request;

  const RewriteRule({super.key, this.rule, this.items, this.request});

  @override
  State<StatefulWidget> createState() {
    return _RewriteRuleState();
  }
}

class _RewriteRuleState extends State<RewriteRule> {
  final rewriteReplaceKey = GlobalKey<RewriteReplaceState>();
  final rewriteUpdateKey = GlobalKey<RewriteUpdateState>();

  late RequestRewriteRule rule;
  List<RewriteItem>? items;
  late RuleType ruleType;
  late TextEditingController nameInput;
  late TextEditingController urlInput;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  final ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    rule = widget.rule ?? RequestRewriteRule(url: '', type: RuleType.responseReplace);
    items = widget.items;
    ruleType = rule.type;

    nameInput = TextEditingController(text: rule.name);
    urlInput = TextEditingController(text: rule.url);

    if (items == null && widget.request != null) {
      items = fromRequestItems(widget.request!, ruleType);
    }
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
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    return Scaffold(
        appBar: AppBar(
          title: Row(children: [
            Text(localizations.requestRewrite, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(width: 15),
            Text.rich(TextSpan(
                text: localizations.useGuide,
                style: const TextStyle(color: Colors.blue, fontSize: 14),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => launchUrl(
                      mode: LaunchMode.externalApplication,
                      Uri.parse(isCN
                          ? 'https://gitee.com/wanghongenpin/proxypin/wikis/%E8%AF%B7%E6%B1%82%E9%87%8D%E5%86%99'
                          : 'https://github.com/wanghongenpin/proxypin/wiki/Request-Rewrite')))),
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
                  items = rewriteReplaceKey.currentState?.getItems() ?? rewriteUpdateKey.currentState?.getItems();

                  var requestRewrites = await RequestRewriteManager.instance;
                  var index = requestRewrites.rules.indexOf(rule);

                  if (index >= 0) {
                    await requestRewrites.updateRule(index, rule, items);
                  } else {
                    await requestRewrites.addRule(rule, items!);
                  }
                  requestRewrites.flushRequestRewriteConfig();
                  if (mounted) {
                    FlutterToastr.show(localizations.saveSuccess, this.context);
                    Navigator.of(this.context).pop(rule);
                  }
                })
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(15),
          child: NestedScrollView(
              controller: scrollController,
              headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
                return <Widget>[
                  SliverToBoxAdapter(
                      child: Form(
                    key: formKey,
                    child: Column(children: <Widget>[
                      Row(children: [
                        SizedBox(
                            width: 60,
                            child: Text('${localizations.enable}:',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500))),
                        SwitchWidget(value: rule.enabled, onChanged: (val) => rule.enabled = val, scale: 0.8)
                      ]),
                      textField('${localizations.name}:', nameInput, localizations.pleaseEnter),
                      textField('URL:', urlInput, 'https://www.example.com/api/*',
                          required: true, keyboardType: TextInputType.url),
                      Row(children: [
                        SizedBox(
                            width: 60,
                            child: Text('${localizations.action}:',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500))),
                        SizedBox(
                            width: 165,
                            height: 50,
                            child: DropdownButtonFormField<RuleType>(
                              onSaved: (val) => rule.type = val!,
                              value: ruleType,
                              decoration: const InputDecoration(
                                  errorStyle: TextStyle(height: 0, fontSize: 0), contentPadding: EdgeInsets.only()),
                              items: RuleType.values
                                  .map((e) => DropdownMenuItem(value: e, child: Text(isCN ? e.label : e.name)))
                                  .toList(),
                              onChanged: onChangeType,
                            )),
                        const SizedBox(width: 10),
                      ]),
                      const SizedBox(height: 10),
                    ]),
                  ))
                ];
              },
              body: rewriteRule()),
        ));
  }

  void onChangeType(RuleType? val) async {
    if (ruleType == val) return;

    ruleType = val!;
    items = [];

    if (ruleType == widget.rule?.type) {
      items = widget.items;
    } else if (widget.request != null) {
      items?.addAll(fromRequestItems(widget.request!, ruleType));
    }

    setState(() {
      rewriteReplaceKey.currentState?.initItems(ruleType, items);
      rewriteUpdateKey.currentState?.initItems(ruleType, items);
    });
  }

  static List<RewriteItem> fromRequestItems(HttpRequest request, RuleType ruleType) {
    if (ruleType == RuleType.requestReplace) {
      //请求替换
      return RewriteItem.fromRequest(request);
    } else if (ruleType == RuleType.responseReplace && request.response != null) {
      //响应替换
      return RewriteItem.fromResponse(request.response!);
    }
    return [];
  }

  Widget rewriteRule() {
    if (ruleType == RuleType.requestUpdate || ruleType == RuleType.responseUpdate) {
      return MobileRewriteUpdate(key: rewriteUpdateKey, items: items, ruleType: ruleType, request: widget.request);
    }

    return MobileRewriteReplace(
        scrollController: scrollController, key: rewriteReplaceKey, items: items, ruleType: ruleType);
  }

  Widget textField(String label, TextEditingController controller, String hint,
      {bool required = false, TextInputType? keyboardType, FormFieldSetter<String>? onSaved}) {
    return Row(children: [
      SizedBox(width: 60, child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500))),
      Expanded(
          child: TextFormField(
        controller: controller,
        validator: (val) => val?.isNotEmpty == true || !required ? null : "",
        onSaved: onSaved,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade500),
          contentPadding: const EdgeInsets.only(),
          errorStyle: const TextStyle(height: 0, fontSize: 0),
        ),
      ))
    ]);
  }
}
