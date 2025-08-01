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
import 'package:get/get.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/request_map_manager.dart';
import 'package:proxypin/network/components/manager/rewrite_rule.dart';
import 'package:proxypin/ui/component/state_component.dart';

/// 重写替换
/// @author wanghongen
/// 2023/10/8
class DesktopMapLocal extends StatefulWidget {
  final int? windowId;
  final RequestMapItem? item;

  const DesktopMapLocal({super.key, this.item, this.windowId});

  @override
  State<DesktopMapLocal> createState() => MapLocaleState();
}

class MapLocaleState extends State<DesktopMapLocal> {
  final _headerKey = GlobalKey<HeadersState>();
  final bodyTextController = TextEditingController();

  RxString bodyType = RxString(ReplaceBodyType.text.name);
  Rxn<String> bodyFile = Rxn<String>();
  TextEditingController statusCodeController = TextEditingController(text: '200');

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  initState() {
    super.initState();
    initItem(widget.item);
  }

  @override
  dispose() {
    bodyTextController.dispose();
    statusCodeController.dispose();
    super.dispose();
  }

  ///初始化重写项
  void initItem(RequestMapItem? item) {
    if (item == null) {
      return;
    }
    statusCodeController.text = item.statusCode?.toString() ?? '200';
    bodyTextController.text = item.body ?? '';
    bodyType.value = item.bodyType ?? ReplaceBodyType.text.name;
  }

  RequestMapItem getRequestMapItem() {
    RequestMapItem item = widget.item ?? RequestMapItem();
    var headers = _headerKey.currentState?.getHeaders();
    item.statusCode = int.tryParse(statusCodeController.text) ?? 200;
    item.headers = headers;
    item.body = bodyTextController.text;
    item.bodyType = item.bodyType ?? ReplaceBodyType.text.name;
    if (item.bodyType == ReplaceBodyType.file.name) {
      item.bodyFile = bodyFile.value;
    } else {
      item.bodyFile = null;
    }
    return item;
  }

  @override
  Widget build(BuildContext context) {
    List<String> tabs = [localizations.statusCode, localizations.responseHeader, localizations.responseBody];

    return Container(
      constraints: const BoxConstraints(maxHeight: 340),
      child: DefaultTabController(
          length: tabs.length,
          initialIndex: tabs.length - 1,
          child: Scaffold(
            appBar: tabBar(tabs),
            body: TabBarView(children: [
              KeepAliveWrapper(child: statusCodeEdit()),
              KeepAliveWrapper(child: headers()),
              KeepAliveWrapper(child: body())
            ]),
          )),
    );
  }

  //tabBar
  TabBar tabBar(List<String> tabs) {
    return TabBar(
        tabs: tabs
            .map((label) => Tab(
                  height: 38,
                  child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                ))
            .toList());
  }

  //body
  Widget body() {
    bool isEN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'en');

    return Obx(() => Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.center, children: [
            const SizedBox(width: 5),
            Text("${localizations.type}: "),
            SizedBox(
                width: 90,
                child: DropdownButtonFormField<String>(
                    value: bodyType.value,
                    focusColor: Colors.transparent,
                    itemHeight: 48,
                    decoration: const InputDecoration(
                        contentPadding: EdgeInsets.all(10), isDense: true, border: InputBorder.none),
                    items: ReplaceBodyType.values
                        .map((e) => DropdownMenuItem(
                            value: e.name,
                            child: Text(isEN ? e.name.toUpperCase() : e.label,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))))
                        .toList(),
                    onChanged: (val) => bodyType.value = val ?? ReplaceBodyType.text.name)),
          ]),
          const SizedBox(height: 10),
          if (bodyType.value == ReplaceBodyType.file.name)
            fileBodyEdit()
          else
            TextFormField(
                controller: bodyTextController,
                style: const TextStyle(fontSize: 14),
                maxLines: 11,
                decoration: decoration(localizations.replaceBodyWith,
                    hintText: '${localizations.example} {"code":"200","data":{}}')),
        ]));
  }

  Widget fileBodyEdit() {
    //选择文件  删除
    return Obx(() => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: bodyFile.value == null
                  ? Container(height: 50)
                  : Container(
                      padding: const EdgeInsets.all(5),
                      foregroundDecoration:
                          BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1)),
                      child: Text(bodyFile.value ?? ''))),
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
                bodyFile.value = path;
              },
              child: Text(localizations.selectFile, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
          const SizedBox(width: 10),
          FilledButton(
              onPressed: () {
                setState(() {
                  bodyFile.value = null;
                });
              },
              child: Text(localizations.delete, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        ]));
  }

  //headers
  Widget headers() {
    return Headers(headers: widget.item?.headers, key: _headerKey);
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
    return Container(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text(localizations.statusCode),
            const SizedBox(width: 10),
            SizedBox(
                width: 100,
                child: TextFormField(
                  controller: statusCodeController,
                  style: const TextStyle(fontSize: 14),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                      contentPadding: const EdgeInsets.all(10),
                      focusedBorder: focusedBorder(),
                      isDense: true,
                      border: const OutlineInputBorder()),
                )),
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
        hintStyle: TextStyle(color: Colors.grey.shade500),
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
      _headers[TextEditingController()] = TextEditingController();
      return;
    }

    setHeaders(widget.headers);
  }

  void setHeaders(Map<String, String>? headers) {
    _clear();
    headers?.forEach((name, value) {
      _headers[TextEditingController(text: name)] = TextEditingController(text: value);
    });
    _headers[TextEditingController()] = TextEditingController();
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

  void _clear() {
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
                  child: const Icon(Icons.remove_circle_outline, size: 16)))));
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
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(width: 0.5, color: Colors.grey)),
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
