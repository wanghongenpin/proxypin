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
import 'package:proxypin/ui/component/utils.dart';

import '../../component/model/search_model.dart';

/// 列表底部搜索：旧版胶囊样式（圆角 20 + 阴影），左搜索图标开条件弹窗，右响应类型下拉
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
    bool dark = theme.brightness == Brightness.dark;
    // 主题适配：亮色沿用旧版 hoverColor 底；暗黑用设计稿 --hover；描边取主题 dividerColor（已注入设计稿 --border）
    var fillColor = dark ? DarkPalette.hover : theme.hoverColor;
    return Material(
        color: fillColor,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        elevation: dark ? 2 : 0.8,
        shadowColor: theme.shadowColor.withValues(alpha: dark ? 0.4 : 0.15),
        child: SizedBox(
          height: 32,
          child: TextField(
            cursorHeight: 18,
            controller: keywordController,
            style: const TextStyle(fontSize: 14),
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
                  borderSide: BorderSide(color: theme.dividerColor, width: 1.5),
                  borderRadius: BorderRadius.circular(15)),
              focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.5), width: 1.8),
                  borderRadius: BorderRadius.circular(15)),
              prefixIcon: IconButton(
                  icon: Icon(Icons.search, size: 20, color: searched ? okColor(theme) : theme.colorScheme.primary),
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 38, minHeight: 32),
                  onPressed: () => searchDialog()),
              hintText: 'Search',
              hintStyle: TextStyle(fontSize: 14, color: theme.colorScheme.onSurfaceVariant),
              suffixIcon: ContentTypeSelect(onSelected: (contentType) {
                setState(() {
                  searchModel.responseContentTypes = contentType == null ? {} : {contentType};
                  searchModel.protocols = {};
                  searched = searchModel.isNotEmpty;
                });
                widget.onSearch?.call(searchModel);
              }),
            ),
          ),
        ));
  }

  void searchDialog() {
    if (!searched) {
      searchModel.searchOptions = {Option.url};
    }
    // 搜索框在列表底部，条件面板需向上弹出。showMenu 只按 position.top 向下排（SDK 无自动上翻），
    // 故用 OverlayEntry 按底边锚定：面板底贴搜索框顶，与面板实际高度无关；窗口过矮时内部滚动。
    var theme = Theme.of(context);
    var box = context.findRenderObject() as RenderBox;
    var offset = box.localToGlobal(Offset.zero);
    var screen = MediaQuery.of(context).size;
    var width = (box.size.width - 24).clamp(260.0, 330.0);

    late OverlayEntry entry;
    entry = OverlayEntry(builder: (overlayContext) {
      return Stack(children: [
        // 点击空白处关闭
        Positioned.fill(
            child: GestureDetector(
                behavior: HitTestBehavior.opaque, onTap: () => entry.remove(), child: const SizedBox.shrink())),
        Positioned(
            left: offset.dx + 12,
            bottom: screen.height - offset.dy + 4,
            width: width,
            child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 120),
                builder: (context, value, child) => Opacity(opacity: value, child: child),
                child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    color: theme.cardColor,
                    shadowColor: theme.shadowColor,
                    child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: offset.dy - 16),
                        child: SingleChildScrollView(
                            child: Padding(
                                padding: const EdgeInsets.only(left: 15, right: 15, top: 10, bottom: 5),
                                child: DefaultTextStyle.merge(
                                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                                    child: SearchConditions(
                                        searchModel: searchModel,
                                        onSearch: (val) {
                                          setState(() {
                                            searchModel = val;
                                            searched = searchModel.isNotEmpty;
                                            keywordController.text = searchModel.keyword ?? '';
                                            widget.onSearch?.call(searchModel);
                                          });
                                        })))))))),
      ]);
    });
    Overlay.of(context).insert(entry);
  }
}

/// 响应类型下拉（旧版 suffix 样式：当前值 + 上箭头，上弹菜单）
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
  Widget build(BuildContext context) {
    value ??= localizations.all;
    types ??= ["JSON", "IMAGE", "HTML", "XML", "JS", "CSS", "TEXT", localizations.all];

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
