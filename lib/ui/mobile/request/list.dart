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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/desktop/request/model/search_model.dart';
import 'package:proxypin/ui/mobile/request/domians.dart';
import 'package:proxypin/ui/mobile/request/request_sequence.dart';
import 'package:proxypin/utils/har.dart';
import 'package:proxypin/utils/listenable_list.dart';
import 'package:share_plus/share_plus.dart';

/// 请求列表
/// @author wanghongen
class RequestListWidget extends StatefulWidget {
  final ProxyServer proxyServer;
  final ListenableList<HttpRequest>? list;

  const RequestListWidget({super.key, required this.proxyServer, this.list});

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

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    if (widget.list != null) {
      container = widget.list!;
    }
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
                  onRemove: sequenceRemove),
              DomainList(
                  key: domainListKey, list: container, proxyServer: widget.proxyServer, onRemove: domainListRemove),
            ],
          ),
        ));
  }

  ///添加请求
  add(Channel channel, HttpRequest request) {
    container.add(request);
    requestSequenceKey.currentState?.add(request);
    domainListKey.currentState?.add(request);
  }

  ///添加响应
  addResponse(ChannelContext channelContext, HttpResponse response) {
    requestSequenceKey.currentState?.addResponse(response);
    domainListKey.currentState?.addResponse(response);
  }

  ///移除
  domainListRemove(List<HttpRequest> list) {
    container.removeWhere((element) => list.contains(element));
    requestSequenceKey.currentState?.remove(list);
  }

  ///全部请求删除
  sequenceRemove(List<HttpRequest> list) {
    container.removeWhere((element) => list.contains(element));
    domainListKey.currentState?.remove(list);
  }

  search(SearchModel searchModel) {
    requestSequenceKey.currentState?.search(searchModel);
    domainListKey.currentState?.search(searchModel.keyword?.trim());
  }

  Iterable<HttpRequest>? currentView() {
    return requestSequenceKey.currentState?.currentView();
  }

  ///清理
  clean() {
    setState(() {
      container.clear();
      domainListKey.currentState?.clean();
      requestSequenceKey.currentState?.clean();
    });
  }

  ///清理早期数据
  cleanupEarlyData(int retain) {
    var list = container.source;
    if (list.length <= retain) {
      return;
    }

    container.removeRange(0, list.length - retain);

    domainListKey.currentState?.clean();
    requestSequenceKey.currentState?.clean();
  }

  //导出har
  export(String title) async {
    //文件名称
    String fileName =
        '${title.contains("ProxyPin") ? '' : 'ProxyPin'}$title.har'.replaceAll(" ", "_").replaceAll(":", "_");
    //获取请求
    var view = currentView()!;
    var json = await Har.writeJson(view.toList(), title: title);
    var file = XFile.fromData(utf8.encode(json), name: fileName, mimeType: "har");
    Share.shareXFiles([file], fileNameOverrides: [fileName]);
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
