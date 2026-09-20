import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/mcp/transport/setup_script.dart';

void main() {
  test('shell script configures mobile entry without touching desktop proxypin', () async {
    var tmp = await Directory.systemTemp.createTemp('proxypin_setup');
    try {
      var home = '${tmp.path}${Platform.pathSeparator}home';
      var bin = '${tmp.path}${Platform.pathSeparator}bin';
      await Directory(home).create(recursive: true);
      await Directory(bin).create(recursive: true);

      var cliLog = '${tmp.path}${Platform.pathSeparator}cli.log';

      // 假 claude：记录参数并成功退出
      await _writeExec('$bin/claude', '''
#!/bin/sh
printf '%s\\n' "\$*" >> "$cliLog"
exit 0
''');
      // 假 codex：存在即触发 config.toml 写入
      await _writeExec('$bin/codex', '#!/bin/sh\nexit 0\n');

      // 预置 Codex 桌面端 stdio 条目（旧名 proxypin），手机脚本不得改动
      var codexDir = '$home${Platform.pathSeparator}.codex';
      await Directory(codexDir).create();
      var codexToml = File('$codexDir${Platform.pathSeparator}config.toml');
      await codexToml.writeAsString('''
[mcp_servers.proxypin]
command = "/Applications/ProxyPin.app"
args = ["--mcp-stdio"]

[mcp_servers.other]
command = "xxx"
''');

      // 预置 Cursor 配置：桌面 proxypin 条目 + 一个无关 server
      var cursorDir = '$home${Platform.pathSeparator}.cursor';
      await Directory(cursorDir).create();
      var cursorJson = File('$cursorDir${Platform.pathSeparator}mcp.json');
      await cursorJson.writeAsString(jsonEncode({
        'mcpServers': {
          'proxypin': {
            'type': 'stdio',
            'command': '/Applications/ProxyPin.app',
            'args': ['--mcp-stdio']
          },
          'other': {'type': 'stdio', 'command': 'xxx'}
        }
      }));
      await Directory('$home${Platform.pathSeparator}.gemini').create();

      const endpoint = 'http://192.168.1.23:9127/mcp';
      const token = 'abcdef0123456789';
      var script = McpSetupScript.shell(endpoint: endpoint, token: token);
      expect(script.contains('__PROXYPIN'), isFalse, reason: 'placeholders must be replaced');

      var scriptFile = File('${tmp.path}${Platform.pathSeparator}setup.sh');
      await scriptFile.writeAsString(script);

      var env = <String, String>{
        'HOME': home,
        'PATH': '$bin:${Platform.environment['PATH']}',
      };

      // 执行两次，验证幂等
      for (var i = 0; i < 2; i++) {
        var result = await Process.run('sh', [scriptFile.path], environment: env);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        if (i == 0) expect(result.stdout, contains('[OK] Claude Code'));
      }

      // ---- Claude CLI：注册 proxypin_mobile（user scope）----
      var log = await File(cliLog).readAsString();
      expect(log, contains('mcp add proxypin_mobile -s user'));
      expect(log, contains('--transport http'));
      expect(log, contains(endpoint));
      expect(log, contains('Authorization: Bearer $token'));
      // 只清理 user scope 的历史遗留 proxypin，绝不动 local（桌面端条目在 local）
      expect(log, contains('mcp remove proxypin -s user'));
      expect(log, isNot(contains('mcp remove proxypin -s local')));
      expect(log, isNot(contains('mcp add proxypin ')));
      // 两次执行：add/remove 各两次
      expect('mcp add proxypin_mobile'.allMatches(log).length, 2);

      // ---- Codex TOML：桌面 proxypin 段保留，新增 mobile 段且唯一 ----
      var toml = await codexToml.readAsString();
      expect(toml, contains('[mcp_servers.proxypin]'), reason: 'desktop section preserved');
      expect(toml, contains('/Applications/ProxyPin.app'), reason: 'desktop command preserved');
      expect(toml, contains('[mcp_servers.other]'), reason: 'unrelated section preserved');
      expect('[mcp_servers.proxypin_mobile]'.allMatches(toml).length, 1,
          reason: 'mobile section unique across reruns');
      expect(toml, contains('url = "$endpoint"'));
      expect(toml, contains('Authorization = "Bearer $token"'));

      // ---- Cursor / Gemini JSON（依赖 python3）----
      if (await _hasCommand('python3')) {
        var cursor = jsonDecode(await cursorJson.readAsString()) as Map<String, dynamic>;
        var servers = cursor['mcpServers'] as Map<String, dynamic>;
        expect(servers.containsKey('other'), isTrue);
        // 桌面 proxypin（stdio）原样保留
        var desktop = servers['proxypin'] as Map<String, dynamic>;
        expect(desktop['type'], 'stdio');
        // 新增 mobile（http）
        var mobile = servers['proxypin_mobile'] as Map<String, dynamic>;
        expect(mobile['type'], 'http');
        expect(mobile['url'], endpoint);
        expect((mobile['headers'] as Map)['Authorization'], 'Bearer $token');

        var gemini = jsonDecode(await File(
                '$home${Platform.pathSeparator}.gemini${Platform.pathSeparator}settings.json')
            .readAsString()) as Map<String, dynamic>;
        expect((gemini['mcpServers'] as Map).containsKey('proxypin_mobile'), isTrue);
      }
    } finally {
      await tmp.delete(recursive: true);
    }
  });

  test('powershell template uses mobile name and replaces placeholders', () {
    var ps = McpSetupScript.powershell(endpoint: 'http://1.2.3.4:9/mcp', token: 't0ken');
    expect(ps.contains('__PROXYPIN'), isFalse);
    expect(ps, contains("'proxypin_mobile'"));
    expect(ps, contains('http://1.2.3.4:9/mcp'));
    expect(ps, contains('t0ken'));
  });
}

Future<void> _writeExec(String path, String content) async {
  var f = File(path);
  await f.writeAsString(content);
  await Process.run('chmod', ['+x', path]);
}

Future<bool> _hasCommand(String name) async {
  var r = await Process.run(Platform.isWindows ? 'where' : 'which', [name]);
  return r.exitCode == 0;
}
