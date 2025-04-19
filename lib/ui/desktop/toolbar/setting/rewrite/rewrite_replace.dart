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

import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/rewrite_rule.dart';
import 'package:proxypin/ui/component/state_component.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/utils/lang.dart';

/// 重写替换
/// @author wanghongen
/// 2023/10/8
class DesktopRewriteReplace extends StatefulWidget {
  final int? windowId;
  final RuleType ruleType;
  final List<RewriteItem>? items;

  const DesktopRewriteReplace({super.key, this.items, required this.ruleType, this.windowId});

  @override
  State<DesktopRewriteReplace> createState() => RewriteReplaceState();
}

class RewriteReplaceState extends State<DesktopRewriteReplace> {
  final _headerKey = GlobalKey<HeadersState>();
  final bodyTextController = TextEditingController();
  late RuleType ruleType;
  List<RewriteItem> items = [];

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  initState() {
    super.initState();
    ruleType = widget.ruleType;
    initItems(widget.ruleType, widget.items);
  }

  @override
  dispose() {
    bodyTextController.dispose();
    super.dispose();
  }

  ///初始化重写项
  initItems(RuleType ruleType, List<RewriteItem>? items) {
    this.items.clear();
    this.ruleType = ruleType;
    if (ruleType == RuleType.redirect) {
      _initRewriteItem(items, RewriteType.redirect, enabled: true);
      return;
    }

    if (ruleType == RuleType.requestReplace) {
      _initRewriteItem(items, RewriteType.replaceRequestLine);
      _initRewriteItem(items, RewriteType.replaceRequestHeader);
      _initRewriteItem(items, RewriteType.replaceRequestBody, enabled: true);
      return;
    }

    if (ruleType == RuleType.responseReplace) {
      _initRewriteItem(items, RewriteType.replaceResponseStatus);
      _initRewriteItem(items, RewriteType.replaceResponseHeader);
      _initRewriteItem(items, RewriteType.replaceResponseBody, enabled: true);
      return;
    }
  }

  RewriteItem _initRewriteItem(List<RewriteItem>? items, RewriteType type, {bool enabled = false}) {
    var item = items?.firstWhereOrNull((it) => it.type == type);
    RewriteItem rewriteItem = RewriteItem(type, item?.enabled ?? enabled, values: item?.values);
    this.items.add(rewriteItem);

    if (type == RewriteType.replaceRequestHeader || type == RewriteType.replaceResponseHeader) {
      _headerKey.currentState?.setHeaders(rewriteItem.headers);
    }

    if ((type == RewriteType.replaceResponseBody || type == RewriteType.replaceRequestBody) &&
        rewriteItem.bodyType != ReplaceBodyType.file.name) {
      bodyTextController.text = rewriteItem.body ?? '';
    }

    return rewriteItem;
  }

  List<RewriteItem> getItems() {
    var headers = _headerKey.currentState?.getHeaders();
    if (headers != null) {
      items
          .firstWhere(
              (item) => item.type == RewriteType.replaceRequestHeader || item.type == RewriteType.replaceResponseHeader)
          .headers = headers;
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    if (ruleType == RuleType.redirect) {
      return SizedBox(
          height: 120, child: Padding(padding: EdgeInsets.symmetric(vertical: 15), child: redirectEdit(items.first)));
    }

    if (ruleType == RuleType.responseReplace || ruleType == RuleType.requestReplace) {
      bool requestEdited = ruleType == RuleType.requestReplace;
      List<String> tabs = requestEdited
          ? [localizations.requestLine, localizations.requestHeader, localizations.requestBody]
          : [localizations.statusCode, localizations.responseHeader, localizations.responseBody];

      return Container(
        constraints: const BoxConstraints(maxHeight: 370),
        child: DefaultTabController(
            length: tabs.length,
            initialIndex: tabs.length - 1,
            child: Scaffold(
              appBar: tabBar(tabs),
              body: TabBarView(children: [
                KeepAliveWrapper(child: requestEdited ? requestLine() : statusCodeEdit()),
                KeepAliveWrapper(child: headers()),
                KeepAliveWrapper(child: body())
              ]),
            )),
      );
    }

    return Container();
  }

  //tabBar
  TabBar tabBar(List<String> tabs) {
    return TabBar(
        tabs: tabs
            .map((label) => Tab(
                height: 38,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 5),
                  Dot(color: items[tabs.indexOf(label)].enabled ? const Color(0xFF00FF00) : Colors.grey)
                ])))
            .toList());
  }

  bool jsonFormatted = false;

  //body
  Widget body() {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    var rewriteItem = items.firstWhere(
        (item) => item.type == RewriteType.replaceRequestBody || item.type == RewriteType.replaceResponseBody);

    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.center, children: [
        const SizedBox(width: 5),
        Text("${localizations.type}: "),
        SizedBox(
            width: 90,
            child: DropdownButtonFormField<String>(
                value: rewriteItem.bodyType ?? ReplaceBodyType.text.name,
                focusColor: Colors.transparent,
                itemHeight: 48,
                decoration:
                    const InputDecoration(contentPadding: EdgeInsets.all(10), isDense: true, border: InputBorder.none),
                items: ReplaceBodyType.values
                    .map((e) => DropdownMenuItem(
                        value: e.name,
                        child: Text(isCN ? e.label : e.name.toUpperCase(),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))))
                    .toList(),
                onChanged: (val) => setState(() {
                      rewriteItem.bodyType = val!;
                    }))),
        Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          IconButton(
            tooltip: 'JSON Format',
            icon:
                Icon(Icons.data_object, size: 20, color: jsonFormatted ? Theme.of(context).colorScheme.primary : null),
            onPressed: () {
              setState(() {
                jsonFormatted = !jsonFormatted;
                bodyTextController.text =
                    jsonFormatted ? JSON.pretty(bodyTextController.text) : JSON.compact(bodyTextController.text);
              });
            },
          ),
          const SizedBox(width: 15),
          Text(localizations.enable),
          const SizedBox(width: 10),
          SwitchWidget(
              value: rewriteItem.enabled,
              scale: 0.65,
              onChanged: (val) => setState(() {
                    rewriteItem.enabled = val;
                  }))
        ]))
      ]),
      const SizedBox(height: 10),
      if (rewriteItem.bodyType == ReplaceBodyType.file.name)
        fileBodyEdit(rewriteItem)
      else
        TextFormField(
            controller: bodyTextController,
            style: const TextStyle(fontSize: 14),
            maxLines: 12,
            decoration: decoration(localizations.replaceBodyWith,
                hintText: '${localizations.example} {"code":"200","data":{}}'),
            onChanged: (val) => rewriteItem.body = val)
    ]);
  }

  Widget fileBodyEdit(RewriteItem item) {
    //选择文件  删除
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
          child: item.bodyFile == null
              ? Container(height: 50)
              : Container(
                  padding: const EdgeInsets.all(5),
                  foregroundDecoration:
                      BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1)),
                  child: Text(item.bodyFile ?? ''))),
      const SizedBox(width: 10),
      FilledButton(
          onPressed: () async {
            String? path;
            if (Platform.isMacOS) {
              path = await DesktopMultiWindow.invokeMethod(0, "pickFiles");
              if (widget.windowId != null) WindowController.fromWindowId(widget.windowId!).show();
            } else {
              FilePickerResult? result = await FilePicker.platform.pickFiles();
              path = result?.files.single.path;
            }

            if (path == null) {
              return;
            }
            item.bodyFile = path;
            setState(() {});
          },
          child: Text(localizations.selectFile, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
      const SizedBox(width: 10),
      FilledButton(
          onPressed: () {
            setState(() {
              item.bodyFile = null;
            });
          },
          child: Text(localizations.delete, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
    ]);
  }

  //headers
  Widget headers() {
    var rewriteItem = items.firstWhere(
        (item) => item.type == RewriteType.replaceRequestHeader || item.type == RewriteType.replaceResponseHeader);

    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.center, children: [
        const Text('Headers'),
        const SizedBox(width: 10),
        Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text(localizations.enable),
          const SizedBox(width: 10),
          SwitchWidget(
              value: rewriteItem.enabled,
              scale: 0.65,
              onChanged: (val) => setState(() {
                    rewriteItem.enabled = val;
                  }))
        ]))
      ]),
      Expanded(child: Headers(headers: rewriteItem.headers, key: _headerKey))
    ]);
  }

  ///请求行
  Widget requestLine() {
    var rewriteItem = items.firstWhere((item) => item.type == RewriteType.replaceRequestLine);
    return Column(
      children: [
        Row(children: [
          Text(localizations.requestMethod),
          const SizedBox(width: 10),
          SizedBox(
              width: 120,
              child: DropdownButtonFormField<String>(
                  value: rewriteItem.method?.name ?? 'GET',
                  focusColor: Colors.transparent,
                  itemHeight: 48,
                  decoration: const InputDecoration(
                      contentPadding: EdgeInsets.all(10), isDense: true, border: InputBorder.none),
                  items: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS']
                      .map((e) => DropdownMenuItem(
                          value: e, child: Text(e, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))))
                      .toList(),
                  onChanged: (val) {
                    setState(() {
                      rewriteItem.values['method'] = val!;
                    });
                  })),
          Expanded(
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text(localizations.enable),
            const SizedBox(width: 10),
            SwitchWidget(
                value: rewriteItem.enabled,
                scale: 0.65,
                onChanged: (val) {
                  setState(() {
                    rewriteItem.enabled = val;
                  });
                })
          ])),
        ]),
        const SizedBox(height: 15),
        textField("Path", rewriteItem.path, "${localizations.example} /api/v1/user",
            onChanged: (val) => rewriteItem.path = val),
        const SizedBox(height: 15),
        textField("URL${localizations.param}", rewriteItem.queryParam, "${localizations.example} id=1&name=2",
            onChanged: (val) => rewriteItem.queryParam = val),
      ],
    );
  }

  //重定向
  Widget redirectEdit(RewriteItem rewriteItem) {
    return TextFormField(
        decoration: decoration(localizations.redirectTo, hintText: 'https://www.example.com/api'),
        maxLines: 5,
        style: const TextStyle(fontSize: 14),
        initialValue: rewriteItem.redirectUrl,
        onChanged: (val) => rewriteItem.redirectUrl = val,
        validator: (val) {
          if (val == null || val.trim().isEmpty) {
            return '${localizations.redirect} URL ${localizations.cannotBeEmpty}';
          }
          return null;
        });
  }

  Widget textField(String label, dynamic value, String hint, {ValueChanged<String>? onChanged}) {
    return Row(children: [
      SizedBox(width: 80, child: Text(label)),
      Expanded(
          child: TextFormField(
        initialValue: value,
        onChanged: onChanged,
        decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            contentPadding: const EdgeInsets.all(10),
            errorStyle: const TextStyle(height: 0, fontSize: 0),
            focusedBorder: focusedBorder(),
            isDense: true,
            border: const OutlineInputBorder()),
      ))
    ]);
  }

  Widget statusCodeEdit() {
    var rewriteItem = items.firstWhere((item) => item.type == RewriteType.replaceResponseStatus);

    return Container(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text(localizations.statusCode),
            const SizedBox(width: 10),
            SizedBox(
                width: 100,
                child: TextFormField(
                  style: const TextStyle(fontSize: 14),
                  initialValue: rewriteItem.statusCode?.toString(),
                  onChanged: (val) => rewriteItem.statusCode = int.tryParse(val),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                      contentPadding: const EdgeInsets.all(10),
                      focusedBorder: focusedBorder(),
                      isDense: true,
                      border: const OutlineInputBorder()),
                )),
            Expanded(
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(localizations.enable),
              const SizedBox(width: 10),
              SwitchWidget(
                  value: rewriteItem.enabled,
                  scale: 0.65,
                  onChanged: (val) => setState(() {
                        rewriteItem.enabled = val;
                      }))
            ])),
            const SizedBox(width: 10),
          ])
        ]));
  }

  InputDecoration decoration(String label, {String? hintText}) {
    Color color = Theme.of(context).colorScheme.primary;
    // Color color = Colors.blueAccent;
    return InputDecoration(
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelText: label,
        hintText: hintText,
        isDense: true,
        border: OutlineInputBorder(borderSide: BorderSide(width: 0.8, color: color)),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(width: 1.5, color: color)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(width: 2, color: color)));
  }

  InputBorder focusedBorder() {
    return OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2));
  }
}

///请求头
class Headers extends StatefulWidget {
  final Map<String, String>? headers;

  const Headers({super.key, this.headers});

  @override
  State<StatefulWidget> createState() {
    return HeadersState();
  }
}

class HeadersState extends State<Headers> with AutomaticKeepAliveClientMixin {
  final Map<TextEditingController, TextEditingController> _headers = {};

  @override
  bool get wantKeepAlive => true;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    if (widget.headers == null) {
      return;
    }

    setHeaders(widget.headers);
  }

  setHeaders(Map<String, String>? headers) {
    _clear();
    headers?.forEach((name, value) {
      _headers[TextEditingController(text: name)] = TextEditingController(text: value);
    });
  }

  ///获取所有请求头
  Map<String, String> getHeaders() {
    var headers = <String, String>{};
    _headers.forEach((name, value) {
      if (name.text.isEmpty) {
        return;
      }
      headers[name.text] = value.text;
    });
    return headers;
  }

  @override
  dispose() {
    _clear();
    super.dispose();
  }

  _clear() {
    _headers.forEach((key, value) {
      key.dispose();
      value.dispose();
    });
    _headers.clear();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    var list = _buildRows();

    return Column(children: [
      Expanded(
          child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              child: ListView.separated(
                  shrinkWrap: true,
                  separatorBuilder: (context, index) =>
                      index == list.length ? const SizedBox() : const Divider(thickness: 0.2),
                  itemBuilder: (context, index) => list[index],
                  itemCount: list.length))),
      TextButton(
        child: Text("${localizations.add}Header", textAlign: TextAlign.center),
        onPressed: () {
          setState(() {
            _headers[TextEditingController()] = TextEditingController();
          });
        },
      ),
    ]);
  }

  List<Widget> _buildRows() {
    List<Widget> list = [];

    _headers.forEach((key, val) {
      list.add(_row(
          _cell(key, isKey: true),
          _cell(val),
          Padding(
              padding: const EdgeInsets.only(right: 15),
              child: InkWell(
                  onTap: () {
                    setState(() {
                      _headers.remove(key);
                    });
                  },
                  child: const Icon(Icons.remove_circle, size: 16)))));
    });

    return list;
  }

  Widget _cell(TextEditingController val, {bool isKey = false}) {
    return Container(
        padding: const EdgeInsets.only(right: 5),
        child: TextFormField(
            style: TextStyle(fontSize: 12, fontWeight: isKey ? FontWeight.w500 : null),
            controller: val,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                hintText: isKey ? "Key" : "Value")));
  }

  Widget _row(Widget key, Widget val, Widget? op) {
    return Row(children: [
      Expanded(flex: 4, child: key),
      const Text(": ", style: TextStyle(color: Colors.deepOrangeAccent)),
      Expanded(flex: 6, child: val),
      op ?? const SizedBox()
    ]);
  }
}
