/*
 * Copyright 2026 Hongen Wang All rights reserved.
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
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/mcp/capture/curl_builder.dart';
import 'package:proxypin/mcp/mcp_names.dart';
import 'package:proxypin/mcp/mcp_service.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/util/file_read.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/mcp_docs.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/desktop/desktop.dart';

/// MCP 服务设置面板（桌面）。样式对齐 Proxyman 的 Settings → MCP：
/// MCP Server（启用开关 + 锁、描述、运行状态、MCP 配置、Claude Code/Codex/Manual
/// 分段、复制、命令框）→ Privacy 脱敏勾选 → 关于 MCP 集成（文档 / 技能目录）。
/// 传输统一走 stdio，端口自动分配，无需用户配置。
///
/// @author wanghongen
class McpServiceDialog extends StatefulWidget {
  final ProxyServer proxyServer;

  const McpServiceDialog({super.key, required this.proxyServer});

  static Future<void> show(BuildContext context, ProxyServer proxyServer) {
    return showDialog(
      context: context,
      builder: (_) => McpServiceDialog(proxyServer: proxyServer),
    );
  }

  @override
  State<StatefulWidget> createState() => _McpServiceDialogState();
}

class _SetupException implements Exception {
  final String message;
  _SetupException(this.message);
  @override
  String toString() => message;
}

typedef _Setup = Future<String> Function(String app, AppLocalizations l);

class _McpClient {
  const _McpClient(this.name, this.hint, this.build, this.setup, this.chat);

  final String name;

  /// Manual 模式下该接入方式的说明文字
  final String Function(AppLocalizations l) hint;

  /// 生成该客户端的接入命令（统一 stdio 传输）：[app] 可执行文件路径
  final String Function(String app) build;

  /// 一键配置：为空表示不支持自动配置（GUI 类客户端）
  final _Setup? setup;

  /// 打开交互式会话的命令（CLI 类客户端）；GUI/IDE 类客户端为空
  final String? chat;
}

const List<_McpClient> _clients = [
  _McpClient('Claude Code', _hintTerminal, _buildClaude, _setupClaude, 'claude'),
  _McpClient('Codex (OpenAI)', _hintTerminal, _buildCodex, _setupCodex, 'codex'),
  _McpClient('Cursor', _hintJson, _buildCursor, _setupCursor, null),
  _McpClient('GitHub Copilot', _hintCopilot, _buildCopilot, null, null),
  _McpClient('Gemini CLI', _hintJson, _buildGemini, _setupGemini, 'gemini'),
  _McpClient('Kimi (Moonshot)', _hintTerminal, _buildKimi, _setupKimi, 'kimi'),
  _McpClient('Doubao (MarsCode)', _hintDoubao, _buildLingma, null, null),
  _McpClient('Tongyi Lingma', _hintLingma, _buildLingma, null, null),
  _McpClient('Cherry Studio', _hintCherry, _buildCherry, null, null),
];

String _hintTerminal(AppLocalizations l) => l.mcpHintTerminal;
String _hintJson(AppLocalizations l) => l.mcpHintJson;
String _hintCopilot(AppLocalizations l) => l.mcpHintCopilot;
String _hintLingma(AppLocalizations l) => l.mcpHintLingma;
String _hintCherry(AppLocalizations l) => l.mcpHintCherry;
String _hintDoubao(AppLocalizations l) => l.mcpHintDoubao;

/// 桌面端注册名（手机端 LAN 配置使用 McpClientNames.mobile，两者并存互不覆盖）。
const String _serverName = McpClientNames.desktop;

String _mcpServersJson(String app) {
  return jsonEncode({
    'mcpServers': {
      _serverName: {'command': app, 'args': ['--mcp-stdio']}
    }
  });
}

String _buildClaude(String app) =>
    'claude mcp add $_serverName -s user --transport stdio -- "$app" --mcp-stdio';

String _buildCodex(String app) => 'codex mcp add $_serverName -- "$app" --mcp-stdio';

String _buildKimi(String app) => 'kimi mcp add --transport stdio $_serverName -- "$app" --mcp-stdio';

String _buildCursor(String app) => _mcpServersJson(app);
String _buildGemini(String app) => _mcpServersJson(app);
String _buildCherry(String app) => _mcpServersJson(app);

String _buildCopilot(String app) {
  return jsonEncode({
    'mcp': {
      'servers': {
        _serverName: {'command': app, 'args': ['--mcp-stdio']}
      }
    }
  });
}

String _buildLingma(String app) => '"$app" --mcp-stdio';

// ------------------------------------------------------------- 一键配置

/// CLI 是否在 PATH 中。
Future<bool> _cliExists(String cli) async {
  var which = Platform.isWindows ? 'where' : 'which';
  return (await Process.run(which, [cli])).exitCode == 0;
}

/// 运行 CLI 的 `mcp add` 命令。先探测 CLI 是否在 PATH 中。
/// "already exists"（已配置过）视为成功，避免幂等重跑被当作错误提示。
Future<String> _runCli(String cli, List<String> args, AppLocalizations l) async {
  if (!await _cliExists(cli)) {
    throw _SetupException(l.mcpCliMissing(cli));
  }
  var result = await Process.run(cli, args).timeout(const Duration(seconds: 30));
  if (result.exitCode == 0) return l.mcpSetupDone;
  var output = '${result.stderr}\n${result.stdout}';
  if (output.toLowerCase().contains('already exists')) return l.mcpSetupDone;
  throw _SetupException('${l.mcpSetupFail}${result.stderr}');
}

/// 一键配置统一走 stdio（HTTP 会触发 OAuth 交互，不适合无人值守）。
/// 添加前先清理旧版注册名与当前名的残留，保证重复执行幂等。
Future<String> _setupClaude(String app, AppLocalizations l) async {
  await _removeAll('claude', [
    ['mcp', 'remove', _serverName, '-s', 'user'],
    ['mcp', 'remove', McpClientNames.legacy, '-s', 'user'],
    ['mcp', 'remove', McpClientNames.legacy, '-s', 'local'],
  ]);
  return _runCli('claude',
      ['mcp', 'add', _serverName, '-s', 'user', '--transport', 'stdio', '--', app, '--mcp-stdio'], l);
}

Future<String> _setupCodex(String app, AppLocalizations l) async {
  await _removeAll('codex', [
    ['mcp', 'remove', _serverName],
    ['mcp', 'remove', McpClientNames.legacy],
  ]);
  return _runCli('codex', ['mcp', 'add', _serverName, '--', app, '--mcp-stdio'], l);
}

Future<String> _setupKimi(String app, AppLocalizations l) async {
  await _removeAll('kimi', [
    ['mcp', 'remove', _serverName],
    ['mcp', 'remove', McpClientNames.legacy],
  ]);
  return _runCli(
      'kimi', ['mcp', 'add', '--transport', 'stdio', _serverName, '--', app, '--mcp-stdio'], l);
}

/// 同一个 CLI 的多个删除命令：只探测一次 PATH，逐条执行（条目不存在不算错）。
Future<void> _removeAll(String cli, List<List<String>> removals) async {
  if (!await _cliExists(cli)) return;
  for (var args in removals) {
    try {
      await Process.run(cli, args).timeout(const Duration(seconds: 15));
    } catch (_) {}
  }
}

/// 写入配置文件（Cursor / Gemini），先备份再合并指定名称的条目；
/// 同时清理旧版注册名 proxypin，避免桌面端新旧两条 stdio 共存。
Future<String> _writeConfigFile(
    File file, String wrapperKey, String name, Map<String, dynamic> entry, AppLocalizations l) async {
  try {
    await file.parent.create(recursive: true);
    Map<String, dynamic> root = {};
    if (await file.exists()) {
      var content = await file.readAsString();
      if (content.trim().isNotEmpty) {
        root = jsonDecode(content) as Map<String, dynamic>;
      }
    }
    if (await file.exists()) {
      await file.copy('${file.path}.bak');
    }
    var section = (root[wrapperKey] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    section.remove(McpClientNames.legacy);
    section[name] = entry;
    root[wrapperKey] = section;
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(root));
    return l.mcpSetupDone;
  } on _SetupException {
    rethrow;
  } catch (e) {
    throw _SetupException('${l.mcpSetupFail}$e');
  }
}

Future<String> _setupCursor(String app, AppLocalizations l) {
  var home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  return _writeConfigFile(
    File('$home${Platform.pathSeparator}.cursor${Platform.pathSeparator}mcp.json'),
    'mcpServers',
    _serverName,
    {
      'command': app,
      'args': ['--mcp-stdio']
    },
    l,
  );
}

Future<String> _setupGemini(String app, AppLocalizations l) {
  var home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  return _writeConfigFile(
    File('$home${Platform.pathSeparator}.gemini${Platform.pathSeparator}settings.json'),
    'mcpServers',
    _serverName,
    {
      'command': app,
      'args': ['--mcp-stdio']
    },
    l,
  );
}

class _McpServiceDialogState extends State<McpServiceDialog> {
  final AppConfiguration cfg = AppConfiguration.current!;

  String? _error;
  bool _busy = false;

  /// 对话框内悬浮提示（复制/配置成功等轻反馈）
  String? _toastMessage;
  Timer? _toastTimer;

  /// 顶部三段选择：claude / codex / manual
  String _mode = 'claude';

  /// Manual 模式下选中的客户端（默认 Cursor，其配置为 mcpServers JSON）
  String _manualKey = 'Cursor';

  AppLocalizations get l => AppLocalizations.of(context)!;

  bool get _running => McpService.instance.isRunning;

  _McpClient _byName(String name) => _clients.firstWhere((c) => c.name == name, orElse: () => _clients.first);

  /// 当前生效的客户端：claude/codex 直连对应 CLI，manual 由下拉决定
  _McpClient get _client => switch (_mode) {
        'codex' => _byName('Codex (OpenAI)'),
        'manual' => _byName(_manualKey),
        _ => _byName('Claude Code'),
      };

  Future<void> _toggle(bool enabled) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    cfg.mcpEnabled = enabled;
    if (enabled) {
      McpService.instance.attach(widget.proxyServer, existing: desktopCaptureContainer);
    }
    try {
      if (enabled) {
        await McpService.instance.start(cfg);
      } else {
        await McpService.instance.stop();
      }
    } catch (e) {
      cfg.mcpEnabled = false;
      _error = '${l.mcpStartFailed}: $e';
    }
    cfg.flushConfig();
    if (mounted) setState(() => _busy = false);
  }

  String get _currentCommand => _client.build(CurlBuilder.executable);

  Future<void> _oneClickSetup() async {
    var setup = _client.setup;
    if (setup == null) {
      _toast(l.mcpUnsupported);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await setup(CurlBuilder.executable, l);
      if (mounted) _toast(l.mcpSetupDone);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    _toastTimer?.cancel();
    setState(() => _toastMessage = message);
    _toastTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  Future<void> _startChat() async {
    var chat = _client.chat;
    if (chat == null) {
      _toast(l.mcpUnsupported);
      return;
    }
    await _openTerminalWith(chat);
  }

  /// 打开终端运行交互式会话；工作目录固定为 proxypin 数据保存目录，便于会话文件落盘在数据目录。
  Future<void> _openTerminalWith(String command) async {
    try {
      var home = await FileRead.homeDir();
      var cwd = home.path;
      await Directory(cwd).create(recursive: true);

      if (Platform.isMacOS) {
        var file = File(
            '${Directory.systemTemp.path}${Platform.pathSeparator}proxypin_mcp_${DateTime.now().millisecondsSinceEpoch}.command');
        await file.writeAsString('#!/bin/bash\ncd "$cwd" || exit 1\n$command\n');
        await Process.run('chmod', ['+x', file.path]);
        await Process.start('open', ['-a', 'Terminal', file.path]);
      } else if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', 'cmd', '/k', 'cd /d "$cwd" && $command']);
      } else {
        for (var t in [
          ['gnome-terminal', '--', 'bash', '-c', 'cd "$cwd"; $command; exec bash'],
          ['x-terminal-emulator', '-e', 'bash', '-c', 'cd "$cwd"; $command; exec bash'],
          ['xterm', '-e', 'bash', '-c', 'cd "$cwd"; $command; exec bash'],
        ]) {
          try {
            await Process.start(t.first, t.sublist(1));
            return;
          } catch (_) {}
        }
        if (mounted) _toast(l.mcpSetupFail);
      }
    } catch (e) {
      logger.e('start chat failed', error: e);
      if (mounted) _toast('${l.mcpSetupFail}$e');
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _toast(l.mcpCopied);
  }

  // ====================================================================== UI

  static const Color _greenLight = Color(0xFF34C759);
  static const Color _greenDark = Color(0xFF30D158);

  /// 主题适配的"运行/成功"强调色
  Color _okColor(ColorScheme cs) => cs.brightness == Brightness.dark ? _greenDark : _greenLight;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var cs = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: cs.surface,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: math.min(580.0, math.max(320.0, MediaQuery.sizeOf(context).width - 48)),
        child: Stack(children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height - 96),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ===== MCP Server =====
              Row(children: [
                Expanded(
                  child: Text(l.mcpService, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: l.close,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, size: 18, color: cs.onSurfaceVariant),
                ),
              ]),
              const SizedBox(height: 12),
              _enableRow(cs),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 38),
                child: Text(l.mcpServiceDescribe,
                    style: TextStyle(fontSize: 11.5, height: 1.45, color: cs.onSurfaceVariant)),
              ),
              const SizedBox(height: 9),
              Padding(
                padding: const EdgeInsets.only(left: 38),
                child: _statusBadge(cs),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                _errorBanner(cs, _error!),
              ],
              const SizedBox(height: 14),
              _configBlock(cs),
              const SizedBox(height: 18),
              _divider(cs),
              const SizedBox(height: 16),

              // ===== Privacy =====
              Text('Privacy', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _checkRow(
                cs,
                value: cfg.mcpRedactEnabled,
                title: l.mcpRedact,
                subtitle: l.mcpRedactDescribe,
                onChanged: (v) {
                  setState(() => cfg.mcpRedactEnabled = v);
                  cfg.flushConfig();
                },
              ),
              const SizedBox(height: 16),
              _divider(cs),
              const SizedBox(height: 16),

              // ===== 关于 MCP 集成 =====
              Text(l.mcpAboutTitle,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              Text(l.mcpAboutText,
                  style: TextStyle(fontSize: 12, height: 1.5, color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              _linkAction(Icons.open_in_new_rounded, l.mcpLearnMore, () => openMcpDoc(context), cs),
            ]),
          ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 14,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _toastMessage == null ? 0 : 1,
                duration: const Duration(milliseconds: 150),
                child: _toastPill(cs),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _toastPill(ColorScheme cs) {
    var message = _toastMessage;
    if (message == null) return const SizedBox.shrink();
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: cs.inverseSurface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Text(message, style: TextStyle(fontSize: 12.5, color: cs.onInverseSurface)),
      ),
    );
  }

  Widget _divider(ColorScheme cs) =>
      Divider(height: 1, thickness: 1, color: cs.outlineVariant.withValues(alpha: 0.5));

  // ------------------------------------------------------------- enable / status
  Widget _enableRow(ColorScheme cs) {
    var on = _running;
    return Row(children: [
      SwitchWidget(value: _running || (cfg.mcpEnabled && _busy), scale: 0.7, onChanged: _busy ? (_) {} : _toggle),
      const SizedBox(width: 6),
      Text(l.mcpEnable,
          style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: on ? cs.onSurface : cs.onSurfaceVariant)),
      const Spacer(),
      // 未启用时显示挂锁，与 Proxyman 一致
      if (!on) Icon(Icons.lock_rounded, size: 15, color: Colors.orange.shade400),
    ]);
  }

  Widget _statusBadge(ColorScheme cs) {
    var on = _running;
    if (on) {
      var color = _okColor(cs);
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_rounded, size: 15, color: color),
        const SizedBox(width: 6),
        Text(l.mcpStatusRunning, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 15,
        height: 15,
        decoration: BoxDecoration(color: cs.onSurfaceVariant.withValues(alpha: 0.55), shape: BoxShape.circle),
        child: Icon(Icons.close_rounded, size: 10, color: cs.surface),
      ),
      const SizedBox(width: 6),
      Text(l.mcpStatusStopped,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant)),
    ]);
  }

  // ------------------------------------------------------------- config block
  Widget _configBlock(ColorScheme cs) {
    var mono = const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4);
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.mcpConfig,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        _modeSegmented(cs),
        if (_mode == 'manual') ...[
          const SizedBox(height: 10),
          _manualSelector(cs),
        ],
        const SizedBox(height: 12),
        _commandField(cs, mono),
        const SizedBox(height: 6),
        // 固定两行高度，避免切换客户端时弹框高度跳动
        SizedBox(
          height: 34,
          child: Text(_hintText(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, height: 1.4, color: cs.onSurfaceVariant)),
        ),
        if (_client.setup != null || _client.chat != null) ...[
          const SizedBox(height: 4),
          _extraActions(cs),
        ],
      ]),
    );
  }

  /// 命令框下方的提示：Claude/Codex 模式按 Proxyman 的“在终端运行此命令…”句式
  String _hintText() {
    if (_mode == 'manual') return _client.hint(l);
    return l.mcpHintRun(_mode == 'codex' ? 'Codex' : 'Claude Code');
  }

  /// 分段控件：Claude Code / Codex / Manual，选中段为主题色填充（对齐 Proxyman）
  Widget _modeSegmented(ColorScheme cs) {
    final tabs = const [('claude', 'Claude Code'), ('codex', 'Codex'), ('manual', 'Manual')];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(children: [
          for (var tab in tabs) Expanded(child: _modeTab(cs, tab.$1, tab.$2)),
        ]),
      ),
    );
  }

  Widget _modeTab(ColorScheme cs, String value, String label) {
    var selected = _mode == value;
    return GestureDetector(
      onTap: () => setState(() => _mode = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
            )),
      ),
    );
  }

  Widget _manualSelector(ColorScheme cs) {
    return PopupMenuButton<String>(
      color: cs.surfaceContainerHigh,
      position: PopupMenuPosition.under,
      tooltip: '',
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 340),
      onSelected: (v) => setState(() => _manualKey = v),
      itemBuilder: (_) => [for (var c in _clients) _menuClient(c, cs)],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(_manualKey, style: TextStyle(fontSize: 12, color: cs.onSurface)),
          const SizedBox(width: 6),
          Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: cs.onSurfaceVariant),
        ]),
      ),
    );
  }

  PopupMenuItem<String> _menuClient(_McpClient c, ColorScheme cs) {
    var selected = c.name == _manualKey;
    return PopupMenuItem<String>(
      value: c.name,
      height: 34,
      child: Row(children: [
        Icon(selected ? Icons.check_rounded : Icons.remove,
            size: 15, color: selected ? cs.primary : Colors.transparent),
        const SizedBox(width: 8),
        Text(c.name, style: const TextStyle(fontSize: 13)),
      ]),
    );
  }

  Widget _commandField(ColorScheme cs, TextStyle mono) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(11, 8, 8, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: Stack(children: [
        Padding(
          padding: const EdgeInsets.only(right: 34),
          child: SelectableText(_currentCommand,
              style: mono.copyWith(color: cs.onSurface.withValues(alpha: 0.9))),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: _copyButton(cs),
        ),
      ]),
    );
  }

  Widget _copyButton(ColorScheme cs) {
    return IconButton(
      tooltip: l.mcpCopy,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      onPressed: () => _copy(_currentCommand),
      icon: Icon(Icons.copy_all_rounded, size: 14.5, color: cs.onSurfaceVariant),
      style: IconButton.styleFrom(backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.6)),
    );
  }

  /// 一键配置 / 开始对话（弱化的链接式辅助操作）
  Widget _extraActions(ColorScheme cs) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (_busy) ...[
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.8, color: cs.primary),
        ),
        const SizedBox(width: 10),
      ],
      if (_client.setup != null)
        _linkAction(Icons.auto_fix_high_rounded, l.mcpSetup, _busy ? null : _oneClickSetup, cs),
      if (_client.chat != null) ...[
        const SizedBox(width: 20),
        _linkAction(Icons.forum_outlined, l.mcpStartChat, _busy ? null : _startChat, cs),
      ],
    ]);
  }

  Widget _linkAction(IconData icon, String label, VoidCallback? onTap, ColorScheme cs) {
    var enabled = onTap != null;
    var color = enabled ? cs.primary : cs.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- privacy
  Widget _checkRow(ColorScheme cs,
      {required bool value,
      required String title,
      required String subtitle,
      required ValueChanged<bool> onChanged}) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 19,
          height: 19,
          child: Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            fillColor: WidgetStatePropertyAll(value ? cs.primary : cs.surface),
            checkColor: cs.onPrimary,
            side: BorderSide(color: cs.onSurfaceVariant.withValues(alpha: 0.5), width: 1.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(title,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface))),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 11.5, height: 1.4, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ]),
    );
  }


  // ------------------------------------------------------------- banners
  Widget _errorBanner(ColorScheme cs, String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline_rounded, size: 15, color: cs.error),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: TextStyle(fontSize: 11.5, color: cs.onErrorContainer, height: 1.35))),
      ]),
    );
  }
}
