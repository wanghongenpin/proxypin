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

import 'dart:collection';

import 'package:date_format/date_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/ui/component/model/search_model.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';
import 'package:proxypin/ui/component/request_tree.dart';
import 'package:proxypin/ui/component/request_tree_view.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/desktop/request/request.dart' show RequestSelectionHandlers;
import 'package:proxypin/ui/mobile/request/request.dart';
import 'package:proxypin/ui/mobile/request/request_sequence.dart';
import 'package:proxypin/utils/export_request.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/listenable_list.dart';

///域名列表
///@author wanghongen
class DomainList extends StatefulWidget {
  final ListenableList<HttpRequest> list;
  final ProxyServer proxyServer;
  final Function(List<HttpRequest>)? onRemove;
  final VoidCallback? onInitialized; // 初始化完成回调
  final MultiSelectController selectionController;

  const DomainList(
      {super.key,
      required this.list,
      required this.proxyServer,
      required this.selectionController,
      this.onRemove,
      this.onInitialized});

  @override
  State<StatefulWidget> createState() {
    return DomainListState();
  }
}

class DomainListState extends State<DomainList> with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  GlobalKey<RequestSequenceState> requestSequenceKey = GlobalKey<RequestSequenceState>();
  late Configuration configuration;

  //域名和对应请求列表的映射
  Map<HostAndPort, List<HttpRequest>> containerMap = {};

  //域名列表 为了维护插入顺序
  LinkedHashSet<HostAndPort> domainList = LinkedHashSet<HostAndPort>();

  //显示的域名 最新的在顶部
  List<HostAndPort> view = [];

  HostAndPort? showHostAndPort;

  //域名匹配函数；为 null 表示当前没有搜索条件
  bool Function(String)? _domainMatcher;

  bool changing = false;

  bool sortDesc = true;

  ///列表/树形展示模式
  ///展示模式直接读配置里的那份，设置页改了这里立刻生效
  RequestViewMode get viewMode => AppConfiguration.current?.requestViewMode.value ?? RequestViewMode.list;

  ///树形节点展开状态，域名本身也用同一份状态，键是域名
  final RequestTreeExpansion treeExpansion = RequestTreeExpansion();

  ///树形模式下请求id对应的响应刷新回调
  final Map<String, VoidCallback> responseCallbacks = {};

  bool get isTreeMode => viewMode == RequestViewMode.tree;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  initState() {
    super.initState();
    configuration = widget.proxyServer.configuration;
    //设置页里改了展示模式，这里跟着刷新
    AppConfiguration.current?.requestViewMode.addListener(_onViewModeChanged);
    initFromContainer();

    // 通知父组件初始化完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onInitialized?.call();
    });
  }

  void initFromContainer() {
    for (var request in widget.list) {
      var hostAndPort = request.hostAndPort!;
      domainList.add(hostAndPort);
      var list = containerMap[hostAndPort] ??= [];
      list.add(request);
    }

    view = domainList.toList();
  }

  void add(HttpRequest request) {
    var hostAndPort = request.hostAndPort!;
    domainList.remove(hostAndPort);
    domainList.add(hostAndPort);

    var list = containerMap[hostAndPort] ??= [];
    list.add(request);
    if (showHostAndPort == request.hostAndPort) {
      requestSequenceKey.currentState?.add(request);
    }

    if (!filter(request.hostAndPort!)) {
      return;
    }

    view = [...domainList.where(filter)].reversed.toList();
    changeState();
  }

  void addResponse(HttpResponse response) {
    HostAndPort? hostAndPort = response.request!.hostAndPort;
    if (response.isWebSocket) {
      add(response.request!);
    }

    //树形模式下请求行直接挂在本页面上，需要自己驱动刷新
    responseCallbacks.remove(response.request?.requestId)?.call();

    if (showHostAndPort == hostAndPort) {
      requestSequenceKey.currentState?.addResponse(response);
    }
  }

  ///展开全部节点，包含域名本身
  void expandAll() {
    treeExpansion.expandAll();
  }

  ///收起全部节点
  void collapseAll() {
    treeExpansion.collapseAll();
  }

  void clean() {
    setState(() {
      view.clear();
      domainList.clear();
      containerMap.clear();
      responseCallbacks.clear();

      initFromContainer();
    });
  }

  void remove(List<HttpRequest> list) {
    for (var request in list) {
      containerMap[request.hostAndPort]?.remove(request);
      responseCallbacks.remove(request.requestId);
      if (containerMap[request.hostAndPort]?.isEmpty ?? false) {
        domainList.remove(request.hostAndPort);
        view.remove(request.hostAndPort);
      }
    }

    setState(() {});
  }

  ///搜索域名
  void search(SearchModel? searchModel) {
    final keyword = searchModel?.keyword?.trim();
    if (searchModel == null || keyword == null || keyword.isEmpty) {
      _domainMatcher = null;
      setState(() {
        view = List.of(domainList.toList().reversed);
      });
      return;
    }

    _domainMatcher = searchModel.buildMatcher();
    view = List.of(domainList.where(filter).toList().reversed);
    changeState();
  }

  ///排序
  void sort(bool desc) {
    sortDesc = desc;
  }

  bool filter(HostAndPort hostAndPort) {
    final matcher = _domainMatcher;
    if (matcher == null) {
      return true;
    }
    return matcher(hostAndPort.domain);
  }

  void changeState() {
    //防止频繁刷新
    if (!changing) {
      changing = true;
      Future.delayed(const Duration(milliseconds: 350), () {
        setState(() {
          changing = false;
        });
      });
    }
  }

  @override
  bool get wantKeepAlive => true;

  void _onViewModeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    AppConfiguration.current?.requestViewMode.removeListener(_onViewModeChanged);
    _scrollController.dispose();
    treeExpansion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scrollbar(
        controller: _scrollController,
        child: ListView.separated(
            controller: _scrollController,
            padding: EdgeInsets.zero,
            separatorBuilder: (context, index) =>
                Divider(thickness: 0.2, height: 0.5, color: Theme.of(context).dividerColor),
            itemCount: view.length,
            itemBuilder: (ctx, index) => isTreeMode ? treeTitle(index) : title(index)));
  }

  Widget title(int index) {
    var value = containerMap[view.elementAt(index)];
    var time = value == null ? '' : formatDate(value.last.requestTime, [m, '/', d, ' ', HH, ':', nn, ':', ss]);

    return ListTile(
        visualDensity: const VisualDensity(vertical: -4),
        title: Text(view.elementAt(index).domain, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        subtitle: Text(localizations.domainListSubtitle(value?.length ?? '', time),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        onLongPress: () => menu(index),
        // show menus
        contentPadding: const EdgeInsets.only(left: 10),
        onTap: () => openDomain(index));
  }

  ///树形模式下的域名行，点击展开路径树，右侧箭头仍然打开原来的请求列表页
  Widget treeTitle(int index) {
    var hostAndPort = view.elementAt(index);
    var requests = containerMap[hostAndPort] ?? const <HttpRequest>[];
    var time = requests.isEmpty ? '' : formatDate(requests.last.requestTime, [m, '/', d, ' ', HH, ':', nn, ':', ss]);

    return ListenableBuilder(
        listenable: treeExpansion,
        builder: (context, _) {
          var expanded = treeExpansion.isExpanded(hostAndPort.domain);

          return Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                visualDensity: const VisualDensity(vertical: -4),
                minLeadingWidth: 25,
                horizontalTitleGap: 0,
                leading: Icon(expanded ? Icons.arrow_drop_down : Icons.arrow_right, size: 22),
                title: Text(hostAndPort.domain, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(localizations.domainListSubtitle(requests.length, time),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: localizations.requestViewList,
                    onPressed: () => openDomain(index)),
                onLongPress: () => menu(index),
                contentPadding: const EdgeInsets.only(left: 6, right: 4),
                onTap: () => treeExpansion.toggle(hostAndPort.domain)),
            if (expanded) treeBody(hostAndPort, requests),
          ]);
        });
  }

  ///域名下按路径分段的请求树
  Widget treeBody(HostAndPort hostAndPort, List<HttpRequest> requests) {
    var ordered = sortDesc ? requests.reversed.toList() : requests;

    //请求行上显示的序号，始终按抓包先后计算
    var displayIndex = <String, int>{};
    for (var i = 0; i < requests.length; i++) {
      displayIndex[requests[i].requestId] = i + 1;
    }

    return RequestTreeView(
        root: RequestTree.build(hostAndPort.domain, ordered),
        expansion: treeExpansion,
        leafBuilder: (request, style) => RequestRow(
            key: ValueKey(request.requestId),
            index: displayIndex[request.requestId] ?? 0,
            request: request,
            proxyServer: widget.proxyServer,
            displayDomain: false,
            treeStyle: style,
            selectionController: widget.selectionController,
            selectionHandlers: const RequestSelectionHandlers(),
            onMount: (callback) => responseCallbacks[request.requestId] = callback,
            onRemove: (item) {
              widget.onRemove?.call([item]);
              remove([item]);
            }));
  }

  ///打开域名下的请求列表页
  void openDomain(int index) {
    Navigator.push(context, MaterialPageRoute(builder: (context) {
      showHostAndPort = view.elementAt(index);
      var list = containerMap[view.elementAt(index)];

      return Scaffold(
          appBar: AppBar(title: Text(view.elementAt(index).domain, style: const TextStyle(fontSize: 16))),
          body: RequestSequence(
            key: requestSequenceKey,
            displayDomain: false,
            container: ListenableList(sortDesc ? list : list?.reversed.toList()),
            sortDesc: sortDesc,
            onRemove: (requests) {
              widget.onRemove?.call(requests);
              remove(requests);
            },
            proxyServer: widget.proxyServer,
            selectionController: MultiSelectController(),
          ));
    }));
  }

  void scrollToTop() {
    _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  ///菜单
  void menu(int index) {
    var hostAndPort = view.elementAt(index);

    showModalBottomSheet(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        context: context,
        enableDrag: true,
        builder: (ctx) {
          return Wrap(
            alignment: WrapAlignment.center,
            children: [
              BottomSheetItem(
                  text: localizations.copyHost,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: hostAndPort.host));
                    FlutterToastr.show(localizations.copied, context);
                  }),
              const Divider(thickness: 0.5, height: 5),
              BottomSheetItem(
                  text: localizations.addBlacklist,
                  onPressed: () {
                    HostFilter.blacklist.add(hostAndPort.host);
                    configuration.flushConfig();
                    FlutterToastr.show(localizations.addSuccess, context);
                  }),
              const Divider(thickness: 0.5, height: 5),
              BottomSheetItem(
                  text: localizations.addWhitelist,
                  onPressed: () {
                    HostFilter.whitelist.add(hostAndPort.host);
                    configuration.flushConfig();
                    FlutterToastr.show(localizations.addSuccess, context);
                  }),
              const Divider(thickness: 0.5, height: 5),
              BottomSheetItem(
                  text: localizations.deleteWhitelist,
                  onPressed: () {
                    HostFilter.whitelist.remove(hostAndPort.host);
                    configuration.flushConfig();
                    FlutterToastr.show(localizations.deleteSuccess, context);
                  }),
              const Divider(thickness: 0.5, height: 5),
              BottomSheetItem(
                  text: localizations.repeatDomainRequests,
                  onPressed: () {
                    repeatDomainRequests(hostAndPort);
                  }),
              const Divider(thickness: 0.5, height: 5),
              BottomSheetItem(
                  text: localizations.exportDomainHar,
                  onPressed: () {
                    exportDomainHar(hostAndPort);
                  }),
              const Divider(thickness: 0.5, height: 5),
              BottomSheetItem(
                  text: localizations.delete,
                  onPressed: () {
                    setState(() {
                      var requests = containerMap.remove(hostAndPort);
                      domainList.remove(hostAndPort);
                      view.removeAt(index);
                      if (requests != null) {
                        widget.onRemove?.call(requests);
                      }
                      FlutterToastr.show(localizations.deleteSuccess, context);
                    });
                  }),
              Container(
                color: Theme.of(context).hoverColor,
                height: 8,
              ),
              TextButton(
                child: Container(
                    height: 45,
                    width: double.infinity,
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(localizations.cancel, textAlign: TextAlign.center)),
                onPressed: () {
                  Navigator.of(ctx).pop();
                },
              ),
            ],
          );
        });
  }

  //重复域名下请求
  void repeatDomainRequests(HostAndPort hostAndPort) async {
    var requests = containerMap[hostAndPort];
    if (requests == null) return;

    for (var httpRequest in requests.toList()) {
      var request = httpRequest.copy(uri: httpRequest.requestUrl);
      var proxyInfo = widget.proxyServer.isRunning ? ProxyInfo.of("127.0.0.1", widget.proxyServer.port) : null;
      try {
        await HttpClients.proxyRequest(request, proxyInfo: proxyInfo);
        if (mounted) FlutterToastr.show(localizations.reSendRequest, rootNavigator: true, context);
      } catch (e) {
        if (mounted) FlutterToastr.show('${localizations.fail}$e', rootNavigator: true, context);
      }
    }
  }

  Future<void> exportDomainHar(HostAndPort hostAndPort) async {
    var requests = containerMap[hostAndPort] ?? [];
    if (requests.isEmpty) {
      if (mounted) FlutterToastr.show(localizations.emptyData, context);
      return;
    }

    var folderName = _domainFileName(hostAndPort, '').replaceAll('.', '');
    showExportDialog(context, requests, folderName);
  }

  String _domainFileName(HostAndPort hostAndPort, String extension) {
    var suffix = (hostAndPort.port == 80 || hostAndPort.port == 443) ? '' : '_${hostAndPort.port}';
    var safeDomain = '${hostAndPort.host}$suffix'.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safeDomain.isEmpty) {
      safeDomain = 'domain';
    }
    return 'proxypin_${safeDomain}_${DateTime.now().dateFormat()}.$extension';
  }
}
