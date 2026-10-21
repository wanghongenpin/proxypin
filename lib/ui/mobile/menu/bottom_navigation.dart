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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/mcp/mcp_service.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/components/manager/environment_manager.dart';
import 'package:proxypin/network/components/manager/hosts_manager.dart';
import 'package:proxypin/network/components/manager/request_block_manager.dart';
import 'package:proxypin/network/components/manager/request_breakpoint_manager.dart';
import 'package:proxypin/network/components/manager/request_crypto_manager.dart';
import 'package:proxypin/network/components/manager/request_map_manager.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/components/manager/script_manager.dart';
import 'package:proxypin/storage/histories.dart';
import 'package:proxypin/ui/component/app_colors.dart';
import 'package:proxypin/ui/component/proxy_port_setting.dart';
import 'package:proxypin/ui/component/svg_icon.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/mobile/menu/drawer.dart';
import 'package:proxypin/ui/mobile/mobile.dart';
import 'package:proxypin/ui/mobile/request/favorite.dart';
import 'package:proxypin/ui/mobile/request/history.dart';
import 'package:proxypin/ui/mobile/menu/weak_network_tile.dart';
import 'package:proxypin/ui/mobile/setting/environment.dart';
import 'package:proxypin/ui/mobile/setting/hosts.dart';
import 'package:proxypin/ui/mobile/setting/mcp.dart';
import 'package:proxypin/ui/mobile/setting/preference.dart';
import 'package:proxypin/ui/mobile/setting/proxy_ignore_domain.dart';
import 'package:proxypin/ui/mobile/setting/request_block.dart';
import 'package:proxypin/ui/mobile/setting/request_breakpoint.dart';
import 'package:proxypin/ui/mobile/setting/request_crypto.dart';
import 'package:proxypin/ui/mobile/setting/request_map.dart';
import 'package:proxypin/ui/mobile/setting/request_rewrite.dart';
import 'package:proxypin/ui/mobile/setting/script.dart';
import 'package:proxypin/ui/mobile/setting/ssl.dart';
import 'package:proxypin/ui/mobile/widgets/about.dart';

import '../../component/widgets.dart';
import '../setting/proxy.dart';

/// @author wanghongen
/// 2024/9/30
Future<void> navigator(BuildContext context, Widget widget) async {
  if (context.mounted) {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (BuildContext context) => widget),
    );
  }
}

/// 配置/设置页通用：白卡片容器（新风格：#E4E6EB 发丝边、10 圆角）
Widget menuCard(BuildContext context, List<Widget> children) {
  var theme = Theme.of(context);
  return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
          side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.55)),
          borderRadius: BorderRadius.circular(10)),
      child: Column(children: children));
}

/// 配置/设置页通用入口行：28px 语义色淡色块图标（[iconColor]，见 AppColors）+ 15px 标题 + 灰色 chevron。
/// 块/图标尺寸按真机可读性放大（设计稿 22/13 → 28/17，图标/块 ≈0.6 不变）。
/// [status] 行尾状态摘要（对齐桌面端流量控制页），启用时 [statusOn] 置绿。
Widget menuTile(BuildContext context, String icon, String title, Future<void> Function() onTap,
    {String? status, bool statusOn = false, required Color iconColor}) {
  var theme = Theme.of(context);
  var chevron = Icon(Icons.keyboard_arrow_right, size: 18, color: theme.colorScheme.onSurfaceVariant);
  return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
              color: AppColors.tint(iconColor, theme.brightness), borderRadius: BorderRadius.circular(7)),
          child: Center(child: SvgIcon(icon, size: 17, color: AppColors.icon(iconColor, theme.brightness)))),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      trailing: status == null
          ? chevron
          : Row(mainAxisSize: MainAxisSize.min, children: [
              Text(status,
                  style:
                      TextStyle(fontSize: 12, color: statusOn ? okColor(theme) : theme.colorScheme.onSurfaceVariant)),
              chevron,
            ]),
      onTap: () async {
        await onTap();
      });
}

/// 28px 语义色字符色块（设计稿 micg：开关行无象形图标时用 S5/H2 字符，同 Base64/Unicode 的 B/U 手法）
Widget glyphTile(BuildContext context, String glyph, Color color) {
  var theme = Theme.of(context);
  return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
          color: AppColors.tint(color, theme.brightness), borderRadius: BorderRadius.circular(7)),
      child: Center(
          child: Text(glyph,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: AppColors.icon(color, theme.brightness)))));
}

/// 卡片内行分隔线：indent 对齐标题文字（带图标行 58 = 14 内边距 + 28 图标 + 16 间隔，无图标行 14）
Widget menuDivider(BuildContext context, {double indent = 58}) =>
    Divider(height: 0.5, thickness: 0.5, indent: indent, color: Theme.of(context).dividerColor.withValues(alpha: 0.35));

/// 配置页：收藏/历史 + 流量控制与网络相关配置入口。
/// 流量控制各行尾部展示状态摘要（未开启 / 启用中 · N 条规则），与桌面端「流量控制」页口径一致。
class ConfigPage extends StatefulWidget {
  final ProxyServer proxyServer;

  const ConfigPage({super.key, required this.proxyServer});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  RequestBlockManager? _blockManager;
  RequestRewriteManager? _rewriteManager;
  RequestMapManager? _mapManager;
  RequestCryptoManager? _cryptoManager;
  ScriptManager? _scriptManager;
  RequestBreakpointManager? _breakpointManager;
  EnvironmentManager? _envManager;

  HistoryTask get historyTask =>
      HistoryTask.ensureInstance(widget.proxyServer.configuration, MobileApp.container);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  /// 加载各流量控制 manager（单例）供行尾状态展示；子页返回后调用以刷新状态。
  Future<void> _reload() async {
    var block = await RequestBlockManager.instance;
    var rewrite = await RequestRewriteManager.instance;
    var map = await RequestMapManager.instance;
    var crypto = await RequestCryptoManager.instance;
    var script = await ScriptManager.instance;
    var breakpoint = await RequestBreakpointManager.instance;
    var env = await EnvironmentManager.instance;
    if (!mounted) return;
    setState(() {
      _blockManager = block;
      _rewriteManager = rewrite;
      _mapManager = map;
      _cryptoManager = crypto;
      _scriptManager = script;
      _breakpointManager = breakpoint;
      _envManager = env;
    });
  }

  /// 状态摘要文案：无规则时不显示（保持行尾清爽）；有规则但全局开关关闭 = 未开启；
  /// 否则展示启用中的规则/脚本数。
  String? _ruleStatus(AppLocalizations localizations, bool enabled, int count, {bool isScript = false}) {
    if (count == 0) return null;
    if (!enabled) return localizations.notEnabled;
    return isScript ? localizations.scriptsCount(count) : localizations.rulesCount(count);
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    var iconColor = Theme.of(context).colorScheme.onSurfaceVariant;
    var arrow = Icon(Icons.keyboard_arrow_right, size: 18, color: iconColor);

    return Scaffold(
        appBar: PreferredSize(
            preferredSize: const Size.fromHeight(42),
            child: AppBar(
              title: Text(localizations.config, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
              centerTitle: true,
            )),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          menuCard(context, [
            menuTile(context, 'star', localizations.favorites, () async {
              await navigator(context, MobileFavorites(proxyServer: widget.proxyServer));
            }, iconColor: AppColors.favorite),
            menuDivider(context),
            menuTile(context, 'clock', localizations.history, () async {
              await navigator(
                  context,
                  MobileHistory(
                      proxyServer: widget.proxyServer, container: MobileApp.container, historyTask: historyTask));
            }, iconColor: AppColors.history),
          ]),
          const SizedBox(height: 12),
          menuCard(context, [
            menuTile(context, 'lines', localizations.hosts, () async {
              var hostsManager = await HostsManager.instance;
              if (context.mounted) await navigator(context, HostsPage(hostsManager: hostsManager));
            }, iconColor: AppColors.hosts),
            menuDivider(context),
            menuTile(context, 'block', localizations.requestBlock, () async {
              var manager = _blockManager ?? await RequestBlockManager.instance;
              if (context.mounted) await navigator(context, MobileRequestBlock(requestBlockManager: manager));
              _reload();
            },
                status: _blockManager == null
                    ? null
                    : _ruleStatus(localizations, _blockManager!.enabled, _blockManager!.list.length),
                statusOn: _blockManager?.enabled == true,
                iconColor: AppColors.requestBlock),
            menuDivider(context),
            menuTile(context, 'pencil', localizations.requestRewrite, () async {
              var manager = _rewriteManager ?? await RequestRewriteManager.instance;
              if (context.mounted) await navigator(context, MobileRequestRewrite(requestRewrites: manager));
              _reload();
            },
                status: _rewriteManager == null
                    ? null
                    : _ruleStatus(localizations, _rewriteManager!.enabled, _rewriteManager!.rules.length),
                statusOn: _rewriteManager?.enabled == true,
                iconColor: AppColors.requestRewrite),
            menuDivider(context),
            menuTile(context, 'swap', localizations.requestMap, () async {
              await navigator(context, MobileRequestMapPage());
              _reload();
            },
                status: _mapManager == null
                    ? null
                    : _ruleStatus(localizations, _mapManager!.enabled, _mapManager!.rules.length),
                statusOn: _mapManager?.enabled == true,
                iconColor: AppColors.requestMap),
            menuDivider(context),
            menuTile(context, 'key', localizations.requestCrypto, () async {
              await navigator(context, const MobileRequestCryptoPage());
              _reload();
            },
                status: _cryptoManager == null
                    ? null
                    : _ruleStatus(localizations, _cryptoManager!.enabled, _cryptoManager!.rules.length),
                statusOn: _cryptoManager?.enabled == true,
                iconColor: AppColors.requestCrypto),
            menuDivider(context),
            menuTile(context, 'code', localizations.script, () async {
              await navigator(context, const MobileScript());
              _reload();
            },
                status: _scriptManager == null
                    ? null
                    : _ruleStatus(localizations, _scriptManager!.enabled, _scriptManager!.list.length,
                        isScript: true),
                statusOn: _scriptManager?.enabled == true,
                iconColor: AppColors.script),
            menuDivider(context),
            menuTile(context, 'breakpoint', localizations.breakpoint, () async {
              var manager = _breakpointManager ?? await RequestBreakpointManager.instance;
              if (context.mounted) await navigator(context, MobileRequestBreakpointPage(manager: manager));
              _reload();
            },
                status: _breakpointManager == null
                    ? null
                    : _ruleStatus(localizations, _breakpointManager!.enabled, _breakpointManager!.list.length),
                statusOn: _breakpointManager?.enabled == true,
                iconColor: AppColors.breakpoint),
            menuDivider(context),
            WeakNetworkMenuTile(
                leading: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                        color: AppColors.tint(AppColors.weakNetwork, Theme.of(context).brightness),
                        borderRadius: BorderRadius.circular(7)),
                    child: Center(
                        child: SvgIcon('zap',
                            size: 17, color: AppColors.icon(AppColors.weakNetwork, Theme.of(context).brightness)))),
                titleStyle: const TextStyle(fontSize: 15),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                trailing: arrow,
                showStatus: true),
            menuDivider(context),
            menuTile(context, 'globe', localizations.environmentVariables, () async {
              await navigator(context, const MobileEnvironmentPage());
              _reload();
            },
                // 行尾显示当前激活的环境名（灰色取值、非状态，对齐设计稿 .val）；仅 Global 生效时不显示
                status: _envManager?.active?.name,
                iconColor: AppColors.environment),
          ]),
          const SizedBox(height: 8),
        ]));
  }
}

class SettingPage extends StatefulWidget {
  final ProxyServer proxyServer;
  final AppConfiguration appConfiguration;

  const SettingPage({super.key, required this.proxyServer, required this.appConfiguration});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  // 供 build 内沿用旧字段名，减少 diff
  ProxyServer get proxyServer => widget.proxyServer;

  AppConfiguration get appConfiguration => widget.appConfiguration;

  bool _mcpRunning = McpService.instance.isRunning;
  Timer? _mcpPoll;

  @override
  void initState() {
    super.initState();
    // 本页随 IndexedStack 首帧构建，早于 MCP 自动启动完成；McpService 非 Listenable，
    // 短暂轮询直至服务跑起来（10s 兜底），手动开关则靠子页返回时刷新
    if (!_mcpRunning) {
      _mcpPoll = Timer.periodic(const Duration(milliseconds: 500), (t) {
        if (!mounted) return;
        var running = McpService.instance.isRunning;
        if (running != _mcpRunning) setState(() => _mcpRunning = running);
        if (running || t.tick >= 20) {
          t.cancel();
          _mcpPoll = null;
        }
      });
    }
  }

  @override
  void dispose() {
    _mcpPoll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configuration = proxyServer.configuration;

    AppLocalizations localizations = AppLocalizations.of(context)!;
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    const titleStyle = TextStyle(fontSize: 15);

    return Scaffold(
        appBar: PreferredSize(
            preferredSize: const Size.fromHeight(42),
            child: AppBar(
              title: Text(localizations.setting, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
              centerTitle: true,
            )),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          menuCard(context, [
            menuTile(context, 'lock', localizations.httpsProxy, () async {
              navigator(context, MobileSslWidget(proxyServer: proxyServer));
            }, iconColor: AppColors.httpsProxy),
            menuDivider(context),
            menuTile(context, 'funnel', localizations.filter, () async {
              navigator(context, FilterMenu(proxyServer: proxyServer));
            }, iconColor: AppColors.filter),
          ]),
          const SizedBox(height: 12),
          // Port and switches
          menuCard(context, [
            PortWidget(
                proxyServer: proxyServer,
                title: '${localizations.proxy}${isCN ? '' : ' '}${localizations.port}',
                textStyle: titleStyle,
                leading: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                        color: AppColors.tint(AppColors.proxyPort, Theme.of(context).brightness),
                        borderRadius: BorderRadius.circular(7)),
                    child: Center(
                        child: SvgIcon('server',
                            size: 17, color: AppColors.icon(AppColors.proxyPort, Theme.of(context).brightness))))),
            menuDivider(context),
            if (Platform.isAndroid)
              ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  title: Text(localizations.systemProxy, style: titleStyle),
                  trailing: SwitchWidget(
                      value: configuration.enableSystemProxy,
                      scale: 0.8,
                      onChanged: (value) {
                        configuration.enableSystemProxy = value;
                        proxyServer.configuration.flushConfig();
                      })),
            if (Platform.isAndroid) menuDivider(context),
            ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                leading: glyphTile(context, 'S5', AppColors.socks5),
                title: const Text("SOCKS5", style: titleStyle),
                trailing: SwitchWidget(
                    value: configuration.enableSocks5,
                    scale: 0.8,
                    onChanged: (value) {
                      configuration.enableSocks5 = value;
                      proxyServer.configuration.flushConfig();
                    })),
            menuDivider(context),
            ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                leading: glyphTile(context, 'H2', AppColors.http2),
                title: Text(localizations.enabledHTTP2, style: titleStyle),
                trailing: SwitchWidget(
                    value: configuration.enabledHttp2,
                    scale: 0.8,
                    onChanged: (value) {
                      configuration.enabledHttp2 = value;
                      proxyServer.configuration.flushConfig();
                    })),
            menuDivider(context),
            menuTile(context, 'arrow_out', localizations.externalProxy, () async {
              showDialog(context: context, builder: (_) => ExternalProxyDialog(configuration: proxyServer.configuration));
            }, iconColor: AppColors.externalProxy),
            menuDivider(context),
            // 忽略域名为独立编辑页（设计稿 tag-4：卡内嵌输入体验差，与入口行形态统一）
            menuTile(context, 'minus_circle', localizations.proxyIgnoreDomain, () async {
              await navigator(context, ProxyIgnoreDomainPage(configuration: proxyServer.configuration));
            }, iconColor: AppColors.proxyIgnoreDomain),
          ]),
          const SizedBox(height: 12),
          menuCard(context, [
            menuTile(context, 'mcp', localizations.mcpService, () async {
              await navigator(context, MobileMcpSetting(proxyServer: proxyServer));
              // 子页可能切换了 MCP 开关，返回后刷新行尾运行状态
              if (mounted) setState(() => _mcpRunning = McpService.instance.isRunning);
            },
                iconColor: AppColors.mcp,
                // 行尾仅运行中时显示绿「运行中」（设计稿 tag-3）；停止是常态不显示
                status: _mcpRunning ? localizations.statusRunning : null,
                statusOn: true),
            menuDivider(context),
            menuTile(context, 'sliders', localizations.preference, () async {
              navigator(context, Preference(proxyServer: proxyServer, appConfiguration: appConfiguration));
            }, iconColor: AppColors.preference),
            menuDivider(context),
            menuTile(context, 'info', localizations.about, () async {
              navigator(context, const About());
            }, iconColor: AppColors.about),
          ]),
          const SizedBox(height: 8),
        ]));
  }
}
