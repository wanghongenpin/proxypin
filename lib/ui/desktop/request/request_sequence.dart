/*
 * Copyright 2023 Hongen Wang
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
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/desktop/request/request.dart';
import 'package:proxypin/utils/keyword_highlight.dart';
import 'package:proxypin/utils/listenable_list.dart';

import '../../component/model/search_model.dart';

///请求序列 列表
/// @author wanghongen
class RequestSequence extends StatefulWidget {
  final ListenableList<HttpRequest> container;
  final ProxyServer proxyServer;
  final bool displayDomain;
  final Function(List<HttpRequest>)? onRemove;
  final MultiSelectController selectionController;
  final RequestSelectionHandlers selectionHandlers;
  final VoidCallback? onInitialized;  // 初始化完成回调，解决 Tab 懒加载搜索不生效问题

  const RequestSequence(
      {super.key,
      required this.container,
      required this.proxyServer,
      this.displayDomain = true,
      this.onRemove,
      required this.selectionController,
      required this.selectionHandlers,
      this.onInitialized});

  @override
  State<StatefulWidget> createState() {
    return RequestSequenceState();
  }
}

class RequestSequenceState extends State<RequestSequence> with AutomaticKeepAliveClientMixin {
  late Configuration configuration;

  ///显示的请求列表 最新的在前面
  Queue<HttpRequest> view = Queue();
  final Map<String, VoidCallback> rowRefreshers = <String, VoidCallback>{};
  bool changing = false;

  bool sortDesc = true;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  //搜索的内容
  SearchModel? searchModel;

  //关键词高亮监听
  late VoidCallback highlightListener;
  late MultiSelectListener<String> selectionListener;

  MultiSelectController get selectionController => widget.selectionController;

  @override
  void initState() {
    super.initState();
    configuration = widget.proxyServer.configuration;
    view.addAll(widget.container.source.reversed);

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
      _refreshChangedRows(items);
    });
    selectionController.selectedIds.addListener(selectionListener);

    // 通知父组件初始化完成，解决 Tab 懒加载时搜索不生效问题
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onInitialized?.call();
    });
  }

  void changeState() {
    //防止频繁刷新
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
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    selectionController.selectedIds.removeListener(selectionListener);
    KeywordHighlights.removeListener(highlightListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ListView.separated(
      cacheExtent: 1000,
      separatorBuilder: (context, index) => Divider(thickness: 0.2, height: 0, color: Theme.of(context).dividerColor),
      itemCount: view.length,
      itemBuilder: (context, index) {
        final request = view.elementAt(index);
        return RequestWidget(
          request,
          key: ValueKey(request.requestId),
          index: sortDesc ? view.length - index : index,
          trailing: appIcon(request),
          proxyServer: widget.proxyServer,
          displayDomain: widget.displayDomain,
          multiSelectController: selectionController,
          selectionHandlers: widget.selectionHandlers,
          onMount: (ref) => rowRefreshers[request.requestId] = ref,
          remove: (requestWidget) {
            setState(() {
              view.remove(requestWidget.request);
              rowRefreshers.remove(requestWidget.request.requestId);
              widget.onRemove?.call([requestWidget.request]);
            });
          },
        );
      },
    );
  }

  Widget? appIcon(HttpRequest request) {
    var processInfo = request.processInfo;
    if (processInfo == null) {
      return null;
    }

    return futureWidget(
        processInfo.getIcon(),
        (data) => data.isEmpty
            ? const SizedBox()
            : Image.memory(
                data,
                width: 23,
                height: Platform.isWindows ? 16 : null,
                errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => const SizedBox(),
              ));
  }

  ///高亮处理
  void highlightHandler() {
    setState(() {});
  }

  ///添加请求
  void add(HttpRequest request) {
    ///过滤
    if (searchModel?.isNotEmpty == true && !searchModel!.filter(request, request.response)) {
      return;
    }

    if (sortDesc) {
      view.addFirst(request);
    } else {
      view.addLast(request);
    }

    changeState();
  }

  ///添加响应
  void addResponse(HttpResponse response) {
    if (searchModel == null || searchModel!.isEmpty || response.request == null) {
      changeState();
      return;
    }

    //搜索视图
    if (searchModel?.filter(response.request!, response) == true) {
      if (!view.contains(response.request)) {
        view.addFirst(response.request!);
        changeState();
      }
    }
  }

  ///过滤
  void search(SearchModel searchModel) {
    this.searchModel = searchModel;
    if (searchModel.isEmpty) {
      view = Queue.of(widget.container.source.reversed);
    } else {
      view = Queue.of(widget.container.where((it) => searchModel.filter(it, it.response)).toList().reversed);
    }
    rowRefreshers.removeWhere((requestId, _) => !view.any((request) => request.requestId == requestId));
    selectionController.prune(view.map((request) => request.requestId));
    setState(() {});
  }

  void remove(List<HttpRequest> list) {
    setState(() {
      view.removeWhere((element) => list.contains(element));
      for (final request in list) {
        rowRefreshers.remove(request.requestId);
      }
    });
  }

  void clean() {
    setState(() {
      view.clear();
      rowRefreshers.clear();
      view.addAll(widget.container.source.reversed);
    });
  }

  void selectRange(HttpRequest request) {
    setState(() {
      selectionController.selectRange(view.map((item) => item.requestId).toList(), request.requestId);
    });
  }

  ///排序
  void sort(bool desc) {
    sortDesc = desc;
    setState(() {
      view = Queue.of(view.toList().reversed);
    });
  }

  void _refreshChangedRows(List<String> changedIds) {
    if (changedIds.isEmpty) {
      return;
    }

    for (final requestId in changedIds) {
      rowRefreshers[requestId]?.call();
    }
  }
}
