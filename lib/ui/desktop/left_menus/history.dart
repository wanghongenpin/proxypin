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
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:date_format/date_format.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http_client.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/histories.dart';
import 'package:proxypin/ui/component/history_cache_time.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/utils/har.dart';
import 'package:proxypin/utils/listenable_list.dart';

import '../../content/panel.dart';
import '../request/list.dart';

/// 历史记录
/// @author wanghongen
/// 2023/10/8
class HistoryPageWidget extends StatelessWidget {
  final ProxyServer proxyServer;
  final ListenableList<HttpRequest> container;
  final NetworkTabController panel;
  final HistoryTask historyTask;

  HistoryPageWidget({super.key, required this.proxyServer, required this.container, required this.panel})
      : historyTask = HistoryTask.ensureInstance(proxyServer.configuration, container);

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case "/request_list":
            return MaterialPageRoute(builder: (_) => requestListWidget(context, settings.arguments as Map));
          default:
            return MaterialPageRoute(
                builder: (_) => futureWidget(
                      HistoryStorage.instance,
                      (storage) => _HistoryListWidget(storage,
                          container: container, proxyServer: proxyServer, historyTask: historyTask),
                    ));
        }
      },
    );
  }

  Widget requestListWidget(BuildContext context, Map arguments) {
    var requestListKey = GlobalKey<DesktopRequestListState>();

    HistoryItem item = arguments['item'];
    var localizations = AppLocalizations.of(context)!;

    return Scaffold(
        appBar: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: AppBar(
              leadingWidth: 50,
              leading: BackButton(style: ButtonStyle(iconSize: MaterialStateProperty.all(15))),
              centerTitle: false,
              title: Text(
                  textAlign: TextAlign.start,
                  localizations.historyRecordTitle(
                      item.requestLength, item.name.substring(0, min(item.name.length, 25))),
                  style: const TextStyle(fontSize: 14)),
            )),
        body: futureWidget(HistoryStorage.instance.then((value) => value.getRequests(item)), (data) {
          //shrinkWrap: false,
          return DesktopRequestListWidget(
              panel: panel, proxyServer: proxyServer, list: ListenableList(data), key: requestListKey);
        }, loading: true));
  }
}

///历史记录列表
class _HistoryListWidget extends StatefulWidget {
  // 存储
  final HistoryStorage storage;
  final ListenableList<HttpRequest> container;
  final ProxyServer proxyServer;
  final HistoryTask historyTask;

  const _HistoryListWidget(this.storage,
      {required this.container, required this.proxyServer, required this.historyTask});

  @override
  State<StatefulWidget> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryListWidget> {
  ///是否保存会话
  static bool _sessionSaved = false;
  int selectIndex = -1;

  // 存储
  late HistoryStorage storage;

  late ListenableList<HttpRequest> container;
  late ProxyServer proxyServer;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    storage = widget.storage;
    container = widget.container;
    proxyServer = widget.proxyServer;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      storage.addListener(OnchangeListEvent(() {
        if (mounted) setState(() {});
      }));
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> children = [];
    if (!_sessionSaved && proxyServer.configuration.historyCacheTime == 0 && widget.historyTask.history == null) {
      //当前会话未保存，是否保存当前会话
      children.add(buildSaveSession());
    }

    var histories = storage.histories;
    for (int i = histories.length - 1; i >= 0; i--) {
      var entry = histories.elementAt(i);
      children.add(buildItem(context, i, entry));
    }

    return Scaffold(
        appBar: PreferredSize(
            preferredSize: const Size.fromHeight(38),
            child: AppBar(
              title: Text(localizations.historyRecord, style: const TextStyle(fontSize: 14)),
              actions: [
                IconButton(onPressed: import, icon: const Icon(Icons.input, size: 18), tooltip: localizations.import),
                const SizedBox(width: 3),
                HistoryCacheTime(proxyServer.configuration, onSelected: (val) {
                  if (val == 0) {
                    widget.container.removeListener(widget.historyTask);
                  } else {
                    widget.container.addListener(widget.historyTask);
                  }
                }),
                const SizedBox(width: 5)
              ],
            )),
        body: ListView.separated(
          itemCount: children.length,
          itemBuilder: (_, index) => children[index],
          separatorBuilder: (_, index) => const Divider(thickness: 0.3, height: 0),
        ));
  }

  //导入har
  import() async {
    final results = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['har']);
    if (results == null || results.files.isEmpty) {
      return;
    }

    var file = results.files.first;
    try {
      var historyItem = await storage.addHarFile(file.xFile);
      setState(() {
        toRequestsView(historyItem);
        FlutterToastr.show(localizations.importSuccess, context);
      });
    } catch (e, t) {
      logger.e('导入失败 $file', error: e, stackTrace: t);
      if (mounted) {
        FlutterToastr.show("${localizations.importFailed} $e", context);
      }
    }
  }

  //构建保存会话
  Widget buildSaveSession() {
    var name = formatDate(DateTime.now(), [mm, '-', d, ' ', HH, ':', nn, ':', ss]);

    return ListTile(
        dense: true,
        title: Text(name),
        subtitle: Text(localizations.historyUnSave),
        trailing: TextButton.icon(
          icon: const Icon(Icons.save),
          label: Text(localizations.save),
          onPressed: () async {
            widget.container.addListener(widget.historyTask);
            widget.historyTask.startTask();

            setState(() {
              _sessionSaved = true;
            });
          },
        ),
        onTap: () {});
  }

  //构建历史记录
  Widget buildItem(BuildContext rootContext, int index, HistoryItem item) {
    return GestureDetector(
        onSecondaryTapDown: (details) {
          setState(() {
            selectIndex = index;
          });
          showContextMenu(rootContext, details.globalPosition, items: [
            CustomPopupMenuItem(
                height: 35,
                child: Text(localizations.rename, style: const TextStyle(fontSize: 13)),
                onTap: () => renameHistory(storage, item)),
            CustomPopupMenuItem(
                height: 35,
                child: Text(localizations.export, style: const TextStyle(fontSize: 13)),
                onTap: () => export(item)),
            const PopupMenuDivider(height: 3),
            CustomPopupMenuItem(
                height: 35,
                child: Text(localizations.repeatAllRequests, style: const TextStyle(fontSize: 13)),
                onTap: () async {
                  var requests = (await storage.getRequests(item)).reversed;
                  //重发所有请求
                  _repeatAllRequests(requests.toList());
                }),
            const PopupMenuDivider(height: 3),
            CustomPopupMenuItem(
                height: 35,
                child: Text(localizations.delete, style: const TextStyle(fontSize: 13)),
                onTap: () {
                  if (item == widget.historyTask.history) {
                    widget.historyTask.cancelTask();
                  }
                  storage.removeHistory(index);
                  FlutterToastr.show(localizations.deleteSuccess, context);
                }),
          ]).whenComplete(() => setState(() => selectIndex = -1));
        },
        child: ListTile(
            selected: selectIndex == index,
            dense: true,
            title: Text(item.name),
            subtitle: Text(localizations.historySubtitle(item.requestLength, item.size)),
            onTap: () => toRequestsView(item)));
  }

  toRequestsView(HistoryItem item) {
    Navigator.pushNamed(context, "/request_list", arguments: {'item': item}).whenComplete(() async {
      if (item != widget.historyTask.history && item.requests != null && item.requestLength != item.requests?.length) {
        await widget.storage.flushRequests(item, item.requests!);
        setState(() {});
      }
      Future.delayed(const Duration(seconds: 60), () => item.requests = null);
    });
  }

  //重命名
  renameHistory(HistoryStorage storage, HistoryItem item) {
    String name = item.name;
    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            content: TextFormField(
              initialValue: name,
              decoration: InputDecoration(label: Text(localizations.name)),
              onChanged: (val) => name = val,
            ),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(context), child: Text(localizations.cancel)),
              TextButton(
                child: Text(localizations.save),
                onPressed: () {
                  if (name.isEmpty) {
                    FlutterToastr.show(localizations.historyEmptyName, context, position: 2);
                    return;
                  }
                  Navigator.maybePop(context);
                  setState(() {
                    item.name = name;
                    storage.refresh();
                  });
                },
              ),
            ],
          );
        });
  }

  //导出har
  export(HistoryItem item) async {
    //文件名称
    String fileName =
        '${item.name.contains("ProxyPin") ? '' : 'ProxyPin'}${item.name}.har'.replaceAll(" ", "_").replaceAll(":", "_");

    final String? path = await FilePicker.platform.saveFile(fileName: fileName);
    if (path == null) {
      return;
    }

    //获取请求
    List<HttpRequest> requests = await storage.getRequests(item);
    var file = await File(path).create();
    await Har.writeFile(requests, file, title: item.name);
    if (mounted) FlutterToastr.show(localizations.exportSuccess, context);
    Future.delayed(const Duration(seconds: 30), () => item.requests = null);
  }

  ///重发所有请求
  void _repeatAllRequests(Iterable<HttpRequest> requests) async {
    var localizations = AppLocalizations.of(context);

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
