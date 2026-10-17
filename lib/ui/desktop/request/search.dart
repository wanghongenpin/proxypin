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
import 'package:proxypin/ui/component/search_condition.dart';

import '../../component/model/search_model.dart';

/// 列表头部搜索（设计稿 .list-head）：搜索框 + 类型过滤 Chip
/// @author wanghongen
/// 2023/10/8
class Search extends StatefulWidget {
  final Function(SearchModel searchModel)? onSearch;

  const Search({super.key, this.onSearch});

  @override
  State<StatefulWidget> createState() {
    return SearchState();
  }
}

class SearchState extends State<Search> {
  SearchModel searchModel = SearchModel();
  bool searched = false;
  TextEditingController keywordController = TextEditingController();
  bool changing = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return Container(
        padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 9),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)))),
        child: Column(children: [
          searchBox(theme),
          const SizedBox(height: 8),
          filterChips(theme),
        ]));
  }

  /// 搜索框（设计稿 .search）：高 30 圆角 7，左搜索图标，右漏斗开搜索条件弹窗
  Widget searchBox(ThemeData theme) {
    return SizedBox(
        height: 30,
        child: TextField(
          cursorHeight: 16,
          controller: keywordController,
          style: const TextStyle(fontSize: 12.5),
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
            filled: true,
            fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.05),
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide.none, borderRadius: BorderRadius.circular(7)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.4), width: 0.8),
                borderRadius: BorderRadius.circular(7)),
            prefixIcon: InkWell(
                child: Icon(Icons.search,
                    size: 17, color: searched ? Colors.green : theme.colorScheme.onSurfaceVariant),
                onTapDown: (details) {
                  searchDialog(details);
                }),
            prefixIconConstraints: const BoxConstraints(minWidth: 34),
            hintText: localizations.searchHint,
            hintStyle: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
            suffixIcon: InkWell(
                child: Icon(Icons.filter_list, size: 16, color: theme.colorScheme.onSurfaceVariant),
                onTapDown: (details) {
                  searchDialog(details);
                }),
            suffixIconConstraints: const BoxConstraints(minWidth: 32),
          ),
        ));
  }

  /// 类型过滤 Chip（设计稿 .filters）
  Widget filterChips(ThemeData theme) {
    var chips = <(String, String)>[
      ('all', localizations.all),
      ('xhr', 'XHR'),
      ('jscss', 'JS/CSS'),
      ('image', localizations.image),
      ('ws', 'WebSocket'),
    ];
    return Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (var chip in chips) filterChip(theme, chip.$1, chip.$2)]));
  }

  Widget filterChip(ThemeData theme, String id, String label) {
    var selected = currentChip == id;
    return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChipSelected(id),
        child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: selected ? theme.colorScheme.primary.withValues(alpha: 0.1) : null,
                border: Border.all(
                    color: selected ? Colors.transparent : theme.dividerColor.withValues(alpha: 0.6))),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
                    color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant))));
  }

  /// 当前选中的 Chip（由搜索条件反推，弹窗修改条件后能保持同步）
  String get currentChip {
    if (searchModel.protocols.contains(Protocol.ws)) {
      return 'ws';
    }
    var types = searchModel.responseContentTypes;
    if (types.isEmpty) {
      return 'all';
    }
    if (types.length == 1 && types.contains(ContentType.json)) {
      return 'xhr';
    }
    if (types.length == 2 && types.contains(ContentType.js) && types.contains(ContentType.css)) {
      return 'jscss';
    }
    if (types.length == 1 && types.contains(ContentType.image)) {
      return 'image';
    }
    return 'all';
  }

  void onChipSelected(String id) {
    setState(() {
      searchModel.protocols = {};
      switch (id) {
        case 'xhr':
          searchModel.responseContentTypes = {ContentType.json};
          break;
        case 'jscss':
          searchModel.responseContentTypes = {ContentType.js, ContentType.css};
          break;
        case 'image':
          searchModel.responseContentTypes = {ContentType.image};
          break;
        case 'ws':
          searchModel.responseContentTypes = {};
          searchModel.protocols = {Protocol.ws};
          break;
        default:
          searchModel.responseContentTypes = {};
      }
      searched = searchModel.isNotEmpty;
      widget.onSearch?.call(searchModel);
    });
  }

  void searchDialog([TapDownDetails? details]) {
    if (!searched) {
      searchModel.searchOptions = {Option.url};
    }
    // 从搜索框位置向下弹出
    var box = context.findRenderObject() as RenderBox;
    var offset = box.localToGlobal(Offset.zero);
    showMenu(
        context: context,
        position: RelativeRect.fromLTRB(offset.dx + 12, offset.dy + 36, offset.dx + 12, 0),
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
