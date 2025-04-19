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
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 请求屏蔽
/// @author wanghongen
/// 2024/02/02
class RequestBlockManager {
  static RequestBlockManager? _instance;
  bool enabled = true;
  List<RequestBlockItem> list = [];
  final File _storageFile;

  RequestBlockManager._(this._storageFile);

  ///单例
  static Future<RequestBlockManager> get instance async {
    if (_instance == null) {
      var file = await configFile();
      _instance = RequestBlockManager._(file);
      await _instance?._load();
    }
    return _instance!;
  }

  static Future<File> configFile() async {
    var directory = await getApplicationSupportDirectory().then((it) => it.path);
    var file = File('$directory${Platform.pathSeparator}request_block.json');
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return file;
  }

  ///加载
  Future<void> _load() async {
    var json = await _storageFile.readAsString();
    if (json.isEmpty) return;
    var config = jsonDecode(json);
    enabled = config['enabled'] == true;
    list.clear();
    config['list']?.forEach((element) {
      list.add(RequestBlockItem.fromJson(element));
    });
  }

  addBlockRequest(RequestBlockItem item) {
    list.add(item);
    flushConfig();
  }

  removeBlockRequest(int index) {
    list.removeAt(index);
    flushConfig();
  }

  /// 是否启用
  bool enableBlockRequest(String url) {
    if (!enabled) {
      return false;
    }
    return list.any((element) => element.match(url, BlockType.blockRequest));
  }

  bool enableBlockResponse(String url) {
    if (!enabled) {
      return false;
    }
    return list.any((element) => element.match(url, BlockType.blockResponse));
  }

  ///刷新配置
  Future<void> flushConfig() async {
    _storageFile.writeAsString(jsonEncode({'enabled': enabled, 'list': list}));
  }
}

enum BlockType {
  blockRequest('屏蔽请求'),
  blockResponse('屏蔽响应');

  //名称
  final String label;

  const BlockType(this.label);
  static BlockType nameOf(String name) {
    return BlockType.values.firstWhere((element) => element.name == name);
  }
}

class RequestBlockItem {
  bool enabled = true;
  String url;
  BlockType type;
  RegExp? urlReg;

  RequestBlockItem(this.enabled, this.url, this.type);

  //匹配url
  bool match(String url, BlockType blockType) {
    urlReg ??= RegExp(this.url.replaceAll("*", ".*"));
    return enabled && type == blockType && urlReg!.hasMatch(url);
  }

  factory RequestBlockItem.fromJson(Map<String, dynamic> json) {
    return RequestBlockItem(json['enabled'], json['url'], BlockType.nameOf(json['type']));
  }

  Map<String, dynamic> toJson() {
    return {'enabled': enabled, 'url': url, 'type': type.name};
  }

  @override
  String toString() {
    return toJson().toString();
  }
}
