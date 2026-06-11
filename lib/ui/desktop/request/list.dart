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
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/content/panel.dart';
import 'package:proxypin/ui/desktop/request/request_sequence.dart';
import 'package:proxypin/ui/desktop/request/request.dart';
import 'package:proxypin/ui/desktop/request/search.dart';
import 'package:proxypin/ui/component/selection_action_bar.dart';
import 'package:proxypin/utils/har.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/listenable_list.dart';

import '../../component/model/search_model.dart';
import 'domains.dart';
import 'package:proxypin/ui/desktop/request/report_servers.dart';

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
  final GlobalKey<SearchState> searchKey = GlobalKey<SearchState>();
  TabController? _tabController;

  //请求列表容器
  ListenableList<HttpRequest> container = ListenableList();

  bool sortDesc = true;

  // 选择控制器
  final MultiSelectController selectionController = MultiSelectController();

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    if (widget.list != null) {
      container = widget.list!;
    }
  }

  bool get isSelectionMode => selectionController.isSelectionMode;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    RequestWidget.removeAutoReadByIds(container.map((request) => request.requestId));
    selectionController.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    List<Tab> tabs = [
      Tab(child: Text(localizations.domainList, style: const TextStyle(fontSize: 13))),
      Tab(child: Text(localizations.sequence, style: const TextStyle(fontSize: 13))),
    ];

    return FocusableActionDetector(
        autofocus: true,
        shortcuts: {
          SingleActivator(LogicalKeyboardKey.escape): const _ClearSelectionIntent(),
        },
        actions: {
          _ClearSelectionIntent: CallbackAction<_ClearSelectionIntent>(onInvoke: (intent) {
            if (_isTextInputFocused()) {
              return null;
            }
            if (isSelectionMode) {
              selectionController.clear();
            }
            return null;
          }),
        },
        child: DefaultTabController(
            length: tabs.length,
            child: Builder(builder: (tabContext) {
              _tabController = DefaultTabController.of(tabContext);
              return Scaffold(
                  appBar: AppBar(
                    toolbarHeight: 40,
                    title: SizedBox(height: 40, child: TabBar(tabs: tabs, dividerColor: Colors.transparent)),
                    automaticallyImplyLeading: false,
                    actions: [popupMenus()],
                  ),
                  bottomNavigationBar: Search(key: searchKey, onSearch: search),
                  body: Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: Column(children: [
                        Obx(() => selectionController.selectionMode.value
                            ? SelectionActionBar(
                                selectionController: selectionController,
                                onRepeat: repeatSelected,
                                onExport: exportSelected,
                                onDelete: deleteSelected)
                            : SizedBox()),
                        Expanded(
                            child: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [
                          DomainList(
                            key: domainListKey,
                            list: container,
                            panel: widget.panel,
                            proxyServer: widget.proxyServer,
                            selectionController: selectionController,
                            selectionHandlers: RequestSelectionHandlers(
                              onRangeSelection: rangeSelectRequest,
                              onDeleteSelected: deleteSelected,
                              onRepeatSelected: repeatSelected,
                              onExportSelected: exportSelected,
                            ),
                            onRemove: domainListRemove,
                          ),
                          RequestSequence(
                            key: requestSequenceKey,
                            container: container,
                            proxyServer: widget.proxyServer,
                            selectionController: selectionController,
                            selectionHandlers: RequestSelectionHandlers(
                              onRangeSelection: rangeSelectRequest,
                              onDeleteSelected: deleteSelected,
                              onRepeatSelected: repeatSelected,
                              onExportSelected: exportSelected,
                            ),
                            onRemove: sequenceRemove,
                          ),
                        ])),
                      ])));
            })));
  }

  bool _isTextInputFocused() {
    return FocusManager.instance.primaryFocus?.context?.widget is EditableText;
  }

  Widget popupMenus() {
    return PopupMenuButton<_RequestListMenuAction>(
        offset: const Offset(0, 32),
        icon: const Icon(Icons.more_vert_outlined, size: 20),
        onSelected: _onMenuSelected,
        itemBuilder: (BuildContext context) {
          return <PopupMenuEntry<_RequestListMenuAction>>[
            _menuItem(_RequestListMenuAction.search,
                icon: const Icon(Icons.search, size: 17), text: localizations.search),
            _menuItem(_RequestListMenuAction.export,
                icon: const Icon(Icons.share, size: 16), text: localizations.viewExport),
            _menuItem(_RequestListMenuAction.repeat,
                icon: const Icon(Icons.repeat, size: 16), text: localizations.repeatAllRequests),
            _menuItem(_RequestListMenuAction.select,
                icon: const Icon(Icons.checklist_outlined, size: 16), text: localizations.selectAction),
            _menuItem(_RequestListMenuAction.sort,
                icon: const Icon(Icons.sort, size: 16),
                text: sortDesc ? localizations.timeAsc : localizations.timeDesc),
            _menuItem(_RequestListMenuAction.report,
                icon: const Icon(Icons.cloud_upload_outlined, size: 16), text: localizations.reportServers),
          ];
        });
  }

  PopupMenuEntry<_RequestListMenuAction> _menuItem(_RequestListMenuAction value,
      {required Icon icon, required String text}) {
    return CustomPopupMenuItem<_RequestListMenuAction>(
        value: value, height: 37, child: IconText(icon: icon, text: text, textStyle: const TextStyle(fontSize: 13)));
  }

  void _onMenuSelected(_RequestListMenuAction action) {
    switch (action) {
      case _RequestListMenuAction.search:
        searchKey.currentState?.searchDialog();
        break;
      case _RequestListMenuAction.export:
        export('ProxyPin_${DateTime.now().dateFormat()}.har');
        break;
      case _RequestListMenuAction.repeat:
        repeatAllRequests();
        break;
      case _RequestListMenuAction.select:
        selectionController.toggleSelectionMode();
        break;
      case _RequestListMenuAction.sort:
        setState(() {
          sortDesc = !sortDesc;
        });
        requestSequenceKey.currentState?.sort(sortDesc);
        domainListKey.currentState?.sort(sortDesc);
        break;
      case _RequestListMenuAction.report:
        showReportServersDialog(context);
        break;
    }
  }

  ///添加请求
  void add(Channel channel, HttpRequest request) {
    container.add(request);
    domainListKey.currentState?.add(channel, request);
    requestSequenceKey.currentState?.add(request);
  }

  ///添加响应
  void addResponse(ChannelContext channelContext, HttpResponse response) {
    domainListKey.currentState?.addResponse(channelContext, response);
    requestSequenceKey.currentState?.addResponse(response);
  }

  void remove(List<HttpRequest> list) {
    container.removeWhere((element) => list.contains(element));
    domainListKey.currentState?.remove(list);
    requestSequenceKey.currentState?.remove(list);
    RequestWidget.removeAutoReadByIds(list.map((request) => request.requestId));
  }

  ///移除
  void domainListRemove(List<HttpRequest> list) {
    container.removeWhere((element) => list.contains(element));
    requestSequenceKey.currentState?.remove(list);
    RequestWidget.removeAutoReadByIds(list.map((request) => request.requestId));
    selectionController.prune(container.map((request) => request.requestId));
  }

  ///全部请求删除
  void sequenceRemove(List<HttpRequest> list) {
    container.removeWhere((element) => list.contains(element));
    domainListKey.currentState?.remove(list);
    RequestWidget.removeAutoReadByIds(list.map((request) => request.requestId));
    selectionController.prune(container.map((request) => request.requestId));
  }

  void search(SearchModel searchModel) {
    domainListKey.currentState?.search(searchModel);
    requestSequenceKey.currentState?.search(searchModel);
  }

  List<HttpRequest>? currentView() {
    return domainListKey.currentState?.currentView();
  }

  ///清理
  void clean() {
    setState(() {
      RequestWidget.removeAutoReadByIds(container.map((request) => request.requestId));
      container.clear();
      domainListKey.currentState?.clean();
      requestSequenceKey.currentState?.clean();
      widget.panel.change(null, null);
      selectionController.clear();
    });
  }

  void cleanupEarlyData(int retain) {
    var list = container.source;
    if (list.length <= retain) {
      return;
    }

    var removeRange = container.removeRange(0, list.length - retain);

    domainListKey.currentState?.clean();
    requestSequenceKey.currentState?.clean();

    RequestWidget.removeAutoReadByIds(removeRange.map((request) => request.requestId));
    selectionController.prune(container.map((request) => request.requestId));
  }

  void deleteSelected() {
    final selectedRequests = domainListKey.currentState?.selectedRequests();
    if (selectedRequests == null || selectedRequests.isEmpty) {
      return;
    }

    showConfirmDialog(context, content: '${localizations.delete} ${selectedRequests.length} ${localizations.request}?',
        onConfirm: () {
      setState(() {
        remove(selectedRequests);
        selectionController.clear();
      });
      if (mounted) {
        FlutterToastr.show(localizations.deleteSuccess, context);
      }
    });
  }

  void rangeSelectRequest(HttpRequest request) {
    switch (_tabController?.index) {
      case 1:
        requestSequenceKey.currentState?.selectRange(request);
        break;
      case 0:
      default:
        domainListKey.currentState?.selectRange(request);
        break;
    }
  }

  void repeatSelected() {
    final selectedRequests = domainListKey.currentState?.selectedRequests();
    _repeatRequests(selectedRequests);
    selectionController.clear();
  }

  Future<void> exportSelected() async {
    final selectedRequests = domainListKey.currentState?.selectedRequests();
    if (selectedRequests == null || selectedRequests.isEmpty) {
      return;
    }

    final fileName = 'ProxyPin_selected_${DateTime.now().dateFormat()}.har';
    _doExport(fileName, selectedRequests);
    selectionController.clear();
  }

  ///导出
  Future<void> export(String fileName) async {
    //获取请求
    List<HttpRequest>? requests = currentView();
    if (requests == null) return;
    _doExport(fileName, requests);
  }

  Future<void> _doExport(String fileName, List<HttpRequest> requests) async {
    var path = await FilePicker.saveFile(fileName: fileName);
    if (path == null) {
      return;
    }
    var file = await File(path).create();
    await Har.writeFile(requests, file, title: fileName);

    if (mounted) FlutterToastr.show(AppLocalizations.of(context)!.exportSuccess, context);
  }

  ///重发所有请求
  void repeatAllRequests() async {
    var requests = currentView();
    _repeatRequests(requests);
  }

  void _repeatRequests(List<HttpRequest>? requests) async {
    if (requests == null) return;

    var localizations = AppLocalizations.of(context);
    final proxyServer = widget.proxyServer;

    for (var request in requests) {
      var httpRequest = request.copy(uri: request.requestUrl);
      var proxyInfo = proxyServer.isRunning ? ProxyInfo.of("127.0.0.1", proxyServer.port) : null;
      try {
        await HttpClients.proxyRequest(httpRequest, proxyInfo: proxyInfo, timeout: const Duration(seconds: 3));
        if (mounted) {
          FlutterToastr.show(localizations!.reSendRequest, rootNavigator: true, context);
        }
      } catch (e) {
        if (mounted) {
          FlutterToastr.show('${localizations!.fail} $e', rootNavigator: true, context);
        }
      }
    }
  }
}

class _ClearSelectionIntent extends Intent {
  const _ClearSelectionIntent();
}

enum _RequestListMenuAction { search, export, repeat, select, sort, report }
