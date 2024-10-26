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

import 'dart:io';

import 'package:proxypin/network/host_port.dart';
import 'package:proxypin/utils/ip.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxy_manager/proxy_manager.dart';

/// @author wanghongen
/// 2023/7/26
class SystemProxy {
  static SystemProxy? _instance;

  ///单例
  static SystemProxy get instance {
    if (_instance == null) {
      if (Platform.isMacOS) {
        _instance = MacSystemProxy();
      } else if (Platform.isWindows) {
        _instance = WindowsSystemProxy();
      } else if (Platform.isLinux) {
        _instance = LinuxSystemProxy();
      } else {
        _instance = SystemProxy();
      }
    }
    return _instance!;
  }

  ///获取代理忽略地址
  static String get proxyPassDomains {
    if (Platform.isMacOS) {
      return '192.168.0.0/16;10.0.0.0/8;172.16.0.0/12;127.0.0.1;localhost;*.local;timestamp.apple.com';
    }
    if (Platform.isWindows) {
      return '192.168.0.*;10.0.0.*;172.16.0.*;127.0.0.1;localhost;*.local;<local>';
    }
    return '';
  }

  ///获取系统代理
  static Future<ProxyInfo?> getSystemProxy(ProxyTypes types) async {
    return instance._getSystemProxy(types);
  }

  ///设置系统代理
  static Future<void> setSystemProxy(int port, bool sslSetting, String proxyPassDomains) async {
    await instance._setSystemProxy(port, sslSetting, proxyPassDomains);
  }

  ///设置Https代理启用状态
  static void setSslProxyEnable(bool proxyEnable, port) {
    instance._setSslProxyEnable(proxyEnable, port);
  }

  /// 设置系统代理
  /// @param sslSetting 是否设置https代理只在mac中有效
  static Future<void> setSystemProxyEnable(int port, bool enable, bool sslSetting,
      {required String passDomains}) async {
    //启用系统代理
    if (enable) {
      await setSystemProxy(port, sslSetting, passDomains);
      return;
    }

    instance._setProxyEnable(enable, sslSetting);
  }

  ///设置代理忽略地址
  static Future<void> setProxyPassDomains(String proxyPassDomains) async {
    instance._setProxyPassDomains(proxyPassDomains);
  }

  //子类抽象方法

  ///获取系统代理
  Future<ProxyInfo?> _getSystemProxy(ProxyTypes types) async {
    return null;
  }

  ///设置系统代理
  Future<void> _setSystemProxy(int port, bool sslSetting, String proxyPassDomains) async {
    ProxyManager manager = ProxyManager();
    await manager.setAsSystemProxy(sslSetting ? ProxyTypes.https : ProxyTypes.http, "127.0.0.1", port);
    setProxyPassDomains(proxyPassDomains);
  }

  ///设置代理是否启用
  Future<void> _setProxyEnable(bool proxyEnable, bool sslSetting) async {
    ProxyManager manager = ProxyManager();
    await manager.cleanSystemProxy();
  }

  ///设置Https代理启用状态
  Future<bool> _setSslProxyEnable(bool proxyEnable, int port) async {
    return false;
  }

  ///设置代理忽略地址
  Future<void> _setProxyPassDomains(String proxyPassDomains) async {}
}

class MacSystemProxy implements SystemProxy {
  static String? _hardwarePort;

  ///获取系统代理
  @override
  Future<ProxyInfo?> _getSystemProxy(ProxyTypes proxyTypes) async {
    _hardwarePort = _hardwarePort ?? await hardwarePort();

    var result = await Process.run('bash', [
      '-c',
      'networksetup ${proxyTypes == ProxyTypes.http ? '-getwebproxy' : '-getsecurewebproxy'} $_hardwarePort'
    ]).then((results) => results.stdout.toString().split('\n'));

    var proxyEnable = result.firstWhere((item) => item.contains('Enabled')).trim().split(": ")[1];
    if (proxyEnable == 'No') {
      return null;
    }

    var proxyServer = result.firstWhere((item) => item.contains('Server')).trim().split(": ")[1];
    var proxyPort = result.firstWhere((item) => item.contains('Port')).trim().split(": ")[1];
    if (proxyEnable == 'Yes' && proxyServer.isNotEmpty) {
      return ProxyInfo.of(proxyServer, int.parse(proxyPort));
    }
    return null;
  }

  ///mac设置代理地址
  @override
  Future<bool> _setSystemProxy(int port, bool sslSetting, String proxyPassDomains) async {
    _hardwarePort = _hardwarePort ?? await hardwarePort();
    var results = await Process.run('bash', [
      '-c',
      _concatCommands([
        'networksetup -setwebproxy $_hardwarePort 127.0.0.1 $port',
        sslSetting == true ? 'networksetup -setsecurewebproxy $_hardwarePort 127.0.0.1 $port' : '',
        'networksetup -setproxybypassdomains $_hardwarePort ${proxyPassDomains.replaceAll(";", " ")}',
        'networksetup -setsocksfirewallproxystate $_hardwarePort off',
      ])
    ]);
    print('set proxyServer, name: $_hardwarePort, exitCode: ${results.exitCode}, stdout: ${results.stdout}');
    return results.exitCode == 0;
  }

  ///设置Https代理
  @override
  Future<bool> _setSslProxyEnable(bool proxyEnable, port) async {
    var name = _hardwarePort ?? await hardwarePort();

    var results = await Process.run('bash', [
      '-c',
      proxyEnable
          ? 'networksetup -setsecurewebproxy $name 127.0.0.1 $port'
          : 'networksetup -setsecurewebproxystate $name off'
    ]);
    return results.exitCode == 0;
  }

  ///mac获取当前网络名称
  static Future<String> hardwarePort() async {
    var name = await networkName();
    var results = await Process.run('bash', [
      '-c',
      'networksetup -listnetworkserviceorder |grep "Device: $name" -A 1 |grep "Hardware Port" |awk -F ": " \'{print \$2}\''
    ]);
    return results.stdout.toString().split(", ")[0];
  }

  ///设置代理忽略地址
  @override
  Future<void> _setProxyPassDomains(String proxyPassDomains) async {
    _hardwarePort ??= await hardwarePort();
    var results = await Process.run(
        'bash', ['-c', 'networksetup -setproxybypassdomains $_hardwarePort ${proxyPassDomains.replaceAll(";", " ")}']);
    print('set proxyPassDomains, name: $_hardwarePort, exitCode: ${results.exitCode}, stdout: ${results.stdout}');
  }

  ///mac设置代理是否启用
  @override
  Future<void> _setProxyEnable(bool proxyEnable, bool sslSetting) async {
    var proxyMode = proxyEnable ? 'on' : 'off';
    _hardwarePort ??= await hardwarePort();
    print('set proxyEnable: $proxyEnable, name: $_hardwarePort');

    await Process.run('bash', [
      '-c',
      _concatCommands([
        'networksetup -setwebproxystate $_hardwarePort $proxyMode',
        sslSetting ? 'networksetup -setsecurewebproxystate $_hardwarePort $proxyMode' : ''
      ])
    ]);
  }

  static _concatCommands(List<String> commands) {
    return commands.where((element) => element.isNotEmpty).join(' && ');
  }
}

class WindowsSystemProxy extends SystemProxy {
  ///设置windows代理是否启用
  @override
  Future<void> _setProxyEnable(bool proxyEnable, bool sslSetting) async {
    await _internetSettings('add', ['ProxyEnable', '/t', 'REG_DWORD', '/f', '/d', proxyEnable ? '1' : '0']);
  }

  ///获取系统代理
  @override
  Future<ProxyInfo?> _getSystemProxy(ProxyTypes types) async {
    var results = await _internetSettings('query', ['ProxyEnable']);

    var proxyEnableLine = results.split('\r\n').where((item) => item.contains('ProxyEnable')).first.trim();
    if (proxyEnableLine.substring(proxyEnableLine.length - 1) != '1') {
      return null;
    }

    return _internetSettings('query', ['ProxyServer']).then((results) {
      var proxyServerLine = results.split('\r\n').where((item) => item.contains('ProxyServer')).firstOrNull;
      var proxyServerLineSplits = proxyServerLine?.split(RegExp(r"\s+"));

      if (proxyServerLineSplits == null || proxyServerLineSplits.length < 2) {
        return null;
      }

      var proxyLine = proxyServerLineSplits[proxyServerLineSplits.length - 1];
      if (proxyLine.startsWith("http://") || proxyLine.startsWith("https:///")) {
        proxyLine = proxyLine.replaceFirst("http://", "").replaceFirst("https:///", "");
      }

      var proxyServer = proxyLine.split(":")[0];
      var proxyPort = proxyLine.split(":")[1];
      print("$proxyServer:$proxyPort");
      return ProxyInfo.of(proxyServer, int.parse(proxyPort));
    }).catchError((e) {
      print(e);
      return null;
    });
  }

  ///设置代理忽略地址
  @override
  Future<void> _setProxyPassDomains(String proxyPassDomains) async {
    var results = await _internetSettings('add', ['ProxyOverride', '/t', 'REG_SZ', '/d', proxyPassDomains, '/f']);
    print('set proxyPassDomains, stdout: $results');
  }

  static Future<String> _internetSettings(String cmd, List<String> args) async {
    return Process.run('reg', [
      cmd,
      'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings',
      '/v',
      ...args,
    ]).then((results) => results.stdout.toString());
  }
}

class LinuxSystemProxy extends SystemProxy {
  @override
  Future<void> _setSystemProxy(int port, bool sslSetting, String proxyPassDomains) async {
    ProxyManager manager = ProxyManager();

    await manager.setAsSystemProxy(ProxyTypes.http, "127.0.0.1", port);
    if (sslSetting) await manager.setAsSystemProxy(ProxyTypes.https, "127.0.0.1", port);

    SystemProxy.setProxyPassDomains(proxyPassDomains);
  }

  ///linux 获取代理
  @override
  Future<ProxyInfo?> _getSystemProxy(ProxyTypes types) async {
    var mode = await Process.run("gsettings", ["get", "org.gnome.system.proxy", "mode"])
        .then((value) => value.stdout.toString().trim());
    if (mode.contains("manual")) {
      var hostFuture = Process.run("gsettings", ["get", "org.gnome.system.proxy.${types.name}", "host"])
          .then((value) => value.stdout.toString().trim());
      var portFuture = Process.run("gsettings", ["get", "org.gnome.system.proxy.${types.name}", "port"])
          .then((value) => value.stdout.toString().trim());

      return Future.wait([hostFuture, portFuture]).then((value) {
        var host = Strings.trimWrap(value[0], "'");
        var port = Strings.trimWrap(value[1], "'");
        if (host.isNotEmpty && port.isNotEmpty) {
          return ProxyInfo.of(host, int.parse(port));
        }
        return null;
      });
    }
    return null;
  }
}

void main() async {
  // single instance
  ProxyManager manager = ProxyManager();
// set a http proxy
  await manager.setAsSystemProxy(ProxyTypes.http, "127.0.0.1", 1087);
}
