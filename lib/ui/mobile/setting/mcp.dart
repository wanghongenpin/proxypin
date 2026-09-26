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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/mcp/mcp_names.dart';
import 'package:proxypin/mcp/mcp_service.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/component/mcp_docs.dart';
import 'package:proxypin/ui/component/port_edit_dialog.dart';
import 'package:proxypin/ui/mobile/mobile.dart';
import 'package:proxypin/utils/flutter_compat.dart';
import 'package:proxypin/utils/ip.dart';

/// 移动端 MCP 设置：在局域网内暴露 MCP HTTP 服务，电脑上的 AI 客户端
/// （Claude Code / Codex 等）通过 Bearer token 远程连接。
///
/// @author wanghongen
class MobileMcpSetting extends StatefulWidget {
  final ProxyServer proxyServer;

  const MobileMcpSetting({super.key, required this.proxyServer});

  @override
  State<MobileMcpSetting> createState() => _MobileMcpSettingState();
}

class _MobileMcpSettingState extends State<MobileMcpSetting> {
  final AppConfiguration cfg = AppConfiguration.current!;

  bool _busy = false;
  String? _error;

  /// 本机 LAN IP，进入页面时异步获取
  String? _lanIp;

  AppLocalizations get l => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _refreshIp();
  }

  Future<void> _refreshIp() async {
    var ip = await localIp(readCache: false);
    if (mounted) setState(() => _lanIp = ip);
  }

  bool get _running => McpService.instance.isRunning;

  String? get _endpoint {
    var ip = _lanIp;
    var port = McpService.instance.port;
    if (ip == null || port == null) return null;
    return 'http://$ip:$port/mcp';
  }

  Future<void> _toggle(bool enabled) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    cfg.mcpEnabled = enabled;
    if (enabled) {
      McpService.instance.attach(widget.proxyServer, existing: MobileApp.container.source);
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
    if (mounted) {
      setState(() => _busy = false);
      // 启动后实际端口才可用，刷新一次 IP 展示
      _refreshIp();
    }
  }

  /// 重置 token：重新生成并在运行中重启 HTTP 服务，旧令牌立即失效
  Future<void> _regenerateToken() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    cfg.mcpToken = McpService.generateToken();
    cfg.flushConfig();
    try {
      if (_running) {
        await McpService.instance.stop();
        // 同 _editPort：stop() 已清空索引，重启前回填，避免重置令牌后历史请求对 AI 不可见
        McpService.instance.attach(widget.proxyServer, existing: MobileApp.container.source);
        await McpService.instance.start(cfg);
      }
    } catch (e) {
      _error = '${l.mcpStartFailed}: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  /// 修改固定监听端口：校验通过后写入配置，运行中则重启服务使新端口生效
  Future<void> _editPort() async {
    var newPort = await PortEditDialog.show(
      context,
      initialPort: cfg.mcpPort ?? McpService.defaultPort,
      defaultPort: McpService.defaultPort,
    );
    if (newPort == null || newPort == (cfg.mcpPort ?? McpService.defaultPort)) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    cfg.mcpPort = newPort;
    cfg.flushConfig();
    try {
      if (_running) {
        await McpService.instance.stop();
        // stop() 会清空抓包索引，重启前回填当前列表，否则改端口后历史请求对 AI 不可见
        McpService.instance.attach(widget.proxyServer, existing: MobileApp.container.source);
        await McpService.instance.start(cfg);
      }
    } catch (e) {
      _error = '${l.mcpStartFailed}: $e';
    }
    if (mounted) {
      setState(() => _busy = false);
      _refreshIp();
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.mcpCopied), duration: const Duration(seconds: 2)));
  }


  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var cs = theme.colorScheme;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(42),
        child: AppBar(
          title: Text(l.mcpService, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
          centerTitle: true,
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        _card([
          SwitchListTile(
            value: _running,
            onChanged: _busy ? null : _toggle,
            activeColor: cs.primary,
            title: Text(l.mcpEnable),
            subtitle: Text(l.mcpServiceDescribe,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.4)),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _statusRow(cs),
          ),
        ]),
        const SizedBox(height: 12),
        if (_running) ...[
          _card([
            ListTile(
              dense: true,
              leading: Icon(Icons.lan_outlined, color: cs.primary),
              title: Text(l.mcpEndpoint, style: const TextStyle(fontSize: 14)),
              subtitle: SelectableText(
                _endpoint ?? '…',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              ),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: l.edit,
                  icon: const Icon(Icons.edit_rounded, size: 19),
                  onPressed: _busy ? null : _editPort,
                ),
                IconButton(
                  icon: const Icon(Icons.copy_all_rounded, size: 19),
                  onPressed: _endpoint == null ? null : () => _copy(_endpoint!),
                ),
              ]),
            ),
            Divider(height: 0, thickness: 0.3, color: theme.dividerColor.withValues(alpha: 0.22)),
            ListTile(
              dense: true,
              leading: Icon(Icons.key_rounded, color: cs.primary),
              title: Text(l.mcpAccessToken, style: const TextStyle(fontSize: 14)),
              subtitle: SelectableText(
                McpService.instance.token ?? '',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              ),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: l.mcpRegenerateToken,
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                  onPressed: _busy ? null : _regenerateToken,
                ),
                IconButton(
                  icon: const Icon(Icons.copy_all_rounded, size: 19),
                  onPressed: () {
                    var t = McpService.instance.token;
                    if (t != null) _copy(t);
                  },
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          _card([
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(l.mcpLanGuide,
                  style: TextStyle(fontSize: 12.5, height: 1.5, color: cs.onSurfaceVariant)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
              child: Text(l.mcpOneClick,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.primary)),
            ),
            _commandBlock(cs, 'macOS / Linux', _oneClickSh()),
            _commandBlock(cs, 'Windows (PowerShell)', _oneClickPs1()),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(l.mcpOneClickHint,
                  style: TextStyle(fontSize: 11, height: 1.5, color: cs.onSurfaceVariant)),
            ),
            _commandBlock(cs, 'Claude Code', _claudeCommand()),
            _commandBlock(cs, 'Codex', _codexCommand()),
            _otherClientsBlock(cs),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Text(l.mcpLanTokenNote,
                  style: TextStyle(fontSize: 11.5, height: 1.5, color: cs.onSurfaceVariant)),
            ),
          ]),
          const SizedBox(height: 12),
        ],
        _card([
          SwitchListTile(
            value: cfg.mcpRedactEnabled,
            activeColor: cs.primary,
            onChanged: (v) {
              setState(() => cfg.mcpRedactEnabled = v);
              cfg.flushConfig();
            },
            title: Text(l.mcpRedact, style: const TextStyle(fontSize: 14)),
            subtitle: Text(l.mcpRedactDescribe,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.4)),
          ),
        ]),
        const SizedBox(height: 12),
        _card([
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(l.mcpAboutTitle,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
            child: Text(l.mcpAboutText,
                style: TextStyle(fontSize: 12, height: 1.5, color: cs.onSurfaceVariant)),
          ),
        ]),
        const SizedBox(height: 12),
        _card([
          InkWell(
            onTap: () => openMcpDoc(context),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(children: [
                Icon(Icons.open_in_new_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(l.mcpLearnMore, style: TextStyle(fontSize: 14, color: cs.primary)),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: cs.onSurfaceVariant),
              ]),
            ),
          ),
        ]),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.error_outline_rounded, size: 17, color: cs.error),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(_error!,
                      style: TextStyle(fontSize: 12, color: cs.onErrorContainer, height: 1.4))),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _statusRow(ColorScheme cs) {
    var color = _running ? const Color(0xFF34C759) : cs.onSurfaceVariant;
    var icon = _running ? Icons.check_circle_rounded : Icons.cancel_outlined;
    var label = _running ? l.mcpStatusRunning : l.mcpStatusStopped;
    return Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: color)),
    ]);
  }

  Widget _card(List<Widget> children) {
    var theme = Theme.of(context);
    return Card(
      color: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
          side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.13)),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  String _claudeCommand() {
    var token = McpService.instance.token ?? '';
    return 'claude mcp add ${McpClientNames.mobile} -s user --transport http ${_endpoint ?? ''} '
        '--header "Authorization: Bearer $token"';
  }

  /// Codex 远程 MCP 的 token 必须通过环境变量传入（CLI 不支持 --header）
  String _codexCommand() {
    var token = McpService.instance.token ?? '';
    return 'export PROXYPIN_MOBILE_TOKEN="$token"\n'
        'codex mcp remove ${McpClientNames.mobile} 2>/dev/null || true\n'
        'codex mcp add ${McpClientNames.mobile} --url ${_endpoint ?? ''} '
        '--bearer-token-env-var PROXYPIN_MOBILE_TOKEN';
  }

  /// 电脑端一键配置（macOS/Linux）：拉取手机下发的 shell 脚本并执行，
  /// 自动探测并配置已安装的 Claude Code / Codex / Cursor / Gemini CLI。
  String _oneClickSh() {
    var token = McpService.instance.token ?? '';
    var ip = _lanIp ?? '';
    var port = McpService.instance.port;
    return 'curl -s -H "Authorization: Bearer $token" '
        'http://$ip:$port/mcp/setup.sh | sh';
  }

  /// 电脑端一键配置（Windows PowerShell）
  String _oneClickPs1() {
    var token = McpService.instance.token ?? '';
    var ip = _lanIp ?? '';
    var port = McpService.instance.port;
    return 'irm -Headers @{ Authorization = "Bearer $token" } '
        'http://$ip:$port/mcp/setup.ps1 | iex';
  }

  /// 通用 Streamable HTTP 配置（mcpServers JSON），覆盖 Cursor / Cline / Gemini CLI /
  /// Cherry Studio / VS Code Copilot 等所有支持 HTTP 传输的 MCP 客户端。
  String _genericHttpConfig() {
    var entry = {
      'type': 'http',
      'url': _endpoint ?? '',
      'headers': {
        'Authorization': 'Bearer ${McpService.instance.token ?? ''}',
      },
    };
    return const JsonEncoder.withIndent('  ').convert({
      'mcpServers': {McpClientNames.mobile: entry}
    });
  }

  Widget _commandBlock(ColorScheme cs, String name, String command) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(name, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: cs.primary)),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _copy(command),
            icon: const Icon(Icons.copy_all_rounded, size: 15),
            label: Text(l.mcpCopy, style: const TextStyle(fontSize: 12.5)),
          ),
        ]),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(command,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.4)),
        ),
      ]),
    );
  }

  /// 其他 AI 客户端：通用 Streamable HTTP JSON 配置
  Widget _otherClientsBlock(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(l.mcpOtherClients,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: cs.primary)),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _copy(_genericHttpConfig()),
            icon: const Icon(Icons.copy_all_rounded, size: 15),
            label: Text(l.mcpCopy, style: const TextStyle(fontSize: 12.5)),
          ),
        ]),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(_genericHttpConfig(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.4)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, right: 8),
          child: Text(l.mcpOtherClientsHint,
              style: TextStyle(fontSize: 11, height: 1.5, color: cs.onSurfaceVariant)),
        ),
      ]),
    );
  }
}