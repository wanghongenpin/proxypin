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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/content/panel.dart';
import 'package:proxypin/ui/desktop/request/model/search_model.dart';
import 'package:proxypin/ui/desktop/request/request_sequence.dart';
import 'package:proxypin/ui/desktop/request/search.dart';
import 'package:proxypin/utils/har.dart';
import 'package:proxypin/utils/listenable_list.dart';

import 'domians.dart';

/// @author wanghongen
class DesktopRequestListWidget extends StatefulWidget {
  final ProxyServer proxyServer;
  final ListenableList<HttpRequest>? list;
  final NetworkTabController panel;

  const DesktopRequestListWidget({super.key, required this.proxyServer, this.list, required this.panel});

  @override
  State<StatefulWidget> createState() {
    return DesktopRequestListState();
  }
}

class DesktopRequestListState extends State<DesktopRequestListWidget> with AutomaticKeepAliveClientMixin {
  final GlobalKey<RequestSequenceState> requestSequenceKey = GlobalKey<RequestSequenceState>();
  final GlobalKey<DomainWidgetState> domainListKey = GlobalKey<DomainWidgetState>();

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
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    List<Tab> tabs = [
      Tab(child: Text(localizations.domainList, style: const TextStyle(fontSize: 13))),
      Tab(child: Text(localizations.sequence, style: const TextStyle(fontSize: 13))),
    ];

    return DefaultTabController(
        length: tabs.length,
        child: Scaffold(
            appBar: AppBar(
                toolbarHeight: 40,
                title: SizedBox(height: 40, child: TabBar(tabs: tabs)),
                automaticallyImplyLeading: false),
            bottomNavigationBar: Search(onSearch: search),
            body: Padding(
                padding: const EdgeInsets.only(right: 5),
                child: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [
                  DomainList(
                      key: domainListKey,
                      list: container,
                      panel: widget.panel,
                      proxyServer: widget.proxyServer,
                      onRemove: domainListRemove),
                  RequestSequence(
                      key: requestSequenceKey,
                      container: container,
                      proxyServer: widget.proxyServer,
                      onRemove: sequenceRemove),
                ]))));
  }

  ///添加请求
  add(Channel channel, HttpRequest request) {
    container.add(request);
    domainListKey.currentState?.add(channel, request);
    requestSequenceKey.currentState?.add(request);
  }

  ///添加响应
  addResponse(ChannelContext channelContext, HttpResponse response) {
    domainListKey.currentState?.addResponse(channelContext, response);
    requestSequenceKey.currentState?.addResponse(response);
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
    domainListKey.currentState?.search(searchModel);
    requestSequenceKey.currentState?.search(searchModel);
  }

  List<HttpRequest>? currentView() {
    return domainListKey.currentState?.currentView();
  }

  ///清理
  clean() {
    setState(() {
      container.clear();
      domainListKey.currentState?.clean();
      requestSequenceKey.currentState?.clean();
      widget.panel.change(null, null);
    });
  }

  cleanupEarlyData(int retain) {
    var list = container.source;
    if (list.length <= retain) {
      return;
    }

    container.removeRange(0, list.length - retain);

    domainListKey.currentState?.clean();
    requestSequenceKey.currentState?.clean();
  }

  ///导出
  export(String fileName) async {
    var path = await FilePicker.platform.saveFile(fileName: fileName);
    if (path == null) {
      return;
    }

    //获取请求
    List<HttpRequest>? requests = currentView();
    if (requests == null) return;

    var file = await File(path).create();
    await Har.writeFile(requests, file, title: fileName);

    if (mounted) FlutterToastr.show(AppLocalizations.of(context)!.exportSuccess, context);
  }
}
