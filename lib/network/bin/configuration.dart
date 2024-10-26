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

import 'package:proxypin/network/host_port.dart';
import 'package:proxypin/network/util/file_read.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/system_proxy.dart';
import 'package:proxypin/utils/platform.dart';

class Configuration {
  ///代理相关配置
  int port = 9099;

  //是否启用https抓包
  bool enableSsl = false;

  //是否设置系统代理
  bool enableSystemProxy = true;

  //代理忽略域名
  String proxyPassDomains = SystemProxy.proxyPassDomains;

  //外部代理
  ProxyInfo? externalProxy;

  //白名单应用
  List<String> appWhitelist = [];

  //白名单应用是否启用
  bool appWhitelistEnabled = true;

  //应用黑名单
  List<String>? appBlacklist;

  //远程连接 不持久化保存
  String? remoteHost;

  bool enabledHttp2 = false; //

  //历史记录缓存时间
  int historyCacheTime = 0;

  //默认是否启动
  bool startup = false;

  Configuration._();

  /// 单例
  static Configuration? _instance;

  static Future<Configuration> get instance async {
    if (_instance == null) {
      try {
        var loadConfig = await _loadConfig();
        _instance = Configuration.fromJson(loadConfig);
      } catch (e) {
        logger.e('初始化配置失败', error: e, stackTrace: StackTrace.current);
        _instance = Configuration._();
      }
    }
    return _instance!;
  }

  /// 加载配置
  Configuration.fromJson(Map<String, dynamic> config) {
    port = config['port'] ?? port;
    enableSsl = config['enableSsl'] == true;
    startup = config['startup'] ?? Platforms.isDesktop();
    enableSystemProxy = config['enableSystemProxy'] ?? (config['enableDesktop'] ?? true);
    proxyPassDomains = config['proxyPassDomains'] ?? SystemProxy.proxyPassDomains;
    historyCacheTime = config['historyCacheTime'] ?? 0;
    if (config['externalProxy'] != null) {
      externalProxy = ProxyInfo.fromJson(config['externalProxy']);
    }
    appWhitelist = List<String>.from(config['appWhitelist'] ?? []);
    appWhitelistEnabled = config['appWhitelistEnabled'] ?? true;
    appBlacklist = config['appBlacklist'] == null ? null : List<String>.from(config['appBlacklist']);
    HostFilter.whitelist.load(config['whitelist']);
    HostFilter.blacklist.load(config['blacklist']);
  }

  /// 配置文件
  static Future<File> configFile() async {
    var separator = Platform.pathSeparator;
    var home = await FileRead.homeDir();
    return File("${home.path}${separator}config.cnf");
  }

  /// 刷新配置文件
  flushConfig() async {
    var file = await configFile();
    var exists = await file.exists();
    if (!exists) {
      file = await file.create(recursive: true);
    }
    HostFilter.whitelist.toJson();
    HostFilter.blacklist.toJson();
    var json = jsonEncode(toJson());
    logger.d('Refresh configuration file $runtimeType ${toJson()}');
    file.writeAsString(json);
  }

  /// 加载配置文件
  static Future<Map<String, dynamic>> _loadConfig() async {
    var file = await configFile();
    var exits = await file.exists();
    if (!exits) {
      return {};
    }

    Map<String, dynamic> config = jsonDecode(await file.readAsString());
    logger.i('加载配置文件 [$file]');
    return config;
  }

  Map<String, dynamic> toJson() {
    return {
      'port': port,
      'enableSsl': enableSsl,
      'startup': startup,
      'enableSystemProxy': enableSystemProxy,
      'proxyPassDomains': proxyPassDomains,
      'externalProxy': externalProxy?.toJson(),
      'appWhitelist': appWhitelist,
      'appWhitelistEnabled': appWhitelistEnabled,
      'appBlacklist': appBlacklist,
      'historyCacheTime': historyCacheTime,
      'whitelist': HostFilter.whitelist.toJson(),
      'blacklist': HostFilter.blacklist.toJson(),
    };
  }
}
