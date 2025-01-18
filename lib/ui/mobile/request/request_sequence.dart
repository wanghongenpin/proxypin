import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/desktop/request/model/search_model.dart';
import 'package:proxypin/ui/mobile/request/request.dart';
import 'package:proxypin/ui/mobile/widgets/highlight.dart';
import 'package:proxypin/utils/listenable_list.dart';

///请求序列 列表
///@author wanghongen
class RequestSequence extends StatefulWidget {
  final ListenableList<HttpRequest> container;
  final ProxyServer proxyServer;
  final bool displayDomain;
  final bool? sortDesc;
  final Function(List<HttpRequest>)? onRemove;

  const RequestSequence(
      {super.key, required this.container, required this.proxyServer, this.displayDomain = true, this.onRemove, this.sortDesc});

  @override
  State<StatefulWidget> createState() {
    return RequestSequenceState();
  }
}

class RequestSequenceState extends State<RequestSequence> with AutomaticKeepAliveClientMixin {
  ///请求id和对应的row的映射
  Map<String, GlobalKey<RequestRowState>> indexes = HashMap();

  ///显示的请求列表 最新的在前面
  Queue<HttpRequest> view = Queue();
  bool changing = false;

  bool sortDesc = true;

  //搜索的内容
  SearchModel? searchModel;

  //关键词高亮监听
  late VoidCallback highlightListener;

  @override
  initState() {
    super.initState();
    sortDesc = widget.sortDesc ?? true;
    view.addAll(widget.container.source.reversed);
    highlightListener = () {
      //回调时机在高亮设置页面dispose之后。所以需要在下一帧刷新，否则会报错
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        setState(() {});
      });
    };
    KeywordHighlight.keywordsController.addListener(highlightListener);
  }

  @override
  dispose() {
    KeywordHighlight.keywordsController.removeListener(highlightListener);
    super.dispose();
  }

  ///添加请求
  add(HttpRequest request) {
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
  addResponse(HttpResponse response) {
    var state = indexes.remove(response.request?.requestId);
    state?.currentState?.change(response);

    if (searchModel == null || searchModel!.isEmpty || response.request == null) {
      return;
    }

    //搜索视图
    if (searchModel?.filter(response.request!, response) == true && state == null) {
      if (!view.contains(response.request)) {
        view.addFirst(response.request!);
        changeState();
      }
    }
  }

  clean() {
    setState(() {
      view.clear();
      indexes.clear();

      view.addAll(widget.container.source.reversed);
    });
  }

  remove(List<HttpRequest> list) {
    setState(() {
      view.removeWhere((element) => list.contains(element));
    });
  }

  ///过滤
  void search(SearchModel searchModel) {
    this.searchModel = searchModel;
    if (searchModel.isEmpty) {
      view = Queue.of(widget.container.source.reversed);
    } else {
      view = Queue.of(widget.container.where((it) => searchModel.filter(it, it.response)).toList().reversed);
    }
    changeState();
  }

  Iterable<HttpRequest> currentView() {
    return view;
  }

  changeState() {
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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scrollbar(
        controller: PrimaryScrollController.maybeOf(context),
        child: ListView.separated(
            controller: PrimaryScrollController.maybeOf(context),
            cacheExtent: 1000,
            separatorBuilder: (context, index) =>
                Divider(thickness: 0.2, height: 0, color: Theme.of(context).dividerColor),
            itemCount: view.length,
            itemBuilder: (context, index) {
              return RequestRow(
                  index: sortDesc ? view.length - index : index,
                  key: indexes[view.elementAt(index).requestId] ??= GlobalKey(),
                  request: view.elementAt(index),
                  proxyServer: widget.proxyServer,
                  displayDomain: widget.displayDomain,
                  onRemove: (request) {
                    setState(() {
                      view.remove(request);
                    });
                    widget.onRemove?.call([request]);
                  });
            }));
  }

  scrollToTop() {
    PrimaryScrollController.maybeOf(context)
        ?.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.ease);
  }

  ///排序
  sort(bool desc) {
    if (sortDesc == desc) {
      return;
    }

    sortDesc = desc;
    setState(() {
      view = Queue.of(view.toList().reversed);
    });
  }
}
