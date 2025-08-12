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
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/desktop/request/model/search_model.dart';
import 'package:proxypin/utils/lang.dart';

/// @author wanghongen
/// 2023/8/6
class SearchConditions extends StatefulWidget {
  final SearchModel searchModel;
  final Function(SearchModel searchModel)? onSearch;
  final EdgeInsetsGeometry? padding;

  const SearchConditions({super.key, required this.searchModel, this.onSearch, this.padding});

  @override
  State<StatefulWidget> createState() {
    return SearchConditionsState();
  }
}

class SearchConditionsState extends State<SearchConditions> {
  final Map<String, ContentType?> requestContentMap = {
    'JSON': ContentType.json,
    'FORM-URL': ContentType.formUrl,
    'FORM-DATA': ContentType.formData,
  };

  final Map<String, ContentType?> responseContentMap = {
    'JSON': ContentType.json,
    'HTML': ContentType.html,
    'JS': ContentType.js,
    'CSS': ContentType.css,
    'TEXT': ContentType.text,
    'IMAGE': ContentType.image
  };

  late SearchModel searchModel;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    searchModel = widget.searchModel.clone();
  }

  @override
  Widget build(BuildContext context) {
    requestContentMap[localizations.all] = null;
    responseContentMap[localizations.all] = null;
    Color primaryColor = ColorScheme.of(context).primary;
    return Container(
        padding: widget.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
                initialValue: searchModel.keyword,
                onChanged: (val) => searchModel.keyword = val,
                onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.all(10),
                  border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(15))),
                  hintText: localizations.keyword,
                  suffixIcon: Obx(() => IconButton(
                        tooltip: "Case Sensitive",
                        color: searchModel.caseSensitive.value ? primaryColor : null,
                        icon: Icon(Icons.text_fields),
                        onPressed: () {
                          searchModel.caseSensitive.value = !searchModel.caseSensitive.value;
                        },
                      )),
                )),
            const SizedBox(height: 15),
            Text(localizations.keywordSearchScope),
            const SizedBox(height: 10),
            Wrap(
              children: [
                options('URL', Option.url),
                options(localizations.requestHeader, Option.requestHeader),
                options(localizations.requestBody, Option.requestBody),
                options(localizations.responseHeader, Option.responseHeader),
                options(localizations.responseBody, Option.responseBody)
              ],
            ),
            const SizedBox(height: 15),
            row(
                Text('${localizations.requestMethod}:'),
                DropdownMenu(
                    initialValue: searchModel.requestMethod?.name ?? localizations.all,
                    items: HttpMethod.methods().map((e) => e.name).toList()..insert(0, localizations.all),
                    onSelected: (String value) {
                      searchModel.requestMethod = value == localizations.all ? null : HttpMethod.valueOf(value);
                    })),
            const SizedBox(height: 15),
            row(
                Text('${localizations.requestType}:'),
                DropdownMenu(
                    initialValue: Maps.getKey(requestContentMap, searchModel.requestContentType) ?? localizations.all,
                    items: requestContentMap.keys,
                    onSelected: (String value) {
                      searchModel.requestContentType = requestContentMap[value];
                    })),
            const SizedBox(height: 15),
            row(
                Text('${localizations.responseType}:'),
                DropdownMenu(
                    initialValue: Maps.getKey(responseContentMap, searchModel.responseContentType) ?? localizations.all,
                    items: responseContentMap.keys,
                    onSelected: (String value) {
                      searchModel.responseContentType = responseContentMap[value];
                    })),
            row(
              Text("${localizations.statusCode}: "),
              TextFormField(
                initialValue: searchModel.statusCode?.toString(),
                onChanged: (val) => searchModel.statusCode = int.tryParse(val),
                onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
                inputFormatters: <TextInputFormatter>[
                  LengthLimitingTextInputFormatter(5),
                  FilteringTextInputFormatter.allow(RegExp('[-0-9]'))
                ],
                decoration: const InputDecoration(
                  isCollapsed: true,
                  contentPadding: EdgeInsets.all(10),
                ),
              ),
            ),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(localizations.cancel, style: const TextStyle(fontSize: 14))),
                TextButton(
                    onPressed: () {
                      widget.onSearch?.call(SearchModel());
                      Navigator.pop(context);
                    },
                    child: Text(localizations.clearSearch, style: const TextStyle(fontSize: 14))),
                TextButton(
                    onPressed: () {
                      widget.onSearch?.call(searchModel);
                      Navigator.pop(context);
                    },
                    child: Text(localizations.confirm, style: const TextStyle(fontSize: 14))),
              ],
            )
          ],
        ));
  }

  Widget options(String title, Option option) {
    bool isCN = localizations.localeName == 'zh';
    return Container(
        constraints: BoxConstraints(maxWidth: isCN ? 100 : 152, minWidth: 100, maxHeight: 33),
        child: Row(children: [
          Text(title, style: const TextStyle(fontSize: 12)),
          Checkbox(
              value: searchModel.searchOptions.contains(option),
              onChanged: (val) {
                setState(() {
                  val == true ? searchModel.searchOptions.add(option) : searchModel.searchOptions.remove(option);
                });
              })
        ]));
  }

  Widget row(Widget child, Widget child2) {
    return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [Expanded(flex: 5, child: child), Expanded(flex: 6, child: child2)]);
  }
}

class DropdownMenu<T> extends StatefulWidget {
  final String? initialValue;
  final Iterable<String> items;
  final Function(String value) onSelected;

  const DropdownMenu({super.key, this.initialValue, required this.items, required this.onSelected});

  @override
  State<StatefulWidget> createState() {
    return DropdownMenuState();
  }
}

class DropdownMenuState extends State<DropdownMenu> {
  String? selectValue;

  @override
  void initState() {
    super.initState();
    selectValue = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton(
      tooltip: '',
      initialValue: selectValue,
      child: Wrap(runAlignment: WrapAlignment.center, children: [
        Text(selectValue ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const Icon(Icons.arrow_drop_down, size: 20)
      ]),
      onSelected: (String value) {
        setState(() {
          widget.onSelected.call(value);
          selectValue = value;
        });
      },
      itemBuilder: (BuildContext context) {
        return widget.items
            .map((it) =>
                PopupMenuItem<String>(height: 35, value: it, child: Text(it, style: const TextStyle(fontSize: 12))))
            .toList();
      },
    );
  }
}
