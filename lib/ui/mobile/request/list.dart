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
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';
import 'package:proxypin/ui/mobile/request/domians.dart';
import 'package:proxypin/ui/mobile/request/request.dart';
import 'package:proxypin/ui/mobile/request/request_sequence.dart';
import 'package:proxypin/utils/export_request.dart';
import 'package:proxypin/utils/listenable_list.dart';

import '../../component/model/search_model.dart';

/// 请求列表
/// @author wanghongen
class RequestListWidget extends StatefulWidget {
  final ProxyServer proxyServer;
  final ListenableList<HttpRequest>? list;
  final MultiSelectController selectionController;

  const RequestListWidget({super.key, required this.proxyServer, this.list, required this.selectionController});

  @override
  State<StatefulWidget> createState() {
    return RequestListState();
  }
}

class RequestListState extends State<RequestListWidget> {
  final GlobalKey<RequestSequenceState> requestSequenceKey = GlobalKey<RequestSequenceState>();
  final GlobalKey<DomainListState> domainListKey = GlobalKey<DomainListState>();

  //请求列表容器
  ListenableList<HttpRequest> container = ListenableList();

  //当前搜索模型
  SearchModel? _currentSearchModel;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    if (widget.list != null) {
      container = widget.list!;
    }
  }

  @override
  void dispose() {
    RequestRowState.removeAutoReadByIds(container.map((request) => request.requestId));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> tabs = [Tab(child: Text(localizations.sequence)), Tab(child: Text(localizations.domainList))];

    //double click scroll to top
    var tabClickHandles = [
      DoubleClickHandle(handle: () => requestSequenceKey.currentState?.scrollToTop()),
      DoubleClickHandle(handle: () => domainListKey.currentState?.scrollToTop())
    ];

    return DefaultTabController(
        length: tabs.length,
        child: Scaffold(
          appBar: AppBar(
              title: TabBar(tabs: tabs, onTap: (index) => tabClickHandles[index].call()),
              automaticallyImplyLeading: false),
          body: TabBarView(
            children: [
              RequestSequence(
                  key: requestSequenceKey,
                  container: container,
                  proxyServer: widget.proxyServer,
                  onRemove: sequenceRemove,
                  selectionController: widget.selectionController),
              DomainList(
                  key: domainListKey,
                  list: container,
                  proxyServer: widget.proxyServer,
                  onRemove: domainListRemove,
                  onInitialized: () {
                    if (_currentSearchModel != null && _currentSearchModel!.isNotEmpty) {
                      domainListKey.currentState?.search(_currentSearchModel!);
                    }
                  }),
            ],
          ),
        ));
  }

  ///添加请求
  void add(Channel channel, HttpRequest request) {
    container.add(request);
    requestSequenceKey.currentState?.add(request);
    domainListKey.currentState?.add(request);
  }

  ///添加响应
  void addResponse(ChannelContext channelContext, HttpResponse response) {
    requestSequenceKey.currentState?.addResponse(response);
    domainListKey.currentState?.addResponse(response);
  }

  ///移除
  void domainListRemove(List<HttpRequest> list) {
    container.removeWhere((element) => list.contains(element));
    requestSequenceKey.currentState?.remove(list);
    RequestRowState.removeAutoReadByIds(list.map((request) => request.requestId));
  }

  ///全部请求删除
  void sequenceRemove(List<HttpRequest> list) {
    container.removeWhere((element) => list.contains(element));
    domainListKey.currentState?.remove(list);
    RequestRowState.removeAutoReadByIds(list.map((request) => request.requestId));
  }

  void search(SearchModel searchModel) {
    _currentSearchModel = searchModel; // 保存当前搜索状态
    requestSequenceKey.currentState?.search(searchModel);
    domainListKey.currentState?.search(searchModel);
  }

  Iterable<HttpRequest>? currentView() {
    return requestSequenceKey.currentState?.currentView();
  }

  ///清理
  void clean() {
    setState(() {
      RequestRowState.removeAutoReadByIds(container.map((request) => request.requestId));
      container.clear();
      domainListKey.currentState?.clean();
      requestSequenceKey.currentState?.clean();
    });
  }

  ///清理早期数据
  void cleanupEarlyData(int retain) {
    var list = container.source;
    if (list.length <= retain) {
      return;
    }

    var removeRange = container.removeRange(0, list.length - retain);

    domainListKey.currentState?.clean();
    requestSequenceKey.currentState?.clean();
    RequestRowState.removeAutoReadByIds(removeRange.map((request) => request.requestId));
  }

  //导出har或文件夹
  Future<void> export(BuildContext context, String title) async {
    var view = currentView()!;
    var folderName = '${title.contains("ProxyPin") ? '' : 'ProxyPin'}$title'.replaceAll(" ", "_").replaceAll(":", "_");

    showExportDialog(context, view.toList(), folderName);
  }

  void sort(bool sortDesc) {
    requestSequenceKey.currentState?.sort(sortDesc);
    domainListKey.currentState?.sort(sortDesc);
  }
}

class DoubleClickHandle {
  int tabClickTime = 0;
  final Function()? handle;

  DoubleClickHandle({this.handle});

  void call() {
    if (handle == null) {
      return;
    }

    if (DateTime.now().millisecondsSinceEpoch - tabClickTime < 500) {
      handle?.call();
    }
    tabClickTime = DateTime.now().millisecondsSinceEpoch;
  }
}
