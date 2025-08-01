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

import 'package:proxypin/network/components/manager/rewrite_rule.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/file_read.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/random.dart';

/// @author wanghongen
/// 2023/7/26
/// 请求重写
class RequestRewriteManager {
  static String separator = Platform.pathSeparator;

  //重写规则
  final Map<RequestRewriteRule, List<RewriteItem>> rewriteItemsCache = {};

  //单例
  static RequestRewriteManager? _instance;

  RequestRewriteManager._();

  static Future<RequestRewriteManager> get instance async {
    if (_instance == null) {
      var config = await _loadRequestRewriteConfig();
      _instance = RequestRewriteManager._();
      await _instance!.reload(config);
    }
    return _instance!;
  }

  bool enabled = true;
  List<RequestRewriteRule> rules = [];

  //重新加载配置
  Future<void> reload(Map<String, dynamic>? map) async {
    rewriteItemsCache.clear();
    if (map == null) {
      return;
    }

    enabled = map['enabled'] == true;
    List list = map['rules'] ?? [];
    rules.clear();
    for (var element in list) {
      try {
        rules.add(RequestRewriteRule.formJson(element));
      } catch (e) {
        logger.e('加载请求重写配置失败 $element', error: e);
      }
    }
  }

  ///重新加载请求重写
  Future<void> reloadRequestRewrite() async {
    var config = await _loadRequestRewriteConfig();
    reload(config);
  }

  ///同步配置
  Future<void> syncConfig(Map<String, dynamic>? config) async {
    if (config == null) {
      return;
    }

    rewriteItemsCache.clear();
    enabled = config['enabled'] == true;
    List list = config['rules'] ?? [];
    rules.clear();
    for (var element in list) {
      try {
        var rule = RequestRewriteRule.formJson(element);
        List list = element['items'] as List;
        List<RewriteItem> items = list.map((e) => RewriteItem.fromJson(e)).toList();
        await addRule(rule, items);
      } catch (e) {
        logger.e('加载请求重写配置失败 $element', error: e);
      }
    }
    flushRequestRewriteConfig();
  }

  /// 加载请求重写配置文件
  static Future<Map<String, dynamic>?> _loadRequestRewriteConfig() async {
    var home = await FileRead.homeDir();
    var file = File('${home.path}${Platform.pathSeparator}request_rewrite.json');
    var exits = await file.exists();
    if (!exits) {
      return null;
    }

    Map<String, dynamic> config = jsonDecode(await file.readAsString());
    logger.i('加载请求重写配置文件 [$file]');
    return config;
  }

  /// 保存请求重写配置文件
  Future<void> flushRequestRewriteConfig() async {
    var home = await FileRead.homeDir();
    var file = File('${home.path}${Platform.pathSeparator}request_rewrite.json');
    bool exists = await file.exists();
    if (!exists) {
      await file.create(recursive: true);
    }
    var json = jsonEncode(toJson());
    logger.i('刷新请求重写配置文件 ${file.path}');
    await file.writeAsString(json);
  }

  ///添加规则
  Future<void> addRule(RequestRewriteRule rule, List<RewriteItem> items) async {
    final home = await FileRead.homeDir();

    String rewritePath = "${separator}rewrite$separator${RandomUtil.randomString(16)}.json";
    var file = File(home.path + rewritePath);
    await file.create(recursive: true);
    file.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()));
    rule.rewritePath = rewritePath;

    rules.add(rule);
    rewriteItemsCache[rule] = items;
  }

  ///更新规则
  Future<void> updateRule(int index, RequestRewriteRule rule, List<RewriteItem>? items) async {
    rewriteItemsCache.remove(rules[index]);
    final home = await FileRead.homeDir();
    rule.updatePathReg();
    rules[index] = rule;

    if (items == null) {
      return;
    }
    bool isExist = rule.rewritePath != null;
    if (rule.rewritePath == null) {
      String rewritePath = "${separator}rewrite$separator${RandomUtil.randomString(16)}.json";
      rule.rewritePath = rewritePath;
    }

    File file = File(home.path + rule.rewritePath!);
    if (!isExist) {
      await file.create(recursive: true);
    }

    await file.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()));
    rewriteItemsCache[rule] = items;
  }

  Future<void> removeIndex(List<int> indexes) async {
    for (var i in indexes) {
      var rule = rules.removeAt(i);
      rewriteItemsCache.remove(rule); //删除缓存
      if (rule.rewritePath != null) {
        File home = await FileRead.homeDir();
        try {
          await File(home.path + rule.rewritePath!).delete();
        } catch (e) {
          logger.e('删除请求重写配置文件失败 ${home.path + rule.rewritePath!}', error: e);
        }
        rule.rewritePath = null;
      }
    }
  }

  RequestRewriteRule getRequestRewriteRule(HttpRequest request, RuleType type) {
    var url = request.domainPath;
    for (var rule in rules) {
      if (rule.match(url) && rule.type == type) {
        return rule;
      }
    }

    return RequestRewriteRule(type: type, url: url);
  }

  RequestRewriteRule? getRewriteRule(String? url, List<RuleType> types) {
    if (url == null || !enabled) {
      return null;
    }
    for (var rule in rules) {
      if (rule.match(url) && types.contains(rule.type)) {
        return rule;
      }
    }
    return null;
  }

  /// 获取重写规则
  Future<List<RewriteItem>?> getRewriteItems(RequestRewriteRule rule) async {
    if (rewriteItemsCache.containsKey(rule)) {
      return rewriteItemsCache[rule]!;
    }
    if (rule.rewritePath == null) {
      return null;
    }

    final home = await FileRead.homeDir();
    List<RewriteItem> items = [];
    try {
      var json = await File(home.path + rule.rewritePath!).readAsString();
      List? list = jsonDecode(json);
      list?.forEach((element) => items.add(RewriteItem.fromJson(element)));
      rewriteItemsCache[rule] = items;
    } catch (e) {
      logger.e('加载请求重写配置文件失败 ${home.path + rule.rewritePath!}', error: e);
    }
    return items;
  }

  Map<String, Object> toJson() {
    return {
      'enabled': enabled,
      'rules': rules.map((e) => e.toJson()).toList(),
    };
  }

  Future<Map<String, dynamic>> toFullJson() async {
    var rulesJson = [];
    for (var rule in rules) {
      var json = rule.toJson();
      json['items'] = await getRewriteItems(rule);
      rulesJson.add(json);
    }

    return {
      'enabled': enabled,
      'rules': rulesJson,
    };
  }
}
