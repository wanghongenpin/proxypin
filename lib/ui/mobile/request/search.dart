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
import 'package:proxypin/ui/desktop/request/model/search_model.dart';
import 'package:proxypin/ui/desktop/request/search_condition.dart';

class MobileSearch extends StatefulWidget {
  final Function(SearchModel searchModel)? onSearch;
  final bool showSearch;

  const MobileSearch({super.key, this.onSearch, this.showSearch = false});

  @override
  State<StatefulWidget> createState() {
    return MobileSearchState();
  }
}

class MobileSearchState extends State<MobileSearch> {
  SearchModel searchModel = SearchModel();
  bool _searched = false;
  final TextEditingController _keywordController = TextEditingController();
  bool _changing = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.showSearch) {
        showSearch();
      }
    });
  }

  @override
  dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.only(left: 20),
        child: TextFormField(
            controller: _keywordController,
            textAlignVertical: TextAlignVertical.center,
            cursorHeight: 20,
            keyboardType: TextInputType.url,
            onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
            onChanged: (val) {
              searchModel.keyword = val;
              if (!_changing) {
                _changing = true;
                Future.delayed(const Duration(milliseconds: 500), () {
                  _changing = false;
                  if (!_searched) {
                    searchModel.searchOptions = {Option.url, Option.method, Option.responseContentType};
                  }
                  widget.onSearch?.call(searchModel);
                });
              }
            },
            decoration: InputDecoration(
                border: InputBorder.none,
                prefixIcon: InkWell(
                    onTap: showSearch,
                    child: Icon(Icons.search, color: _searched ? Colors.green : Theme.of(context).colorScheme.primary)),
                hintText: 'Search')));
  }

  showSearch() {
    showModalBottomSheet(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        isScrollControlled: true,
        context: context,
        builder: (context) {
          if (!_searched) {
            searchModel.searchOptions = {Option.url};
          }
          return Padding(
              padding: MediaQuery.of(context).viewInsets,
              child: SizedBox(
                  height: 430,
                  child: SearchConditions(
                    padding: const EdgeInsets.only(left: 15, right: 15, top: 10),
                    searchModel: searchModel,
                    onSearch: (val) {
                      setState(() {
                        searchModel = val;
                        _searched = searchModel.isNotEmpty;
                        _keywordController.text = searchModel.keyword ?? '';
                        widget.onSearch?.call(searchModel);
                      });
                    },
                  )));
        });
  }
}
