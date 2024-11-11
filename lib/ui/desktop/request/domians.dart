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
import 'package:flutter_desktop_context_menu/flutter_desktop_context_menu.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http_client.dart';
import 'package:proxypin/ui/component/transition.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/content/panel.dart';
import 'package:proxypin/ui/desktop/request/model/search_model.dart';
import 'package:proxypin/ui/desktop/request/request.dart';
import 'package:proxypin/ui/desktop/widgets/highlight.dart';
import 'package:proxypin/utils/listenable_list.dart';

/// 左侧域名
/// @author wanghongen
/// 2023/10/8
class DomainList extends StatefulWidget {
  final ProxyServer proxyServer;
  final NetworkTabController panel;

  final ListenableList<HttpRequest> list;
  final bool shrinkWrap;
  final Function(List<HttpRequest>)? onRemove;

  const DomainList(
      {super.key,
      required this.proxyServer,
      required this.list,
      this.shrinkWrap = true,
      required this.panel,
      this.onRemove});

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

  changeState() {
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
      domainRequests.addRequest(request.requestId, request);
    }
    highlightListener = () {
      //回调时机在高亮设置页面dispose之后。所以需要在下一帧刷新，否则会报错
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        highlightHandler();
      });
    };
    DesktopKeywordHighlight.keywordsController.addListener(highlightListener);
  }

  @override
  dispose() {
    DesktopKeywordHighlight.keywordsController.removeListener(highlightListener);
    super.dispose();
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
    } else {
      searchView.clear();
    }

    return widget.shrinkWrap
        ? SingleChildScrollView(child: Column(children: list.toList()))
        : ListView.builder(itemCount: list.length, itemBuilder: (_, index) => list.elementAt(index));
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
        result[key] = domainRequests.copy(body: body, selected: searchView[key]?.currentSelected);
      }
    });

    return result;
  }

  ///高亮处理
  highlightHandler() {
    //获取所有请求Widget
    List<RequestWidget> requests = containerMap.values.map((e) => e.body).expand((element) => element).toList();
    for (RequestWidget request in requests) {
      GlobalKey key = request.key as GlobalKey<State>;
      key.currentState?.setState(() {});
    }
  }

  ///添加请求
  add(Channel channel, HttpRequest request) {
    String? host = request.remoteDomain();
    if (host == null) {
      return;
    }

    //按照域名分类
    DomainRequests domainRequests = getDomainRequests(request);
    var isNew = domainRequests.body.isEmpty;

    domainRequests.addRequest(request.requestId, request);
    //搜索视图
    if (searchModel?.isNotEmpty == true && searchModel?.filter(request, null) == true) {
      searchView[host]?.addRequest(request.requestId, request);
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
        proxyServer: widget.panel.proxyServer,
        trailing: appIcon(request),
        onDelete: deleteHost,
        onRequestRemove: (req) {
          widget.onRemove?.call([req]);
          changeState();
        },
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
  deleteHost(String host) {
    DomainRequests? domainRequests = containerMap.remove(host);
    if (domainRequests == null) {
      return;
    }
    setState(() {});

    widget.onRemove?.call(domainRequests.body.map((e) => e.request).toList());
  }

  ///添加响应
  addResponse(ChannelContext channelContext, HttpResponse response) {
    String domain = channelContext.host!.domain;
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
        requests?.addRequest(response.requestId, pathRow.request);
      }
      requests?.getRequest(response)?.setResponse(response);
    }
  }

  remove(List<HttpRequest> list) {
    for (var request in list) {
      String? host = request.remoteDomain();
      containerMap[host]?._removeRequest(request);
    }
  }

  ///清理
  clean() {
    setState(() {
      containerMap.clear();
      searchView.clear();

      var container = widget.list;
      for (var request in container.source) {
        DomainRequests domainRequests = getDomainRequests(request);
        domainRequests.addRequest(request.requestId, request);
      }
    });
  }

  List<HttpRequest> currentView() {
    var container = containerMap.values;
    if (searchModel?.isNotEmpty == true) {
      container = searchView.values;
    }
    return container.expand((list) => list.body.map((it) => it.request)).toList();
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
  final Function(HttpRequest request)? onRequestRemove;

  DomainRequests(this.domain,
      {this.selected = false, this.onDelete, required this.proxyServer, this.onRequestRemove, this.trailing})
      : super(key: GlobalKey<_DomainRequestsState>());

  ///添加请求
  void addRequest(String? requestId, HttpRequest request) {
    if (requestMap.containsKey(requestId)) return;

    var requestWidget = RequestWidget(request,
        index: body.length, proxyServer: proxyServer, displayDomain: false, remove: (it) => _remove(it));
    body.addFirst(requestWidget);
    if (requestId == null) {
      return;
    }
    requestMap[requestId] = requestWidget;
    changeState();
  }

  RequestWidget? getRequest(HttpResponse response) {
    return requestMap[response.request?.requestId ?? response.requestId];
  }

  setTrailing(Widget? trailing) {
    var state = key as GlobalKey<_DomainRequestsState>;
    state.currentState?.trailing = trailing;
  }

  _remove(RequestWidget requestWidget) {
    if (body.remove(requestWidget)) {
      onRequestRemove?.call(requestWidget.request);
      changeState();
    }
  }

  _removeRequest(HttpRequest request) {
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
  DomainRequests copy({Iterable<RequestWidget>? body, bool? selected}) {
    var state = key as GlobalKey<_DomainRequestsState>;
    var headerBody = DomainRequests(domain,
        trailing: trailing,
        selected: selected ?? state.currentState?.selected == true,
        onDelete: onDelete,
        onRequestRemove: onRequestRemove,
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

  changeState() {
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

  @override
  void initState() {
    super.initState();
    configuration = widget.proxyServer.configuration;
    selected = widget.selected;
    trailing = widget.trailing;
  }

  changeState() {
    //防止频繁刷新
    if (!changing) {
      changing = true;
      Future.delayed(const Duration(milliseconds: 500), () {
        setState(() {
          changing = false;
        });
        transitionState.currentState?.show();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _hostWidget(widget.domain),
      Offstage(offstage: !selected, child: Column(children: widget.body.toList()))
    ]);
  }

  //domain title
  Widget _hostWidget(String title) {
    var host = GestureDetector(
        onSecondaryTap: menu,
        child: ListTile(
            minLeadingWidth: 25,
            leading: Icon(selected ? Icons.arrow_drop_down : Icons.arrow_right, size: 18),
            trailing: trailing,
            dense: true,
            horizontalTitleGap: 0,
            contentPadding: const EdgeInsets.only(left: 3, right: 8),
            visualDensity: const VisualDensity(vertical: -3.6),
            title: Text(title,
                textAlign: TextAlign.left,
                style: const TextStyle(fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            onTap: () {
              setState(() {
                selected = !selected;
              });
            }));

    return ColorTransition(
        key: transitionState,
        duration: const Duration(milliseconds: 1800),
        begin: Theme.of(context).focusColor,
        startAnimation: false,
        child: host);
  }

  //域名右键菜单
  menu() {
    Menu menu = Menu(items: [
      MenuItem(
          label: localizations.copyHost,
          onClick: (_) {
            Clipboard.setData(ClipboardData(text: Uri.parse(widget.domain).host));
            FlutterToastr.show(localizations.copied, context);
          }),
      MenuItem.separator(),
      MenuItem(
        label: localizations.domainFilter,
        type: 'submenu',
        submenu: hostFilterMenu(),
      ),
      MenuItem.separator(),
      MenuItem(label: localizations.repeatDomainRequests, onClick: (_) => repeatDomainRequests()),
      MenuItem.separator(),
      MenuItem(label: localizations.delete, onClick: (_) => _delete()),
    ]);

    popUpContextMenu(menu);
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

  Menu hostFilterMenu() {
    return Menu(items: [
      MenuItem(
          label: localizations.domainBlacklist,
          onClick: (_) {
            HostFilter.blacklist.add(Uri.parse(widget.domain).host);
            configuration.flushConfig();
            FlutterToastr.show(localizations.addSuccess, context);
          }),
      MenuItem(
          label: localizations.domainWhitelist,
          onClick: (_) {
            HostFilter.whitelist.add(Uri.parse(widget.domain).host);
            configuration.flushConfig();
            FlutterToastr.show(localizations.addSuccess, context);
          }),
      MenuItem(
          label: localizations.deleteWhitelist,
          onClick: (_) {
            HostFilter.whitelist.remove(Uri.parse(widget.domain).host);
            configuration.flushConfig();
            FlutterToastr.show(localizations.deleteSuccess, context);
          }),
    ]);
  }

  _delete() {
    widget.onDelete?.call(widget.domain);
    widget.requestMap.clear();
    widget.body.clear();
    FlutterToastr.show(localizations.deleteSuccess, context);
  }
}

class HostWidget extends StatelessWidget {
  final String host;
  final Function()? onMenu;

  HostWidget(this.host, {this.onMenu});

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
