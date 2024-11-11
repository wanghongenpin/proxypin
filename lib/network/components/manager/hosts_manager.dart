/*
 * Copyright 2024 Hongen Wang All rights reserved.
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

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:path_provider/path_provider.dart';
import 'package:proxypin/network/util/random.dart';

/// Hosts manager
/// @author wanghongen
class HostsManager {
  static String separator = Platform.pathSeparator;

  static HostsManager? _instance;
  bool enabled = true;
  final List<HostsItem> list = [];

  final Map<String, List<HostsItem>> _folderMap = {};

  HostsManager._();

  /// Singleton
  static Future<HostsManager> get instance async {
    if (_instance == null) {
      _instance = HostsManager._();
      await _instance?.load();
    }
    return _instance!;
  }

  static File? _configFile;

  static Future<String> homePath() async {
    if (Platform.isMacOS) {
      return await DesktopMultiWindow.invokeMethod(0, "getApplicationSupportDirectory");
    }
    return await getApplicationSupportDirectory().then((it) => it.path);
  }

  static Future<File> get configFile async {
    if (_configFile != null) return _configFile!;

    final path = await homePath();
    var file = File('$path${separator}hosts.json');
    if (!await file.exists()) {
      await file.create();
    }
    _configFile = file;
    return file;
  }

  /// Load
  Future<void> load() async {
    var json = await (await configFile).readAsString();
    if (json.isEmpty) return;

    var config = jsonDecode(json);
    enabled = config['enabled'] == true;
    list.clear();
    config['list']?.forEach((element) {
      var hostsItem = HostsItem.fromJson(element);

      if (hostsItem.parent != null) {
        var children = _folderMap[hostsItem.parent!] ??= [];
        children.add(hostsItem);
        return;
      }

      if (hostsItem.isFolder) {
        _folderMap[hostsItem.id] ??= [];
      }
      list.add(hostsItem);
    });
  }

  /// Save
  Future<void> flushConfig() async {
    var config = List.from(list);
    for (var values in _folderMap.values) {
      config.addAll(values);
    }

    var json = jsonEncode({
      'enabled': enabled,
      'list': config.map((e) => e.toJson()).toList(),
    });
    (await configFile).writeAsString(json);
  }

  List<HostsItem> getFolderList(String parent) {
    return _folderMap[parent] ?? [];
  }

  Future<void> addHosts(HostsItem item) async {
    if (item.parent == null) {
      list.add(item);
    } else {
      var children = _folderMap[item.parent!] ??= [];
      children.add(item);
    }
  }

  Future<HostsItem?> getHosts(String host) async {
    if (!enabled) return null;

    for (var item in list) {
      if (!item.enabled) continue;

      if (item.isFolder) {
        var list = _folderMap[item.id];
        if (list == null) continue;
        for (var it in list) {
          if (it.enabled && it.match(host)) {
            return it;
          }
        }
        continue;
      }

      if (item.match(host)) {
        return item;
      }
    }

    return null;
  }

  removeHosts(Iterable<HostsItem> items) async {
    if (items.isEmpty) return;
    for (var item in items) {
      if (item.parent == null) {
        list.remove(item);
        if (item.isFolder) {
          _folderMap.remove(item.id);
        }
      } else {
        var children = _folderMap[item.parent!] ??= [];
        children.remove(item);
      }
    }
    flushConfig();
  }
}

class HostsItem {
  bool enabled = true;
  bool isFolder = false;
  final String id;
  String? parent;
  String host;
  String? toAddress;
  RegExp? _hostReg;

  HostsItem({String? id, required this.host, this.toAddress, required this.enabled, this.isFolder = false, this.parent})
      : id = id ?? generateId();

  static String generateId() {
    return DateTime.now().millisecondsSinceEpoch.toRadixString(36) + RandomUtil.randomString(4);
  }

  //匹配url
  bool match(String domain) {
    if (host != _hostReg?.pattern) _hostReg = null;
    _hostReg ??= RegExp(host.replaceAll("*", ".*"));
    return _hostReg!.hasMatch(domain);
  }

  factory HostsItem.fromJson(Map<String, dynamic> json) {
    return HostsItem(
      id: json['id'],
      host: json['host'],
      toAddress: json['toAddress'],
      enabled: json['enabled'],
      parent: json['parent'],
      isFolder: json['isFolder'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'parent': parent,
      'enabled': enabled,
      'isFolder': isFolder,
      'host': host,
      'toAddress': toAddress,
    };
  }
}
