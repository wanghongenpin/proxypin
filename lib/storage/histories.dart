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
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:date_format/date_format.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/path.dart';
import 'package:proxypin/utils/files.dart';
import 'package:proxypin/utils/har.dart';
import 'package:proxypin/utils/listenable_list.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

///历史存储
///@Author WangHongEn
class HistoryStorage {
  static HistoryStorage? _instance;
  final File _storageFile;

  HistoryStorage._internal(this._storageFile);

  static final ListenableList<HistoryItem> _histories = ListenableList();

  ///单例
  static Future<HistoryStorage> get instance async {
    if (_instance == null) {
      var file = await Paths.getPath("histories.json");
      _instance = HistoryStorage._internal(file);
      await _instance!._init();
    }
    return _instance!;
  }

  //初始化
  Future<void> _init() async {
    if (await _storageFile.exists()) {
      var content = await _storageFile.readAsString();
      if (content.trim().isEmpty) {
        return;
      }
      try {
        var list = jsonDecode(content) as List<dynamic>;
        for (var entry in list) {
          _histories.add(HistoryItem.formJson(entry));
        }
      } catch (e) {
        logger.e("历史记录解析错误", error: e);
      }
    }
  }

  static Future<String> _homePath() async {
    final home = await getApplicationSupportDirectory();
    return '${home.path}${Platform.pathSeparator}history';
  }

  /// 获取历史记录
  List<HistoryItem> get histories {
    return _histories.source;
  }

  addListener(ListenerListEvent<HistoryItem> listener) {
    _histories.addListener(listener);
  }

  ///打开文件
  static Future<File> openFile(String name) async {
    final homePath = await _homePath();
    var file = File('$homePath${Platform.pathSeparator}$name');
    return file.create(recursive: true);
  }

  /// 添加历史记录
  HistoryItem addHistory(String name, File file, int requestLength) {
    var historyItem = HistoryItem(name, file.path, requestLength, 0);
    _histories.add(historyItem);
    refresh();
    return historyItem;
  }

  int getIndex(HistoryItem item) {
    return _histories.indexOf(item);
  }

  //更新
  updateHistory(int index, HistoryItem item) async {
    _histories.update(index, item);
    refresh();
  }

  //获取
  HistoryItem getHistory(int index) {
    return _histories.source[index];
  }

  Future<void> refresh() async {
    await _storageFile.writeAsString(jsonEncode(_histories.source));
  }

  ///删除
  Future<void> removeHistory(int index) async {
    var history = _histories.removeAt(index);
    logger.i('删除历史记录 $history');
    final homePath = await _homePath();
    var file = File('$homePath${Platform.pathSeparator}${Files.getName(history.path)}');
    file.delete();
    await refresh();
  }

  //获取请求列表
  Future<List<HttpRequest>> getRequests(HistoryItem history) async {
    if (history.requests == null) {
      final homePath = await _homePath();
      String path = '$homePath${Platform.pathSeparator}${Files.getName(history.path)}';
      var file = File(path);
      history.requests = await Har.readFile(file);
      history.requestLength = history.requests!.length;
      file.length().then((size) => history.fileSize = size);
    }

    return history.requests!;
  }

  ///刷新requests
  Future<void> flushRequests(HistoryItem history, List<HttpRequest> requests) async {
    logger.i("刷新历史记录 $history");
    final homePath = await _homePath();
    String path = '$homePath${Platform.pathSeparator}${Files.getName(history.path)}';
    var file = File(path);
    for (int i = 0; i < requests.length; i++) {
      var request = requests[i];
      var har = Har.toHar(request);
      await file.writeAsString("${jsonEncode(har)},\n", mode: i == 0 ? FileMode.write : FileMode.append);
    }

    history.requestLength = requests.length;
    await file.length().then((size) => history.fileSize = size);
    await refresh();
  }

  //添加历史
  Future<HistoryItem> addHarFile(XFile file) async {
    var readAsBytes = await file.readAsString();
    var json = jsonDecode(readAsBytes);
    var log = json['log'];
    String name = formatDate(DateTime.now(), [mm, '-', d, ' ', HH, ':', nn, ':', ss]);
    List? pages = log['pages'] as List;
    if (pages.isNotEmpty) {
      name = pages.first['title'];
    }

    //解析请求
    List entries = log['entries'];
    var list = entries.map((e) => Har.toRequest(e)).toList();

    //保存文件
    var historyFile = await HistoryStorage.openFile("${DateTime.now().millisecondsSinceEpoch}.txt");
    var open = await historyFile.open(mode: FileMode.append);
    for (var request in list) {
      await open.writeString(jsonEncode(Har.toHar(request)));
      await open.writeString(",\n");
    }
    return addHistory(name, historyFile, list.length);
  }
}

class HistoryTask extends ListenerListEvent<HttpRequest> {
  HistoryItem? history;
  Timer? timer;
  final Queue writeList = Queue();

  RandomAccessFile? open;
  bool locked = false;

  static HistoryTask? _instance;

  final Configuration configuration;
  final ListenableList<HttpRequest> sourceList;

  HistoryTask(this.configuration, this.sourceList) {
    if (configuration.historyCacheTime != 0) {
      sourceList.addListener(this);
      Future.delayed(const Duration(seconds: 3), () => cleanHistory());
    }
  }

  static HistoryTask ensureInstance(Configuration configuration, ListenableList<HttpRequest> sourceList) {
    return _instance ??= HistoryTask(configuration, sourceList);
  }

  //清理历史数据
  cleanHistory() async {
    if (configuration.historyCacheTime == 0) {
      return;
    }
    var overdueTime = DateTime.now().subtract(Duration(days: configuration.historyCacheTime));
    var historyStorage = await HistoryStorage.instance;
    var histories = historyStorage.histories;
    for (int i = 0; i < histories.length; i++) {
      if (histories.elementAt(i).createTime.isBefore(overdueTime)) {
        await historyStorage.removeHistory(i);
        i--;
      }
    }
  }

  @override
  void onAdd(HttpRequest item) {
    if (history == null) {
      startTask();
      return;
    }
    writeList.add(item);
  }

  @override
  void onRemove(HttpRequest item) => resetList();

  @override
  void onBatchRemove(List<HttpRequest> items) => resetList();

  @override
  clear() => resetList();

  resetList() async {
    locked = true;
    await open?.lock().timeout(Duration(seconds: 3), onTimeout: () => open!.unlock());
    open = await open?.truncate(0);
    await open?.setPosition(0);
    history?.requestLength = 0;
    history?.requests = null;
    writeList.clear();
    writeList.addAll(sourceList.source);
    locked = false;
    open?.unlock();
  }

  cancelTask() {
    timer?.cancel();
    timer = null;
    open?.close();
    open = null;
    history = null;
    sourceList.removeListener(this);
    writeList.clear();
  }

  //写入任务
  Future<void> startTask() async {
    if (history != null || locked) return;
    locked = true;

    HistoryStorage storage = await HistoryStorage.instance;
    var name = formatDate(DateTime.now(), [mm, '-', d, ' ', HH, ':', nn, ':', ss]);
    File file = await HistoryStorage.openFile("${DateTime.now().millisecondsSinceEpoch}.txt");
    history = storage.addHistory(name, file, 0);
    writeList.clear();
    writeList.addAll(sourceList.source);
    locked = false;

    open = await file.open(mode: FileMode.append);
    timer = Timer.periodic(const Duration(seconds: 5), (it) => writeTask());
  }

  //写入任务
  writeTask() async {
    if (writeList.isEmpty) {
      return;
    }

    bool changed = false;
    while (writeList.isNotEmpty && !locked) {
      var request = writeList.removeFirst();
      var har = Har.toHar(request);

      await open?.writeString("${jsonEncode(har)},\n");

      history!.requestLength++;
      changed = true;
    }

    if (!changed) return;
    history!.fileSize = await open!.length();
    history!.requests = null;
    var historyStorage = await HistoryStorage.instance;
    historyStorage.updateHistory(historyStorage.getIndex(history!), history!);
  }
}

/// 历史记录
class HistoryItem {
  String name;
  final String path; // 文件路径
  int requestLength = 0; // 请求数量
  int? fileSize; // 文件大小
  DateTime createTime = DateTime.now();

  List<HttpRequest>? requests;

  HistoryItem(this.name, this.path, this.requestLength, this.fileSize, {DateTime? createTime})
      : createTime = createTime ?? DateTime.now();

  //json反序列化
  factory HistoryItem.formJson(Map<String, dynamic> map) {
    return HistoryItem(map['name'], map['path'], map['requestLength'], map['fileSize'],
        createTime: map['createTime'] == null ? null : DateTime.fromMillisecondsSinceEpoch(map['createTime']));
  }

  //json序列化
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'requestLength': requestLength,
      'fileSize': fileSize,
      'createTime': createTime.millisecondsSinceEpoch,
    };
  }

  //获取文件大小
  String get size {
    if (this.fileSize == null) {
      return "";
    }

    int fileSize = this.fileSize!;
    if (fileSize > 1024 * 1024) {
      return "${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB";
    }

    return "${(fileSize / 1024).toStringAsFixed(1)}KB";
  }

  @override
  String toString() {
    return "$path $requestLength $fileSize";
  }
}
