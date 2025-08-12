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
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/ui/desktop/request/model/search_model.dart';
import 'package:proxypin/ui/desktop/request/search_condition.dart';

/// @author wanghongen
/// 2023/10/8
class Search extends StatefulWidget {
  final Function(SearchModel searchModel)? onSearch;

  const Search({super.key, this.onSearch});

  @override
  State<StatefulWidget> createState() {
    return _SearchState();
  }
}

class _SearchState extends State<Search> {
  SearchModel searchModel = SearchModel();
  bool searched = false;
  TextEditingController keywordController = TextEditingController();
  bool changing = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      width: 300,
      decoration: BoxDecoration(
        color: Theme.of(context).hoverColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: TextField(
        cursorHeight: 22,
        controller: keywordController,
        onChanged: (val) async {
          searchModel.keyword = val;

          if (!changing) {
            changing = true;
            Future.delayed(const Duration(milliseconds: 500), () {
              changing = false;
              if (!searched) {
                searchModel.searchOptions = {Option.url, Option.method, Option.responseContentType};
              }
              widget.onSearch?.call(searchModel);
            });
          }
        },
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.all(0),
          enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade400, width: 0.5), borderRadius: BorderRadius.circular(15)),
          border: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade400, width: 0.5), borderRadius: BorderRadius.circular(15)),
          prefixIcon: InkWell(
              child: Icon(Icons.search, color: searched ? Colors.green : Theme.of(context).colorScheme.primary),
              onTapDown: (details) {
                searchDialog(details);
              }),
          hintText: 'Search',
          suffixIcon: ContentTypeSelect(onSelected: (contentType) {
            searchModel.responseContentType = contentType;
            widget.onSearch?.call(searchModel);
          }),
        ),
      ),
    );
  }

  searchDialog(TapDownDetails details) {
    if (!searched) {
      searchModel.searchOptions = {Option.url};
    }
    bool isCN = AppLocalizations.of(context)!.localeName == 'zh';
    var height = MediaQuery.of(context).size.height;
    height = isCN ? height - 400 : height - 485;
    showMenu(
        context: context,
        position: RelativeRect.fromLTRB(10, height, 10, height),
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 330),
        items: [
          PopupMenuItem(
              padding: const EdgeInsets.only(left: 15, right: 15, top: 10, bottom: 5),
              enabled: false,
              child: DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
                  child: SizedBox(
                      child: SearchConditions(
                          searchModel: searchModel,
                          onSearch: (val) {
                            setState(() {
                              searchModel = val;
                              searched = searchModel.isNotEmpty;
                              keywordController.text = searchModel.keyword ?? '';
                              widget.onSearch?.call(searchModel);
                            });
                          }))))
        ]);
  }
}

class ContentTypeSelect extends StatefulWidget {
  final Function(ContentType? contentType) onSelected;

  const ContentTypeSelect({super.key, required this.onSelected});

  @override
  State<StatefulWidget> createState() {
    return ContentTypeState();
  }
}

class ContentTypeState extends State<ContentTypeSelect> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  String? value;
  List<String>? types;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    value ??= localizations.all;
    types ??= ["JSON", "HTML", "JS", "CSS", "TEXT", "IMAGE", localizations.all];

    return PopupMenuButton(
      initialValue: value,
      offset: Offset(-10, (types!.length - types!.indexOf(value!)) * -30.0 - 10),
      tooltip: localizations.responseType,
      constraints: const BoxConstraints(maxWidth: 75),
      child: Wrap(runAlignment: WrapAlignment.center, children: [
        Text(value!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const Icon(Icons.arrow_drop_up, size: 20)
      ]),
      onSelected: (String value) {
        if (this.value == value) {
          return;
        }
        setState(() {
          this.value = value;
        });
        widget.onSelected(value == localizations.all ? null : ContentType.valueOf(value));
      },
      itemBuilder: (BuildContext context) {
        return types!.map(item).toList();
      },
    );
  }

  PopupMenuItem<String> item(String value) {
    return PopupMenuItem(
      height: 30,
      value: value,
      child: Text(value, style: const TextStyle(fontSize: 12)),
    );
  }
}
