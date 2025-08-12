import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:path_provider/path_provider.dart';

import '../../util/logger.dart';
import '../../util/random.dart';

class RequestMapManager {
  static RequestMapManager? _instance;

  static String separator = Platform.pathSeparator;

  RequestMapManager._internal();

  final Map<RequestMapRule, RequestMapItem> _mapItemsCache = {};

  bool enabled = true;

  //存储所有的请求映射规则
  List<RequestMapRule> rules = [];

  ///单例
  static Future<RequestMapManager> get instance async {
    if (_instance == null) {
      _instance = RequestMapManager._internal();
      await _instance?.reloadConfig();
    }
    return _instance!;
  }

  //添加规则
  Future<void> addRule(RequestMapRule rule, RequestMapItem item) async {
    final path = await homePath();
    String itemPath = "${separator}request_map$separator${RandomUtil.randomString(16)}.json";
    var file = File(path + itemPath);
    await file.create(recursive: true);
    final itemJson = jsonEncode(item.toJson());
    file.writeAsString(itemJson);

    rule.itemPath = itemPath;
    _mapItemsCache[rule] = item;
    rules.add(rule);

    await flushConfig();
  }

  //update rule
  Future<void> updateRule(RequestMapRule rule, RequestMapItem item) async {
    rule.updatePathReg();
    if (rule.itemPath != null) {
      final path = await homePath();
      var file = File('$path${rule.itemPath}');
      await file.writeAsString(jsonEncode(item.toJson()));
    }
    _mapItemsCache[rule] = item;
    await flushConfig();
  }

  //删除规则
  Future<void> deleteRule(int index) async {
    var item = rules.removeAt(index);
    final home = await homePath();
    File(home + item.itemPath!).delete();
  }

  //根据url和类型查找匹配的规则
  RequestMapRule? findMatch(String url) {
    for (var rule in rules) {
      if (rule.match(url)) {
        return rule;
      }
    }
    return null;
  }

  Future<RequestMapItem?> getMapItem(RequestMapRule rule) async {
    if (_mapItemsCache.containsKey(rule)) {
      return _mapItemsCache[rule];
    }

    if (rule.itemPath != null) {
      final path = await homePath();
      var file = File('$path$separator${rule.itemPath}');
      if (await file.exists()) {
        var content = await file.readAsString();
        if (content.isNotEmpty) {
          var item = RequestMapItem.fromJson(jsonDecode(content));
          _mapItemsCache[rule] = item;
          return item;
        }
      }
    }
    return null;
  }

  static String? _homePath;

  static Future<String> homePath() async {
    if (_homePath != null) {
      return _homePath!;
    }

    if (Platform.isMacOS) {
      _homePath = await DesktopMultiWindow.invokeMethod(0, "getApplicationSupportDirectory");
    } else {
      _homePath = await getApplicationSupportDirectory().then((it) => it.path);
    }
    return _homePath!;
  }

  static Future<File> get _path async {
    final path = await homePath();
    var file = File('$path${Platform.pathSeparator}request_map.json');
    if (!await file.exists()) {
      await file.create();
    }
    return file;
  }

  ///重新加载配置
  Future<void> reloadConfig() async {
    List<RequestMapRule> list = [];
    var file = await _path;
    logger.d("reload request map config from ${file.path}");

    if (await file.exists()) {
      var content = await file.readAsString();
      if (content.isEmpty) {
        return;
      }
      var config = jsonDecode(content);
      enabled = config['enabled'] == true;
      for (var entry in config['list']) {
        list.add(RequestMapRule.fromJson(entry));
      }
    }
    rules = list;
    _mapItemsCache.clear();
  }

  ///保存配置
  Future<void> flushConfig() async {
    var file = await _path;
    if (!await file.exists()) {
      await file.create(recursive: true);
    }

    var config = {
      'enabled': enabled,
      'list': rules.map((e) => e.toJson()).toList(),
    };

    await file.writeAsString(jsonEncode(config));
  }
}

enum RequestMapType {
  local("本地"),
  script("脚本"),
  ;

  //名称
  final String label;

  const RequestMapType(this.label);

  static RequestMapType fromName(String name) {
    return values.firstWhere((element) => element.name == name || element.label == name);
  }
}

class RequestMapRule {
  bool enabled;
  RequestMapType type;

  String? name;
  String url;
  RegExp _urlReg;
  String? itemPath;

  RequestMapRule({this.enabled = true, this.name, required this.url, required this.type, this.itemPath})
      : _urlReg = RegExp(url.replaceAll("*", ".*").replaceFirst('?', '\\?'));

  bool match(String url) {
    if (enabled) {
      return _urlReg.hasMatch(url);
    }
    return false;
  }

  /// 从json中创建
  factory RequestMapRule.fromJson(Map<dynamic, dynamic> map) {
    return RequestMapRule(
        enabled: map['enabled'] == true,
        name: map['name'],
        url: map['url'],
        type: RequestMapType.fromName(map['type']),
        itemPath: map['itemPath']);
  }

  void updatePathReg() {
    _urlReg = RegExp(url.replaceAll("*", ".*").replaceFirst('?', '\\?'));
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'enabled': enabled,
      'url': url,
      'type': type.name,
      'itemPath': itemPath,
    };
  }
}

class RequestMapItem {
  String? script;

  int? statusCode;
  Map<String, String>? headers;

  //body
  String? body;

  String? bodyType;

  String? bodyFile;

  RequestMapItem({this.script, this.statusCode, this.headers, this.body, this.bodyType, this.bodyFile});

  /// 从json中创建
  factory RequestMapItem.fromJson(Map<dynamic, dynamic> map) {
    return RequestMapItem(
      script: map['script'],
      statusCode: map['statusCode'],
      headers: (map['headers'] as Map?)?.cast<String, String>(),
      body: map['body'],
      bodyType: map['bodyType'],
      bodyFile: map['bodyFile'],
    );
  }

  Map<String, Object?> toJson() {
    return {
      'script': script,
      'statusCode': statusCode,
      'headers': headers,
      'body': body,
      'bodyType': bodyType,
      'bodyFile': bodyFile,
    };
  }
}

enum MapBodyType {
  text("文本"),
  file("文件");

  final String label;

  const MapBodyType(this.label);
}
