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
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/ui/component/context_menu.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';
import 'package:proxypin/ui/component/request_tree.dart';
import 'package:proxypin/ui/component/request_tree_view.dart';
import 'package:proxypin/ui/component/transition.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/content/panel.dart';
import 'package:proxypin/ui/desktop/request/request.dart';
import 'package:proxypin/utils/har.dart';
import 'package:proxypin/utils/keyword_highlight.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/listenable_list.dart';
import 'package:proxypin/utils/platform.dart';

import '../../component/model/search_model.dart';

/// 左侧域名
/// @author wanghongen
/// 2023/10/8
class DomainList extends StatefulWidget {
  final ProxyServer proxyServer;
  final NetworkTabController panel;

  final ListenableList<HttpRequest> list;
  final bool shrinkWrap;
  final Function(List<HttpRequest>)? onRemove;
  final MultiSelectController selectionController;
  final RequestSelectionHandlers selectionHandlers;

  const DomainList(
      {super.key,
      required this.proxyServer,
      required this.list,
      this.shrinkWrap = true,
      required this.panel,
      this.onRemove,
      required this.selectionController,
      required this.selectionHandlers});

  @override
  State<StatefulWidget> createState() {
    return DomainWidgetState();
  }
}

class DomainWidgetState extends State<DomainList> with AutomaticKeepAliveClientMixin {
  //域名和对应请求列表的映射
  final LinkedHashMap<String, DomainRequests> containerMap = LinkedHashMap<String, DomainRequests>();

  //搜索视图
  LinkedHashMap<String, DomainRequests> searchView = LinkedHashMap<String, DomainRequests>();

  //搜索的内容
  SearchModel? searchModel;
  bool changing = false; //是否存在刷新任务
  //关键词高亮监听
  late VoidCallback highlightListener;
  late MultiSelectListener<String> selectionListener;

  bool sortDesc = true;

  ///列表/树形展示模式。直接用配置里的那份，设置页改了这里立刻生效。
  ///多窗口下 AppConfiguration.current 可能为空，那时才退化成本地的一份
  ValueNotifier<RequestViewMode>? _localViewMode;

  ValueNotifier<RequestViewMode> get viewMode =>
      AppConfiguration.current?.requestViewMode ?? (_localViewMode ??= ValueNotifier(RequestViewMode.list));

  ///树形展开状态在域名之间共享
  final RequestTreeExpansion treeExpansion = RequestTreeExpansion();

  ///搜索结果单独一份展开状态，默认全开但仍然可以手动收起
  RequestTreeExpansion searchExpansion = RequestTreeExpansion(expandedByDefault: true);

  ///键盘所在的行，键是 RequestTreeRow.key，域名行的键就是域名本身
  final ValueNotifier<String?> cursor = ValueNotifier(null);
  final GlobalKey _cursorAnchor = GlobalKey();
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'domain tree');

  bool get isTreeMode => viewMode.value == RequestViewMode.tree;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  MultiSelectController get selectionController => widget.selectionController;

  void changeState() {
    if (!changing) {
      changing = true;
      Future.delayed(const Duration(milliseconds: 500), () {
        setState(() {
          changing = false;
        });
      });
    }
  }

  @override
  void initState() {
    super.initState();
    var container = widget.list;
    for (var request in container.source) {
      DomainRequests domainRequests = getDomainRequests(request);
      domainRequests.addRequest(request.requestId, request, sortDesc);
    }
    highlightListener = () {
      //回调时机在高亮设置页面dispose之后。所以需要在下一帧刷新，否则会报错
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        highlightHandler();
      });
    };
    KeywordHighlights.addListener(highlightListener);

    selectionListener = MultiSelectListener((items) {
      if (!mounted) {
        return;
      }
      _refreshRequestSelection(items);
    });
    selectionController.selectedIds.addListener(selectionListener);
  }

  @override
  void dispose() {
    selectionController.selectedIds.removeListener(selectionListener);
    KeywordHighlights.removeListener(highlightListener);
    treeExpansion.dispose();
    searchExpansion.dispose();
    //只销毁自己建的那份，配置里的那份归 AppConfiguration
    _localViewMode?.dispose();
    cursor.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  ///当前生效的展开状态：搜索中用搜索那份
  RequestTreeExpansion get activeExpansion => searchModel?.isNotEmpty == true ? searchExpansion : treeExpansion;

  ///屏幕上从上到下的所有行，域名行在前，展开的域名后面跟着它的路径树
  List<RequestTreeRow> _visibleRows() {
    var domains = searchModel?.isNotEmpty == true ? searchView.values : containerMap.values;
    var expansion = activeExpansion;
    var rows = <RequestTreeRow>[];

    for (var domain in domains) {
      var root = RequestTree.build(domain.domain, domain.body.map((it) => it.request));
      rows.add(RequestTreeRow(key: domain.domain, parentKey: null, depth: 0, label: domain.domain, node: root));
      if (domain.currentSelected) {
        rows.addAll(RequestTree.visibleRows(root, expansion));
      }
    }
    return rows;
  }

  DomainRequests? _domainOf(String domain) {
    var domains = searchModel?.isNotEmpty == true ? searchView : containerMap;
    return domains[domain];
  }

  ///点开某一行时把键盘光标挪过去，并让列表拿到焦点，之后方向键就能用了
  void _onFolderTap(String rowKey) {
    cursor.value = rowKey;
    _keyboardFocus.requestFocus();
  }

  ///键盘导航：上下移动，右键展开或进入，左键收起或回到父节点
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !isTreeMode) {
      return KeyEventResult.ignored;
    }

    var key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      return moveCursor(1);
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      return moveCursor(-1);
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return expandOrEnter();
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      return collapseOrLeave();
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult moveCursor(int delta) {
    var rows = _visibleRows();
    if (rows.isEmpty) {
      return KeyEventResult.ignored;
    }

    var index = rows.indexWhere((row) => row.key == cursor.value);
    var next = index < 0 ? (delta > 0 ? 0 : rows.length - 1) : index + delta;
    if (next < 0 || next >= rows.length) {
      return KeyEventResult.handled;
    }

    _setCursor(rows[next]);
    return KeyEventResult.handled;
  }

  KeyEventResult expandOrEnter() {
    var rows = _visibleRows();
    var index = rows.indexWhere((row) => row.key == cursor.value);
    if (index < 0) {
      return moveCursor(1);
    }

    var row = rows[index];
    if (!row.isFolder) {
      return KeyEventResult.handled;
    }

    var expanded = row.depth == 0 ? _domainOf(row.key)?.currentSelected == true : activeExpansion.isExpanded(row.key);
    if (!expanded) {
      _setExpanded(row, true);
      return KeyEventResult.handled;
    }

    //已经展开就进入第一个子节点
    return moveCursor(1);
  }

  KeyEventResult collapseOrLeave() {
    var rows = _visibleRows();
    var index = rows.indexWhere((row) => row.key == cursor.value);
    if (index < 0) {
      return KeyEventResult.ignored;
    }

    var row = rows[index];
    var expanded = row.isFolder &&
        (row.depth == 0 ? _domainOf(row.key)?.currentSelected == true : activeExpansion.isExpanded(row.key));
    if (expanded) {
      _setExpanded(row, false);
      return KeyEventResult.handled;
    }

    //已经收起或是请求行，就回到父节点
    if (row.parentKey == null) {
      return KeyEventResult.handled;
    }
    var parent = rows.firstWhereOrNull((it) => it.key == row.parentKey);
    if (parent != null) {
      _setCursor(parent);
    }
    return KeyEventResult.handled;
  }

  void _setExpanded(RequestTreeRow row, bool expanded) {
    if (row.depth == 0) {
      _domainOf(row.key)?.setExpanded(expanded);
      setState(() {});
      return;
    }
    activeExpansion.setExpanded(row.key, expanded);
  }

  void _setCursor(RequestTreeRow row) {
    cursor.value = row.key;

    //光标停在请求行时，右侧面板跟着打开这条请求
    if (!row.isFolder) {
      var requestId = row.request!.requestId;
      for (var domain in containerMap.values) {
        domain.requestMap[requestId]?.select();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      var context = _cursorAnchor.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(context, alignment: 0.2, duration: const Duration(milliseconds: 120));
      }
    });
  }

  ///展开全部节点，包含域名本身
  void expandAll() {
    activeExpansion.expandAll();
    for (var domainRequests in containerMap.values) {
      domainRequests.setExpanded(true);
    }
    setState(() {});
  }

  ///收起全部节点
  void collapseAll() {
    activeExpansion.collapseAll();
    for (var domainRequests in containerMap.values) {
      domainRequests.setExpanded(false);
    }
    setState(() {});
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    var list = containerMap.values;

    //根究搜素文本过滤
    if (searchModel?.isNotEmpty == true) {
      searchView = searchFilter(searchModel!);
      list = searchView.values;
      selectionController.prune(list.expand((e) => e.body).map((e) => e.request.requestId).toSet());
    } else {
      searchView.clear();
    }

    var body = widget.shrinkWrap
        ? SingleChildScrollView(child: Column(children: list.toList()))
        : ListView.builder(itemCount: list.length, itemBuilder: (_, index) => list.elementAt(index));

    //树形模式下接管方向键；点进列表才拿焦点，不抢输入框
    return Focus(focusNode: _keyboardFocus, onKeyEvent: _onKey, child: body);
  }

  ///搜索
  void search(SearchModel? val) {
    setState(() {
      searchModel = val;
    });
  }

  ///搜索过滤
  LinkedHashMap<String, DomainRequests> searchFilter(SearchModel searchModel) {
    LinkedHashMap<String, DomainRequests> result = LinkedHashMap<String, DomainRequests>();

    containerMap.forEach((key, domainRequests) {
      var body = domainRequests.search(searchModel);
      if (body.isNotEmpty) {
        //搜索结果强制展开，否则匹配到的请求会被折叠的目录挡住
        //搜索结果用另一份展开状态，默认全开但用户仍然可以手动收起
        result[key] =
            domainRequests.copy(body: body, selected: searchView[key]?.currentSelected, expansion: searchExpansion);
      }
    });

    return result;
  }

  ///高亮处理
  void highlightHandler() {
    //获取所有请求Widget
    List<RequestWidget> requests = containerMap.values.map((e) => e.body).expand((element) => element).toList();
    for (RequestWidget request in requests) {
      request.changeState();
    }
  }

  ///添加请求
  void add(Channel channel, HttpRequest request) {
    String? host = request.remoteDomain();
    if (host == null) {
      return;
    }

    //按照域名分类
    DomainRequests domainRequests = getDomainRequests(request);
    var isNew = domainRequests.body.isEmpty;

    domainRequests.addRequest(request.requestId, request, sortDesc);
    //搜索视图
    if (searchModel?.isNotEmpty == true && searchModel?.filter(request, null) == true) {
      searchView[host]?.addRequest(request.requestId, request, sortDesc);
    }

    if (isNew) {
      setState(() {
        containerMap[host] = domainRequests;
      });
    }
  }

  DomainRequests getDomainRequests(HttpRequest request) {
    var host = request.remoteDomain()!;
    DomainRequests? domainRequests = containerMap[host];
    if (domainRequests == null) {
      domainRequests = DomainRequests(
        host,
        proxyServer: widget.proxyServer,
        trailing: appIcon(request),
        onDelete: deleteHost,
        onExportHar: exportDomainHar,
        onRequestRemove: (req) {
          widget.onRemove?.call([req]);
          changeState();
        },
        selectionController: selectionController,
        selectionHandlers: widget.selectionHandlers,
        viewMode: viewMode,
        treeExpansion: treeExpansion,
        cursor: cursor,
        cursorAnchor: _cursorAnchor,
        onFolderTap: _onFolderTap,
      );
      containerMap[host] = domainRequests;
    }

    return domainRequests;
  }

  Widget? appIcon(HttpRequest request) {
    var processInfo = request.processInfo;
    if (processInfo == null) {
      return null;
    }

    return futureWidget(
        processInfo.getIcon(),
        (data) =>
            data.isEmpty ? const SizedBox() : Image.memory(data, width: 23, height: Platform.isWindows ? 16 : null));
  }

  ///移除域名
  void deleteHost(String host) {
    DomainRequests? domainRequests = containerMap.remove(host);
    if (domainRequests == null) {
      return;
    }
    setState(() {});

    widget.onRemove?.call(domainRequests.body.map((e) => e.request).toList());
  }

  ///添加响应
  void addResponse(ChannelContext channelContext, HttpResponse response) {
    String domain = response.request?.hostAndPort?.domain ?? channelContext.host!.domain;
    DomainRequests? domainRequests = containerMap[domain];
    var pathRow = domainRequests?.getRequest(response);
    pathRow?.setResponse(response);
    if (pathRow == null) {
      return;
    }

    //搜索视图
    if (searchModel?.isNotEmpty == true && searchModel?.filter(pathRow.request, response) == true) {
      var requests = searchView[domain];
      if (requests?.getRequest(response) == null) {
        requests?.addRequest(response.requestId, pathRow.request, sortDesc);
      }
      requests?.getRequest(response)?.setResponse(response);
    }
  }

  void remove(List<HttpRequest> list) {
    for (var request in list) {
      String? host = request.remoteDomain();
      containerMap[host]?._removeRequest(request);
    }
  }

  ///清理
  void clean() {
    setState(() {
      containerMap.clear();
      searchView.clear();

      var container = widget.list;
      for (var request in container.source) {
        DomainRequests domainRequests = getDomainRequests(request);
        domainRequests.addRequest(request.requestId, request, sortDesc);
      }
    });
  }

  List<HttpRequest> currentView() {
    var container = containerMap.values;
    if (searchModel?.isNotEmpty == true) {
      container = searchView.values;
    }

    if (isTreeMode) {
      //树形模式下显示顺序由路径决定，范围选择需要按显示顺序来
      return container
          .expand((domain) => RequestTree.build(domain.domain, domain.body.map((it) => it.request)).orderedRequests())
          .toList();
    }

    return container.expand((list) => list.body.map((it) => it.request)).toList();
  }

  Future<void> exportDomainHar(String domain) async {
    var requests = containerMap[domain]?.body.map((it) => it.request).toList() ?? [];
    if (requests.isEmpty) {
      if (mounted) FlutterToastr.show(localizations.emptyData, context);
      return;
    }

    var fileName = _domainHarFileName(domain);
    try {
      var path = await Platforms.saveFileAdaptive(fileName: fileName);
      if (path == null) {
        return;
      }
      var file = await File(path).create(recursive: true);
      await Har.writeFile(requests, file, title: fileName);
      if (mounted) FlutterToastr.show(localizations.exportSuccess, context);
    } catch (e) {
      if (mounted) FlutterToastr.show('${localizations.exportFailed} $e', context);
    }
  }

  String _domainHarFileName(String domain) {
    var uri = Uri.tryParse(domain);
    var host = (uri?.host.isNotEmpty == true) ? uri!.host : domain;
    var suffix = uri?.hasPort == true ? '_${uri!.port}' : '';
    var safeDomain = '$host$suffix'.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safeDomain.isEmpty) {
      safeDomain = 'domain';
    }
    return 'ProxyPin_${safeDomain}_${DateTime.now().dateFormat()}.har';
  }

  ///排序
  void sort(bool desc) {
    sortDesc = desc;
    containerMap.forEach((key, request) {
      var reversed = request.body.toList().reversed;
      request.body.clear();
      request.body.addAll(reversed);
      request.changeState();
    });
  }

  List<HttpRequest> selectedRequests() {
    final selectedIds = selectionController.selectedIds;
    if (selectedIds.isEmpty) {
      return [];
    }
    return currentView().where((request) => selectedIds.contains(request.requestId)).toList();
  }

  void selectRange(HttpRequest request) {
    final currentIds = currentView().map((item) => item.requestId).toList();
    if (currentIds.isEmpty) {
      return;
    }

    selectionController.selectRange(currentIds, request.requestId);
  }

  void _refreshRequestSelection(List<String> selectedIds) {
    var container = containerMap.values;
    if (searchModel?.isNotEmpty == true) {
      container = searchView.values;
    }
    for (var domain in container) {
      for (var requestWidget in domain.body) {
        if (selectedIds.contains(requestWidget.request.requestId)) {
          requestWidget.changeState();
        }
      }
    }
  }
}

///标题和内容布局 标题是域名 内容是域名下请求
class DomainRequests extends StatefulWidget {
  //请求ID和请求的映射
  final Map<String, RequestWidget> requestMap = HashMap<String, RequestWidget>();

  final String domain;
  final ProxyServer proxyServer;
  final Widget? trailing;

  //请求列表
  final Queue<RequestWidget> body = Queue();

  //是否选中
  final bool selected;

  //移除回调
  final Function(String host)? onDelete;
  final Function(String host)? onExportHar;
  final Function(HttpRequest request)? onRequestRemove;
  final RequestSelectionHandlers selectionHandlers;
  final MultiSelectController selectionController;

  ///列表/树形展示模式，由域名列表统一持有
  final ValueNotifier<RequestViewMode> viewMode;

  ///树形目录的展开状态，所有域名共享
  final RequestTreeExpansion treeExpansion;

  ///键盘所在的行
  final ValueNotifier<String?>? cursor;

  ///键盘所在行上方的锚点，用于滚动到可视区域
  final GlobalKey? cursorAnchor;

  ///点开目录时通知外层，把键盘光标挪过去
  final ValueChanged<String>? onFolderTap;

  DomainRequests(this.domain,
      {this.selected = false,
      this.onDelete,
      this.onExportHar,
      required this.proxyServer,
      this.onRequestRemove,
      required this.selectionHandlers,
      this.trailing,
      required this.selectionController,
      required this.viewMode,
      required this.treeExpansion,
      this.cursor,
      this.cursorAnchor,
      this.onFolderTap})
      : super(key: GlobalKey<_DomainRequestsState>());

  ///展开或收起该域名
  void setExpanded(bool expanded) {
    var state = key as GlobalKey<_DomainRequestsState>;
    state.currentState?.setExpanded(expanded);
  }

  ///添加请求
  void addRequest(String? requestId, HttpRequest request, bool sortDesc) {
    if (requestMap.containsKey(requestId)) return;

    var requestWidget = RequestWidget(request,
        key: ValueKey(request.requestId),
        index: body.length,
        proxyServer: proxyServer,
        displayDomain: false,
        multiSelectController: selectionController,
        selectionHandlers: selectionHandlers,
        remove: (it) => _remove(it));
    sortDesc ? body.addFirst(requestWidget) : body.addLast(requestWidget);

    if (requestId == null) {
      return;
    }

    requestMap[requestId] = requestWidget;
    changeState();
  }

  RequestWidget? getRequest(HttpResponse response) {
    return requestMap[response.request?.requestId ?? response.requestId];
  }

  void setTrailing(Widget? trailing) {
    var state = key as GlobalKey<_DomainRequestsState>;
    state.currentState?.trailing = trailing;
  }

  void _remove(RequestWidget requestWidget) {
    if (body.remove(requestWidget)) {
      onRequestRemove?.call(requestWidget.request);
      changeState();
    }
  }

  void _removeRequest(HttpRequest request) {
    var requestWidget = requestMap.remove(request.requestId);
    if (requestWidget != null) {
      _remove(requestWidget);
    }
  }

  ///根据文本过滤
  Iterable<RequestWidget> search(SearchModel searchModel) {
    return body
        .where((element) => searchModel.filter(element.request, element.response.get() ?? element.request.response));
  }

  ///复制
  DomainRequests copy({Iterable<RequestWidget>? body, bool? selected, RequestTreeExpansion? expansion}) {
    var state = key as GlobalKey<_DomainRequestsState>;
    var headerBody = DomainRequests(domain,
        trailing: trailing,
        selected: selected ?? state.currentState?.selected == true,
        onDelete: onDelete,
        onExportHar: onExportHar,
        onRequestRemove: onRequestRemove,
        selectionController: selectionController,
        selectionHandlers: selectionHandlers,
        viewMode: viewMode,
        treeExpansion: expansion ?? treeExpansion,
        cursor: cursor,
        cursorAnchor: cursorAnchor,
        onFolderTap: onFolderTap,
        proxyServer: proxyServer);
    if (body != null) {
      headerBody.body.addAll(body);
    }
    return headerBody;
  }

  bool get currentSelected {
    var state = key as GlobalKey<_DomainRequestsState>;
    return state.currentState?.selected == true;
  }

  void changeState() {
    var state = key as GlobalKey<_DomainRequestsState>;
    state.currentState?.changeState();
  }

  @override
  State<StatefulWidget> createState() {
    return _DomainRequestsState();
  }
}

class _DomainRequestsState extends State<DomainRequests> {
  final GlobalKey<ColorTransitionState> transitionState = GlobalKey<ColorTransitionState>();
  late Configuration configuration;
  late bool selected;
  Widget? trailing;
  bool changing = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  bool get isTreeMode => widget.viewMode.value == RequestViewMode.tree;

  @override
  void initState() {
    super.initState();
    configuration = widget.proxyServer.configuration;
    selected = widget.selected;
    trailing = widget.trailing;
    widget.viewMode.addListener(_onViewModeChanged);
  }

  @override
  void dispose() {
    widget.viewMode.removeListener(_onViewModeChanged);
    super.dispose();
  }

  void _onViewModeChanged() {
    if (widget.viewMode.value == RequestViewMode.list) {
      //回到列表模式，恢复请求行原本的完整路径和缩进
      for (var requestWidget in widget.body) {
        requestWidget.applyTreeStyle(null);
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  void setExpanded(bool expanded) {
    if (selected == expanded || !mounted) {
      return;
    }
    setState(() {
      selected = expanded;
    });
  }

  void changeState() {
    //防止频繁刷新
    if (!changing) {
      changing = true;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            changing = false;
          });
          transitionState.currentState?.show();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isTreeMode) {
      //树形模式只在展开时构建，避免为折叠的域名白算一棵树
      return Column(children: [_hostWidget(widget.domain), if (selected) _treeBody()]);
    }

    return Column(children: [
      _hostWidget(widget.domain),
      Offstage(offstage: !selected, child: Column(children: widget.body.toList()))
    ]);
  }

  ///按路径分段构建域名下的请求树
  Widget _treeBody() {
    var requestWidgets = <String, RequestWidget>{};
    for (var requestWidget in widget.body) {
      requestWidgets[requestWidget.request.requestId] = requestWidget;
    }

    var root = RequestTree.build(widget.domain, widget.body.map((it) => it.request));
    return RequestTreeView(
        root: root,
        expansion: widget.treeExpansion,
        cursor: widget.cursor,
        cursorAnchor: widget.cursorAnchor,
        onFolderTap: widget.onFolderTap,
        leafBuilder: (request, style) {
          var requestWidget = requestWidgets[request.requestId]!;
          requestWidget.applyTreeStyle(style);
          return requestWidget;
        });
  }

  //domain title
  Widget _hostWidget(String title) {
    Widget host = GestureDetector(
        onSecondaryTapDown: (details) => menu(details),
        child: ListTile(
            minLeadingWidth: 25,
            leading: Icon(selected ? Icons.arrow_drop_down : Icons.arrow_right, size: 18),
            trailing: trailing,
            dense: true,
            horizontalTitleGap: 0,
            contentPadding: const EdgeInsets.only(left: 3, right: 8),
            visualDensity: const VisualDensity(vertical: -3.6),
            //树形模式下域名行和它下面的目录行排一样紧，平铺模式保持原样
            minTileHeight: isTreeMode ? RequestTreeStyle.rowHeight : null,
            minVerticalPadding: isTreeMode ? 0 : 4,
            title: Text(title,
                textAlign: TextAlign.left,
                style: const TextStyle(fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            onTap: () {
              setState(() {
                selected = !selected;
              });
              widget.onFolderTap?.call(widget.domain);
            }));

    //域名行也可以是键盘光标所在的行
    var cursor = widget.cursor;
    if (cursor != null) {
      host = ValueListenableBuilder<String?>(
          valueListenable: cursor,
          builder: (context, current, child) => Container(
              color: current == widget.domain && isTreeMode
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                  : null,
              child: child),
          child: host);
    }

    return ColorTransition(
        key: transitionState,
        duration: const Duration(milliseconds: 1800),
        begin: Theme.of(context).focusColor,
        startAnimation: false,
        child: host);
  }

  //域名右键菜单
  void menu(TapDownDetails details) {
    showCustomContextMenu(context, details.globalPosition, [
      ContextMenuItem.normal(
          label: localizations.copyHost,
          onClick: () {
            Clipboard.setData(ClipboardData(text: Uri.parse(widget.domain).host));
            FlutterToastr.show(localizations.copied, context);
          }),
      ContextMenuItem.separator(),
      ContextMenuItem.submenu(label: localizations.domainFilter, submenu: hostFilterMenu()),
      ContextMenuItem.separator(),
      ContextMenuItem.normal(label: localizations.exportDomainHar, onClick: () => exportDomainHar()),
      ContextMenuItem.separator(),
      ContextMenuItem.normal(label: localizations.repeatDomainRequests, onClick: () => repeatDomainRequests()),
      ContextMenuItem.separator(),
      ContextMenuItem.normal(label: localizations.delete, onClick: () => _delete()),
    ]);
  }

  //重复域名下请求
  void repeatDomainRequests() async {
    var list = widget.body.toList().reversed;
    for (var requestWidget in list) {
      var request = requestWidget.request.copy(uri: requestWidget.request.requestUrl);
      var proxyInfo = widget.proxyServer.isRunning ? ProxyInfo.of("127.0.0.1", widget.proxyServer.port) : null;
      try {
        await HttpClients.proxyRequest(request, proxyInfo: proxyInfo, timeout: const Duration(seconds: 3));
        if (mounted) FlutterToastr.show(localizations.reSendRequest, rootNavigator: true, context);
      } catch (e) {
        if (mounted) FlutterToastr.show('${localizations.fail}$e', rootNavigator: true, context);
      }
    }
  }

  void exportDomainHar() {
    widget.onExportHar?.call(widget.domain);
  }

  List<ContextMenuItem> hostFilterMenu() {
    return [
      ContextMenuItem.normal(
          label: localizations.domainBlacklist,
          onClick: () {
            HostFilter.blacklist.add(Uri.parse(widget.domain).host);
            configuration.flushConfig();
            FlutterToastr.show(localizations.addSuccess, context);
          }),
      ContextMenuItem.normal(
          label: localizations.domainWhitelist,
          onClick: () {
            HostFilter.whitelist.add(Uri.parse(widget.domain).host);
            configuration.flushConfig();
            FlutterToastr.show(localizations.addSuccess, context);
          }),
      ContextMenuItem.normal(
          label: localizations.deleteWhitelist,
          onClick: () {
            HostFilter.whitelist.remove(Uri.parse(widget.domain).host);
            configuration.flushConfig();
            FlutterToastr.show(localizations.deleteSuccess, context);
          }),
    ];
  }

  void _delete() {
    widget.onDelete?.call(widget.domain);
    widget.requestMap.clear();
    widget.body.clear();
    FlutterToastr.show(localizations.deleteSuccess, context);
  }
}

class HostWidget extends StatelessWidget {
  final String host;
  final Function()? onMenu;

  const HostWidget(this.host, {super.key, this.onMenu});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onSecondaryTap: onMenu,
        child: ListTile(
            minLeadingWidth: 25,
            leading: const Icon(Icons.arrow_right, size: 18),
            dense: true,
            horizontalTitleGap: 0,
            contentPadding: const EdgeInsets.only(left: 3, right: 8),
            visualDensity: const VisualDensity(vertical: -3.6),
            title: Text(host,
                textAlign: TextAlign.left,
                style: const TextStyle(fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis)));
  }
}
