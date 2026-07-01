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

import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/util/logger.dart';
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
      return '';
    }
    if (Platform.isWindows) {
      return '';
    }

    if (Platform.isAndroid) {
      return '';
    }
    if (Platform.isIOS) {
      return '';
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

    await instance._setProxyEnable(enable, sslSetting);
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

  /// 缓存的活跃网络服务名列表。
  /// 仅在启用代理（[_setSystemProxy]）和禁用代理（[_setProxyEnable]）时刷新，
  /// 因为这两次调用之间用户可能连接/断开了 VPN 或虚拟网卡；其余方法直接复用缓存。
  List<String>? _cachedServices;

  // Helper to safely quote a string for sh (single-quote and escape any internal single quotes)
  static String _shellQuote(String s) {
    // Replace ' with '\'' which is the safe way to include single quotes inside single-quoted strings in shell
    return "'${s.replaceAll("'", "'\\''")}'";
  }

  ///获取系统代理
  @override
  Future<ProxyInfo?> _getSystemProxy(ProxyTypes proxyTypes) async {
    _hardwarePort = _hardwarePort ?? await hardwarePort();

    // ensure we have a name
    if (_hardwarePort == null || _hardwarePort!.isEmpty) {
      logger.e('hardwarePort is empty, cannot get system proxy');
      return null;
    }

    final quotedName = _shellQuote(_hardwarePort!);

    var result = await Process.run('bash', [
      '-c',
      'networksetup ${proxyTypes == ProxyTypes.http ? '-getwebproxy' : '-getsecurewebproxy'} $quotedName'
    ]).then((results) => results.stdout.toString().split('\n'));

    // defensive parsing: find lines safely
    String enabledLine = result.firstWhere((item) => item.contains('Enabled'), orElse: () => '');
    if (enabledLine.isEmpty) {
      logger.e('Failed to parse Enabled line from networksetup output: ${result.join('\n')}');
      return null;
    }

    var proxyEnableParts = enabledLine.trim().split(RegExp(r":\s*"));
    var proxyEnable = proxyEnableParts.length > 1 ? proxyEnableParts[1] : 'No';
    if (proxyEnable == 'No') {
      return null;
    }

    String serverLine = result.firstWhere((item) => item.contains('Server'), orElse: () => '');
    String portLine = result.firstWhere((item) => item.contains('Port'), orElse: () => '');
    if (serverLine.isEmpty || portLine.isEmpty) {
      logger.e('Failed to parse Server/Port from networksetup output: ${result.join('\n')}');
      return null;
    }

    var proxyServer = serverLine.trim().split(RegExp(r":\s*"))[1];
    var proxyPort = portLine.trim().split(RegExp(r":\s*"))[1];
    if (proxyEnable == 'Yes' && proxyServer.isNotEmpty) {
      return ProxyInfo.of(proxyServer, int.parse(proxyPort));
    }
    return null;
  }

  /// 通过 `networksetup -listallnetworkservices` 获取所有活跃网络服务名。
  /// 输出首行为标题，需跳过；以 `*` 开头的服务被禁用，需排除。
  /// 命令失败或无活跃服务时，依次回退到 [hardwarePort]（动态探测的主服务）
  /// 和硬编码的 `['Wi-Fi']`（避免遗漏如 Mac mini 这类仅有有线网卡的设备）。
  static Future<List<String>> _listNetworkServices() async {
    try {
      var result = await Process.run('networksetup', ['-listallnetworkservices']);
      if (result.exitCode == 0) {
        var services = result.stdout
            .toString()
            .split(RegExp(r'\r?\n'))
            // 跳过首行（标题行）
            .skip(1)
            .map((s) => s.trim())
            // 排除被禁用的服务（以 '*' 开头）和空行
            .where((s) => s.isNotEmpty && !s.startsWith('*'))
            .toList();
        if (services.isNotEmpty) return services;
        logger.w('listallnetworkservices returned no active services, using fallback');
      } else {
        logger.w('listallnetworkservices failed, stderr: ${result.stderr}, using fallback');
      }
    } catch (e) {
      logger.w('listallnetworkservices error: $e, using fallback');
    }
    // 动态回退：基于默认路由的硬件端口探测主服务。
    // 对于没有 Wi-Fi 接口的设备，优于硬编码的 'Wi-Fi'。
    var primary = await hardwarePort();
    if (primary.isNotEmpty) return [primary];
    return ['Wi-Fi'];
  }

  /// 对忽略代理的域名列表进行安全转义，便于拼接到 shell 命令中。
  /// 输入以 `;` 或空白符分隔（ProxyPin 用 `;` 作为分隔符）；
  /// 每个 token 都用 [_shellQuote] 包裹，避免用户输入的特殊字符
  /// （`;`、`` ` ``、`$()`、`|`、`&` 等）破坏 networksetup 参数。
  /// 列表为空时返回单个空引号参数，以清空忽略列表，与原 `""` 行为一致。
  static String _quoteBypassDomains(String raw) {
    var tokens = raw.split(RegExp(r'[;\s]+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return "''";
    return tokens.map(_shellQuote).join(' ');
  }

  /// 获取已缓存的服务列表，[refresh] 为 true 时重新探测。
  Future<List<String>> _services({bool refresh = false}) async {
    if (refresh || _cachedServices == null) {
      _cachedServices = await _listNetworkServices();
    }
    return _cachedServices!;
  }

  /// 对每个网络服务分别执行一次 [commandBuilder] 生成的命令。
  /// 每个服务单独起一个 `bash -c`（内部命令用 `&&` 连接），
  /// 因此某个服务失败不会跳过其他服务的命令。
  /// 只要任一服务成功即视为整体成功（单个不活跃/虚拟网卡不应中断整个操作）；
  /// 单个服务失败仅记为 warning。仅当所有服务都失败时，才回退到 [setProxyWithAuth]（弹 sudo）。
  /// [refresh] 为 true 时先重建缓存的服务列表（用户可能在上次调用后连接/断开了 VPN）。
  Future<bool> _runForAllServices(
    Iterable<String> Function(String service) commandBuilder, {
    String? logLabel,
    bool refresh = false,
  }) async {
    var services = await _services(refresh: refresh);
    Map<String, List<String>> byService = {};
    for (var service in services) {
      var cmds = commandBuilder(service).where((c) => c.isNotEmpty).toList();
      if (cmds.isNotEmpty) byService[service] = cmds;
    }

    if (byService.isEmpty) {
      logger.w('${logLabel ?? 'runForAllServices'}: no commands generated for services $services');
      return false;
    }

    logger.d('${logLabel ?? 'runForAllServices'} running for services: $byService');
    int failed = 0;
    String? lastErr;
    for (var entry in byService.entries) {
      var perService = await Process.run('bash', ['-c', _concatCommands(entry.value)]);
      if (perService.exitCode != 0) {
        failed++;
        lastErr = perService.stderr.toString();
        logger.w('$logLabel failed for service "${entry.key}", stderr: ${perService.stderr}');
      }
    }
    // 任一服务成功即可；仅当全部失败时才升级处理。
    bool overallSuccess = failed < byService.length;
    if (!overallSuccess) {
      logger.e('$logLabel failed for all services, last stderr: $lastErr');
      return setProxyWithAuth(byService.values.expand((c) => c).toList());
    }
    return true;
  }

  ///mac设置代理地址
  @override
  Future<bool> _setSystemProxy(int port, bool sslSetting, String proxyPassDomains) async {
    final quotedBypass = _quoteBypassDomains(proxyPassDomains);

    return _runForAllServices(
      (service) {
        final quotedName = _shellQuote(service);
        return [
          'networksetup -setwebproxy $quotedName 127.0.0.1 $port',
          if (sslSetting == true) 'networksetup -setsecurewebproxy $quotedName 127.0.0.1 $port',
          'networksetup -setproxybypassdomains $quotedName $quotedBypass',
          'networksetup -setsocksfirewallproxystate $quotedName off',
        ];
      },
      logLabel: 'setSystemProxy',
      refresh: true,
    );
  }

  ///设置Https代理
  @override
  Future<bool> _setSslProxyEnable(bool proxyEnable, int port) async {
    return _runForAllServices(
      (service) {
        final quotedName = _shellQuote(service);
        return [
          proxyEnable
              ? 'networksetup -setsecurewebproxy $quotedName 127.0.0.1 $port'
              : 'networksetup -setsecurewebproxystate $quotedName off'
        ];
      },
      logLabel: 'setSslProxyEnable',
    );
  }

  ///mac获取当前网络名称
  static Future<String> hardwarePort() async {
    var name = await networkName();
    // Use a safer pipeline that avoids embedding awk's $2 (which complicates Dart string quoting).
    // This command finds the Device line, takes the following Hardware Port line, and extracts the part after ':'
    var cmd =
        'networksetup -listnetworkserviceorder | grep "Device: ${name}" -A 1 | grep "Hardware Port" | cut -d: -f2 | sed -n \'1p\'';
    var results = await Process.run('bash', ['-c', cmd]);
    var out = results.stdout.toString().trim();
    if (out.isEmpty) return '';
    // split on newlines or commas and take the first non-empty token
    var parts = out.split(RegExp(r"[\r\n,]+"));
    return parts.first.trim();
  }

  ///设置代理忽略地址
  @override
  Future<void> _setProxyPassDomains(String proxyPassDomains) async {
    final quotedBypass = _quoteBypassDomains(proxyPassDomains);

    await _runForAllServices(
      (service) {
        final quotedName = _shellQuote(service);
        return ['networksetup -setproxybypassdomains $quotedName $quotedBypass'];
      },
      logLabel: 'setProxyPassDomains',
    );
  }

  ///mac设置代理是否启用
  @override
  Future<void> _setProxyEnable(bool proxyEnable, bool sslSetting) async {
    var proxyMode = proxyEnable ? 'on' : 'off';
    await _runForAllServices(
      (service) {
        final quotedName = _shellQuote(service);
        return [
          'networksetup -setwebproxystate $quotedName $proxyMode',
          if (sslSetting) 'networksetup -setsecurewebproxystate $quotedName $proxyMode',
        ];
      },
      logLabel: 'setProxyEnable',
      // 关闭代理时也要刷新：若用户在启用代理后又连接了 VPN/TUN，
      // 该新接口不在缓存列表中，会导致其代理状态未被清理。
      // 清理时漏掉新接口的后果比启用时更严重，故仅在关闭时刷新。
      refresh: !proxyEnable,
    );
  }

  Future<bool> setProxyWithAuth(List<String> commands) async {
    // 使用 quoted form of 确保 shell 指令被 AppleScript 正确转义
    String script = 'do shell script "${commands.join('; ')}" with administrator privileges';
    try {
      final result = await Process.run('osascript', ['-e', script]);
      bool success = result.exitCode == 0;
      if (!success) {
        logger.e("操作失败或用户取消: ${result.stderr}");
      }
      return success;
    } catch (e) {
      logger.e("执行 AppleScript 出错: $e");
      return false;
    }
  }

  static String _concatCommands(List<String> commands) {
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
      logger.d("$proxyServer:$proxyPort");
      return ProxyInfo.of(proxyServer, int.parse(proxyPort));
    }).catchError((e) {
      logger.e('getSystemProxy error', error: e, stackTrace: StackTrace.current);
      return null;
    });
  }

  ///设置代理忽略地址
  @override
  Future<void> _setProxyPassDomains(String proxyPassDomains) async {
    var results = await _internetSettings('add', ['ProxyOverride', '/t', 'REG_SZ', '/d', proxyPassDomains, '/f']);
    logger.i('set proxyPassDomains, stdout: $results');
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
