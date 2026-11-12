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

  ///mac设置代理地址
  @override
  Future<bool> _setSystemProxy(int port, bool sslSetting, String proxyPassDomains) async {
    _hardwarePort = _hardwarePort ?? await hardwarePort();
    if (_hardwarePort == null || _hardwarePort!.isEmpty) {
      logger.e('hardwarePort is empty, cannot set system proxy');
      return false;
    }

    final quotedName = _shellQuote(_hardwarePort!);
    var bypass = proxyPassDomains.replaceAll(";", " ");
    if (bypass.isEmpty) {
      bypass = '""';
    }

    List<String> commands = [
      'networksetup -setwebproxy $quotedName 127.0.0.1 $port',
      sslSetting == true ? 'networksetup -setsecurewebproxy $quotedName 127.0.0.1 $port' : '',
      'networksetup -setproxybypassdomains $quotedName $bypass',
      'networksetup -setsocksfirewallproxystate $quotedName off',
    ];
    print("Running commands:\n${commands.where((c) => c.isNotEmpty).join('\n')}");
    var results = await Process.run('bash', ['-c', _concatCommands(commands)]);
    logger.d('set proxyServer, name: $_hardwarePort, exitCode: ${results.exitCode}, stdout: ${results.stdout}');
    bool success = results.exitCode == 0;
    if (!success) {
      logger.e('setSystemProxy failed, stderr: ${results.stderr}');
      return setProxyWithAuth(commands);
    }
    return success;
  }

  ///设置Https代理
  @override
  Future<bool> _setSslProxyEnable(bool proxyEnable, port) async {
    var name = _hardwarePort ?? await hardwarePort();
    if (name.isEmpty) {
      logger.e('hardwarePort is empty, cannot set ssl proxy state');
      return false;
    }
    final quotedName = _shellQuote(name);

    List<String> commands = [
      proxyEnable
          ? 'networksetup -setsecurewebproxy $quotedName 127.0.0.1 $port'
          : 'networksetup -setsecurewebproxystate $quotedName off'
    ];

    var results = await Process.run('bash', ['-c', _concatCommands(commands)]);
    bool success = results.exitCode == 0;
    if (!success) {
      logger.e('setSystemProxy failed, stderr: ${results.stderr}');
      return setProxyWithAuth(commands);
    }
    return success;
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
    _hardwarePort ??= await hardwarePort();
    if (_hardwarePort == null || _hardwarePort!.isEmpty) {
      logger.e('hardwarePort is empty, cannot set proxy bypass domains');
      return;
    }
    final quotedName = _shellQuote(_hardwarePort!);
    var pass = proxyPassDomains.replaceAll(";", " ");
    if (pass.isEmpty) {
      pass = '""';
    }
    var results = await Process.run('bash', ['-c', 'networksetup -setproxybypassdomains $quotedName $pass']);
    logger.d('set proxyPassDomains, name: $_hardwarePort, exitCode: ${results.exitCode}, stdout: ${results.stdout}');
  }

  ///mac设置代理是否启用
  @override
  Future<void> _setProxyEnable(bool proxyEnable, bool sslSetting) async {
    var proxyMode = proxyEnable ? 'on' : 'off';
    _hardwarePort ??= await hardwarePort();
    if (_hardwarePort == null || _hardwarePort!.isEmpty) {
      logger.e('hardwarePort is empty, cannot set proxy enable state');
      return;
    }
    logger.d('set proxyEnable: $proxyEnable, name: $_hardwarePort');
    final quotedName = _shellQuote(_hardwarePort!);
    List<String> commands = [
      'networksetup -setwebproxystate $quotedName $proxyMode',
      sslSetting ? 'networksetup -setsecurewebproxystate $quotedName $proxyMode' : ''
    ];

    var results = await Process.run('bash', ['-c', _concatCommands(commands)]);

    if (results.exitCode != 0) {
      logger.e('setProxyEnable failed, stderr: ${results.stderr}');
      await setProxyWithAuth(commands);
    }
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
  static const String _schema = 'org.gnome.system.proxy';

  /// Plasma 6 只提供 kwriteconfig6（kwriteconfig5 已被移除），而 proxy_manager 0.0.3
  /// 在 XDG_CURRENT_DESKTOP=KDE 时写死调用 kwriteconfig5，会抛 ProcessException：
  /// 表现为「点停止后提示失败，但代理其实还在监听」，设置系统代理时也会异步抛错。
  /// 这里自己写 KIO 的配置并做版本兼容。
  static Future<void> _kdeConfig(String key, String value) async {
    final desktop = Platform.environment['XDG_CURRENT_DESKTOP'] ?? '';
    if (!desktop.toUpperCase().contains('KDE')) {
      return;
    }

    final home = Platform.environment['HOME'];
    for (final tool in const ['kwriteconfig6', 'kwriteconfig5']) {
      try {
        final result = await Process.run(tool, [
          '--file',
          '$home/.config/kioslaverc',
          '--group',
          'Proxy Settings',
          '--key',
          key,
          value,
        ]);
        if (result.exitCode == 0) {
          return;
        }
        logger.w('$tool $key=$value exits with ${result.exitCode}: ${result.stderr}');
      } on ProcessException {
        // 该版本不存在，试下一个
      }
    }
    logger.w('kwriteconfig6/5 not found, skip KDE proxy setting ($key)');
  }

  /// 删除某个 KIO 键（还原时清理我们自己写入、但用户原本没有的键）
  static Future<void> _kdeDelete(String key) async {
    final desktop = Platform.environment['XDG_CURRENT_DESKTOP'] ?? '';
    if (!desktop.toUpperCase().contains('KDE')) {
      return;
    }

    final home = Platform.environment['HOME'];
    for (final tool in const ['kwriteconfig6', 'kwriteconfig5']) {
      try {
        final result = await Process.run(tool, [
          '--file',
          '$home/.config/kioslaverc',
          '--group',
          'Proxy Settings',
          '--delete',
          '--key',
          key,
        ]);
        if (result.exitCode == 0) {
          return;
        }
      } on ProcessException {
        // 该版本不存在，试下一个
      }
    }
  }

  static Future<void> _gsettings(List<String> args) async {
    try {
      final result = await Process.run('gsettings', args);
      if (result.exitCode != 0) {
        logger.w('gsettings ${args.join(' ')} failed: ${result.stderr}');
      }
    } on ProcessException catch (e) {
      logger.w('gsettings not available: $e');
    }
  }

  static const List<String> _proxyTypes = ['http', 'https', 'socks'];

  /// 已知的 KIO 代理相关键，备份/还原时按这个列表处理
  static const List<String> _kdeKeys = ['ProxyType', 'httpProxy', 'httpsProxy', 'socksProxy', 'NoProxyFor'];

  /// 启动系统代理前把用户原有设置存一份，停止时还原。
  /// 否则（上游行为）停止会把模式直接设成 none，用户自己的 PAC/手动代理配置就丢了。
  static File? get _backupFile {
    final home = Platform.environment['HOME'];
    return home == null ? null : File('$home/.proxypin/system_proxy_backup.json');
  }

  static Future<String?> _gsettingsGet(String schema, String key) async {
    try {
      final result = await Process.run('gsettings', ['get', schema, key]);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } on ProcessException catch (e) {
      logger.w('gsettings get $schema $key failed: $e');
    }
    return null;
  }

  /// 读取 ~/.config/kioslaverc 的 [Proxy Settings] 段（只取代理相关键）
  static Map<String, String> _readKdeConfig() {
    final home = Platform.environment['HOME'];
    if (home == null) {
      return {};
    }
    final file = File('$home/.config/kioslaverc');
    if (!file.existsSync()) {
      return {};
    }

    final result = <String, String>{};
    var inSection = false;
    try {
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trim();
        if (trimmed.startsWith('[')) {
          inSection = trimmed == '[Proxy Settings]';
          continue;
        }
        if (!inSection || trimmed.isEmpty || trimmed.startsWith('#')) {
          continue;
        }
        final index = trimmed.indexOf('=');
        if (index <= 0) {
          continue;
        }
        final key = trimmed.substring(0, index).trim();
        if (_kdeKeys.contains(key)) {
          result[key] = trimmed.substring(index + 1).trim();
        }
      }
    } catch (e) {
      logger.w('read kioslaverc failed: $e');
    }
    return result;
  }

  static Future<void> _saveBackup() async {
    final file = _backupFile;
    if (file == null || file.existsSync()) {
      // 已有备份（含上次异常退出留下的）就不覆盖，避免把我们的设置当成用户设置
      return;
    }

    // gsettings 的代理项分属不同 schema：org.gnome.system.proxy 只有 mode /
    // autoconfig-url / ignore-hosts，各协议的 host/port/enabled 在 .http/.https/.socks 里。
    final settings = <String, String>{};
    Future<void> read(String schema, String key) async {
      final value = await _gsettingsGet(schema, key);
      if (value != null) {
        settings['$schema|$key'] = value;
      }
    }

    for (final key in const ['mode', 'autoconfig-url', 'ignore-hosts']) {
      await read(_schema, key);
    }
    for (final type in _proxyTypes) {
      await read('$_schema.$type', 'enabled');
      await read('$_schema.$type', 'host');
      await read('$_schema.$type', 'port');
    }

    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'gsettings': settings, 'kioslaverc': _readKdeConfig()}));
      logger.d('system proxy settings backed up');
    } catch (e) {
      logger.w('backup system proxy settings failed: $e');
    }
  }

  /// gsettings get 的结果带引号（字符串）或数组字面量，还原时按需去掉外层单引号
  static String _unwrap(String raw) {
    final value = raw.trim();
    if (value.length >= 2 && value.startsWith("'") && value.endsWith("'")) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  /// 还原备份；没有备份时返回 false，由调用方走默认逻辑
  static Future<bool> _restoreBackup() async {
    final file = _backupFile;
    if (file == null || !file.existsSync()) {
      return false;
    }

    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final settings = (data['gsettings'] as Map?)?.cast<String, dynamic>() ?? const {};
      final kde = (data['kioslaverc'] as Map?)?.cast<String, dynamic>() ?? const {};

      String? mode;
      // 先写具体项，最后切 mode，避免中途出现「manual 但地址还是 9099」的空窗
      for (final entry in settings.entries) {
        final sep = entry.key.indexOf('|');
        if (sep <= 0) {
          continue;
        }
        final schema = entry.key.substring(0, sep);
        final key = entry.key.substring(sep + 1);
        if (schema == _schema && key == 'mode') {
          mode = '${entry.value}';
          continue;
        }
        await _gsettings(['set', schema, key, _unwrap('${entry.value}')]);
      }
      if (mode != null) {
        await _gsettings(['set', _schema, 'mode', _unwrap(mode)]);
      }

      for (final key in _kdeKeys) {
        if (kde[key] != null) {
          await _kdeConfig(key, '${kde[key]}');
        } else {
          // 用户原本没有这个键：删掉我们写入的值，否则会留下指向 9099 的死配置
          await _kdeDelete(key);
        }
      }

      file.deleteSync();
      logger.i('system proxy settings restored');
      return true;
    } catch (e) {
      logger.w('restore system proxy settings failed: $e');
      return false;
    }
  }

  @override
  Future<void> _setSystemProxy(int port, bool sslSetting, String proxyPassDomains) async {
    await _saveBackup();
    await _gsettings(['set', _schema, 'mode', 'manual']);
    await _gsettings(['set', '$_schema.http', 'host', '127.0.0.1']);
    await _gsettings(['set', '$_schema.http', 'port', '$port']);
    await _gsettings(['set', '$_schema.http', 'enabled', 'true']);
    // 只代理 http/https：用户原来若开了 socks 代理，指向的是我们没监听的端口，先关掉（停止时还原）
    await _gsettings(['set', '$_schema.socks', 'enabled', 'false']);
    if (sslSetting) {
      await _gsettings(['set', '$_schema.https', 'host', '127.0.0.1']);
      await _gsettings(['set', '$_schema.https', 'port', '$port']);
      await _gsettings(['set', '$_schema.https', 'enabled', 'true']);
    }

    await _kdeConfig('ProxyType', '1');
    await _kdeConfig('httpProxy', 'http://127.0.0.1:$port');
    if (sslSetting) {
      await _kdeConfig('httpsProxy', 'http://127.0.0.1:$port');
    }

    SystemProxy.setProxyPassDomains(proxyPassDomains);
  }

  @override
  Future<void> _setProxyEnable(bool proxyEnable, bool sslSetting) async {
    if (await _restoreBackup()) {
      return;
    }

    // 没有备份（例如系统代理是别处开启的）时保持旧行为：关掉代理
    await _gsettings(['set', _schema, 'mode', 'none']);
    await _kdeConfig('ProxyType', '0');
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
