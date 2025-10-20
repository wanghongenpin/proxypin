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
import 'package:proxypin/utils/lang.dart';

import 'model/search_model.dart';

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
    Color primaryColor = Theme.of(context).colorScheme.primary;
    return Container(
      padding: widget.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // keyword
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
                    icon: Text('Aa',
                        style: TextStyle(
                            fontWeight: FontWeight.w500, color: searchModel.caseSensitive.value ? primaryColor : null)),
                    onPressed: () {
                      searchModel.caseSensitive.value = !searchModel.caseSensitive.value;
                    },
                  )),
            ),
          ),
          const SizedBox(height: 10),
          // protocol quick selectors placed under the keyword input (very compact)
          protocolsWidget(),
          const SizedBox(height: 10),
          // keyword scope
          Text(localizations.keywordSearchScope),
          const SizedBox(height: 10),
          Wrap(
            children: [
              options('URL', Option.url),
              options(localizations.requestHeader, Option.requestHeader),
              options(localizations.requestBody, Option.requestBody),
              options(localizations.responseHeader, Option.responseHeader),
              options(localizations.responseBody, Option.responseBody),
            ],
          ),
          const SizedBox(height: 10),

          // request method
          row(
            Text('${localizations.requestMethod}:'),
            DropdownMenu(
              initialValue: searchModel.requestMethod?.name ?? localizations.all,
              items: HttpMethod.methods().map((e) => e.name).toList()..insert(0, localizations.all),
              onSelected: (String value) {
                searchModel.requestMethod = value == localizations.all ? null : HttpMethod.valueOf(value);
              },
            ),
          ),
          const SizedBox(height: 10),
          // request type
          row(
            Text('${localizations.requestType}:'),
            DropdownMenu(
              initialValue: Maps.getKey(requestContentMap, searchModel.requestContentType) ?? localizations.all,
              items: requestContentMap.keys,
              onSelected: (String value) {
                searchModel.requestContentType = requestContentMap[value];
              },
            ),
          ),
          const SizedBox(height: 10),

          // response type
          row(
            Text('${localizations.responseType}:'),
            DropdownMenu(
              initialValue: Maps.getKey(responseContentMap, searchModel.responseContentType) ?? localizations.all,
              items: responseContentMap.keys,
              onSelected: (String value) {
                searchModel.responseContentType = responseContentMap[value];
              },
            ),
          ),
          const SizedBox(height: 10),

          // status code range
          row(
            Text('${localizations.statusCode}: '),
            Row(children: [
              SizedBox(
                  width: 55,
                  height: 32,
                  child: textField(
                      initialValue: searchModel.statusCodeFrom?.toString(),
                      onChanged: (val) => searchModel.statusCodeFrom = int.tryParse(val))),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 5), child: Text(" - ")),
              SizedBox(
                  width: 55,
                  height: 32,
                  child: textField(
                      initialValue: searchModel.statusCodeTo?.toString(),
                      onChanged: (val) => searchModel.statusCodeTo = int.tryParse(val))),
            ]),
          ),
          const SizedBox(height: 10),

          // duration range (ms)
          row(
            Text('${localizations.duration} (ms): '),
            Row(children: [
              SizedBox(
                  width: 55,
                  height: 32,
                  child: textField(
                      initialValue: searchModel.durationFromMs?.toString(),
                      onChanged: (val) => searchModel.durationFromMs = int.tryParse(val))),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 5), child: Text(" - ")),
              SizedBox(
                  width: 55,
                  height: 32,
                  child: textField(
                      initialValue: searchModel.durationToMs?.toString(),
                      onChanged: (val) => searchModel.durationToMs = int.tryParse(val))),
            ]),
          ),
          const SizedBox(height: 15),

          // action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(localizations.cancel, style: const TextStyle(fontSize: 14)),
              ),
              TextButton(
                onPressed: () {
                  widget.onSearch?.call(SearchModel());
                  Navigator.pop(context);
                },
                child: Text(localizations.clearSearch, style: const TextStyle(fontSize: 14)),
              ),
              TextButton(
                onPressed: () {
                  widget.onSearch?.call(searchModel);
                  Navigator.pop(context);
                },
                child: Text(localizations.confirm, style: const TextStyle(fontSize: 14)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget protocolsWidget() {
    Color primaryColor = Theme.of(context).colorScheme.primary;
    return Wrap(
      spacing: 5,
      runSpacing: 2,
      children: <Widget>[
        FilterChip(
          label: const Text('HTTP'),
          selected: searchModel.protocols.contains(Protocol.http),
          showCheckmark: false,
          selectedColor: primaryColor.withOpacity(0.12),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          labelStyle: const TextStyle(fontSize: 12),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
          onSelected: (sel) => setState(() {
            sel ? searchModel.protocols.add(Protocol.http) : searchModel.protocols.remove(Protocol.http);
          }),
        ),
        FilterChip(
          label: const Text('HTTPS'),
          selected: searchModel.protocols.contains(Protocol.https),
          showCheckmark: false,
          selectedColor: primaryColor.withOpacity(0.12),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          labelStyle: const TextStyle(fontSize: 12),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
          onSelected: (sel) => setState(() {
            sel ? searchModel.protocols.add(Protocol.https) : searchModel.protocols.remove(Protocol.https);
          }),
        ),
        FilterChip(
          label: const Text('WS'),
          selected: searchModel.protocols.contains(Protocol.ws),
          showCheckmark: false,
          selectedColor: primaryColor.withOpacity(0.12),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          labelStyle: const TextStyle(fontSize: 12),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
          onSelected: (sel) => setState(() {
            sel ? searchModel.protocols.add(Protocol.ws) : searchModel.protocols.remove(Protocol.ws);
          }),
        ),
        FilterChip(
          label: const Text('HTTP/1'),
          selected: searchModel.protocols.contains(Protocol.http1),
          showCheckmark: false,
          selectedColor: primaryColor.withOpacity(0.12),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          labelStyle: const TextStyle(fontSize: 12),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
          onSelected: (sel) => setState(() {
            sel ? searchModel.protocols.add(Protocol.http1) : searchModel.protocols.remove(Protocol.http1);
          }),
        ),
        FilterChip(
          label: const Text('H2'),
          selected: searchModel.protocols.contains(Protocol.h2),
          showCheckmark: false,
          selectedColor: primaryColor.withOpacity(0.12),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          labelStyle: const TextStyle(fontSize: 12),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
          onSelected: (sel) => setState(() {
            sel ? searchModel.protocols.add(Protocol.h2) : searchModel.protocols.remove(Protocol.h2);
          }),
        ),
      ],
    );
  }

  Widget options(String title, Option option) {
    bool isCN = localizations.localeName == 'zh';
    return Container(
        constraints: BoxConstraints(maxWidth: isCN ? 100 : 132, minWidth: 100, maxHeight: 33),
        child: Row(children: [
          Text(title, style: const TextStyle(fontSize: 12)),
          Checkbox(
              visualDensity: VisualDensity.compact,
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [Expanded(flex: 4, child: child), Expanded(flex: 6, child: child2)]);
  }

  Widget textField({String? initialValue, final ValueChanged<String>? onChanged, TextStyle? style}) {
    Color color = Theme.of(context).colorScheme.primary;

    return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 32),
        child: TextFormField(
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
          initialValue: initialValue,
          onChanged: onChanged,
          style: style,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.only(left: 10, right: 10, top: 2, bottom: 2),
            border: OutlineInputBorder(borderSide: BorderSide(width: 1, color: color.withOpacity(0.3))),
          ),
        ));
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
