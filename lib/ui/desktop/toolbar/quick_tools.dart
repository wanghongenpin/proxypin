import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/mcp/mcp_service.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/components/manager/hosts_manager.dart';
import 'package:proxypin/network/components/manager/network_condition_manager.dart';
import 'package:proxypin/network/components/manager/request_block_manager.dart';
import 'package:proxypin/network/components/manager/request_breakpoint_manager.dart';
import 'package:proxypin/network/components/manager/request_crypto_manager.dart';
import 'package:proxypin/network/components/manager/request_map_manager.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/components/manager/script_manager.dart';
import 'package:proxypin/ui/component/multi_window.dart';
import 'package:proxypin/ui/component/svg_icon.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/desktop/setting/external_proxy.dart';
import 'package:proxypin/ui/desktop/setting/filter.dart';
import 'package:proxypin/ui/desktop/setting/hosts.dart';
import 'package:proxypin/ui/desktop/setting/request_block.dart';
import 'package:proxypin/ui/desktop/setting/weak_network.dart';
import 'package:proxypin/ui/desktop/toolbar/mcp_panel.dart';

typedef QuickToolName = String Function(AppLocalizations localizations);
typedef QuickToolLaunch = Future<void> Function(BuildContext context, ProxyServer proxyServer);

/// 功能是否处于启用/生效状态（用于工具栏图标高亮：未启用灰色，启用主色）
typedef QuickToolActive = Future<bool> Function(ProxyServer proxyServer);

class QuickTool {
  final String id;

  /// assets/icons/ 下的设计稿线条图标名
  final String icon;
  final QuickToolName name;
  final QuickToolLaunch launch;

  /// 启用状态检查；为 null 时恒视为启用（保持高亮）
  final QuickToolActive? isActive;

  const QuickTool({required this.id, required this.icon, required this.name, required this.launch, this.isActive});
}

final trafficQuickTools = <QuickTool>[
  QuickTool(
      id: 'requestBlock',
      icon: 'block',
      name: (l) => l.requestBlock,
      isActive: (_) async {
        var m = await RequestBlockManager.instance;
        return m.enabled && m.list.isNotEmpty;
      },
      launch: (context, proxyServer) async {
        var manager = await RequestBlockManager.instance;
        if (!context.mounted) return;
        await showDialog(
            barrierDismissible: false,
            context: context,
            builder: (context) => RequestBlock(requestBlockManager: manager));
      }),
  QuickTool(
      id: 'requestRewrite',
      icon: 'pencil',
      name: (l) => l.requestRewrite,
      isActive: (_) async {
        var m = await RequestRewriteManager.instance;
        return m.enabled && m.rules.isNotEmpty;
      },
      launch: (context, proxyServer) async {
        await MultiWindow.openWindow(AppLocalizations.of(context)!.requestRewrite, 'RequestRewriteWidget',
            size: const Size(800, 750));
      }),
  QuickTool(
      id: 'requestMap',
      icon: 'swap',
      name: (l) => l.requestMap,
      isActive: (_) async {
        var m = await RequestMapManager.instance;
        return m.enabled && m.rules.isNotEmpty;
      },
      launch: (context, proxyServer) async {
        await MultiWindow.openWindow(AppLocalizations.of(context)!.requestMap, 'RequestMapPage',
            size: const Size(800, 720));
      }),
  QuickTool(
      id: 'requestCrypto',
      icon: 'key',
      name: (l) => l.requestCrypto,
      isActive: (_) async {
        var m = await RequestCryptoManager.instance;
        return m.enabled && m.rules.isNotEmpty;
      },
      launch: (context, proxyServer) async {
        await MultiWindow.openWindow(AppLocalizations.of(context)!.requestCrypto, 'RequestCryptoPage',
            size: const Size(820, 750));
      }),
  QuickTool(
      id: 'script',
      icon: 'code',
      name: (l) => l.script,
      isActive: (_) async {
        var m = await ScriptManager.instance;
        return m.enabled && m.list.isNotEmpty;
      },
      launch: (context, proxyServer) async {
        await MultiWindow.openWindow(AppLocalizations.of(context)!.script, 'ScriptWidget',
            size: const Size(800, 780));
      }),
  QuickTool(
      id: 'breakpoint',
      icon: 'breakpoint',
      name: (l) => l.breakpoint,
      isActive: (_) async {
        var m = await RequestBreakpointManager.instance;
        return m.enabled && m.list.isNotEmpty;
      },
      launch: (context, proxyServer) async {
        await MultiWindow.openWindow(AppLocalizations.of(context)!.breakpoint, 'RequestBreakpointPage',
            size: const Size(800, 750));
      }),
];

final settingQuickTools = <QuickTool>[
  QuickTool(
      id: 'domainFilter',
      icon: 'funnel',
      name: (l) => l.domainFilter,
      isActive: (_) async => HostFilter.whitelist.enabled || HostFilter.blacklist.enabled,
      launch: (context, proxyServer) async {
        await showDialog(
            barrierDismissible: false,
            context: context,
            builder: (context) => FilterDialog(configuration: proxyServer.configuration));
      }),
  QuickTool(
      id: 'hosts',
      icon: 'lines',
      name: (l) => l.hosts,
      isActive: (_) async {
        var m = await HostsManager.instance;
        return m.enabled && m.list.isNotEmpty;
      },
      launch: (context, proxyServer) async {
        var hosts = await HostsManager.instance;
        if (!context.mounted) return;
        await showDialog(
            barrierDismissible: false, context: context, builder: (context) => HostsDialog(hostsManager: hosts));
      }),
  QuickTool(
      id: 'externalProxy',
      icon: 'arrow_out',
      name: (l) => l.externalProxy,
      isActive: (proxyServer) async => proxyServer.configuration.externalProxy?.enabled == true,
      launch: (context, proxyServer) async {
        await showDialog(
            barrierDismissible: false,
            context: context,
            builder: (context) => ExternalProxyDialog(configuration: proxyServer.configuration));
      }),
  QuickTool(
      id: 'weakNetwork',
      icon: 'zap',
      name: (l) => l.weakNetwork,
      isActive: (_) async {
        var m = await NetworkConditionManager.instance;
        return m.enabled && m.rules.any((r) => r.enabled);
      },
      launch: (context, proxyServer) async {
        var manager = await NetworkConditionManager.instance;
        if (!context.mounted) return;
        await showDialog(
            barrierDismissible: false, context: context, builder: (context) => WeakNetworkDialog(manager: manager));
      }),
  QuickTool(
      id: 'mcpService',
      icon: 'mcp',
      name: (l) => l.mcpService,
      isActive: (_) async => McpService.instance.isRunning,
      launch: (context, proxyServer) async {
        await McpServiceDialog.show(context, proxyServer);
      }),
];

final quickTools = <QuickTool>[...trafficQuickTools, ...settingQuickTools];

QuickTool? quickToolOf(String id) {
  for (var tool in quickTools) {
    if (tool.id == id) {
      return tool;
    }
  }
  return null;
}

void toggleToolbarPin(AppConfiguration appConfiguration, String id) {
  var pins = List<String>.of(appConfiguration.toolbarPins.value);
  if (!pins.remove(id)) {
    pins.add(id);
  }
  appConfiguration.toolbarPins.value = pins;
  appConfiguration.flushConfig();
}

class QuickToolbar extends StatefulWidget {
  final ProxyServer proxyServer;

  const QuickToolbar({super.key, required this.proxyServer});

  @override
  State<QuickToolbar> createState() => _QuickToolbarState();
}

class _QuickToolbarState extends State<QuickToolbar> {
  /// 各工具的启用状态缓存：启用主色高亮，未启用灰色（管理器均为缓存单例，读取近零成本）
  final Map<String, bool> _active = {};
  String _lastPinsKey = '';

  @override
  void initState() {
    super.initState();
    _refresh();
    // 子窗口（重写/映射/加密/脚本/断点）开关变化 → 主窗口 reload 后版本号递增 → 刷新高亮
    managerStateVersion.addListener(_onManagerStateChanged);
  }

  @override
  void dispose() {
    managerStateVersion.removeListener(_onManagerStateChanged);
    super.dispose();
  }

  void _onManagerStateChanged() => _refresh();

  void _refresh() {
    var pins = AppConfiguration.current?.toolbarPins.value ?? const <String>[];
    for (var id in pins) {
      var checker = quickToolOf(id)?.isActive;
      if (checker == null) {
        _active[id] = true; // 无状态检查的工具恒高亮（当前没有此类工具）
        continue;
      }
      checker(widget.proxyServer).then((active) {
        if (mounted && _active[id] != active) {
          setState(() => _active[id] = active);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    var appConfiguration = AppConfiguration.current;
    if (appConfiguration == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<List<String>>(
        valueListenable: appConfiguration.toolbarPins,
        builder: (context, pins, _) {
          // 固定项变化时调度一次状态刷新（microtask 避开 build 期 setState）
          var pinsKey = pins.join(',');
          if (pinsKey != _lastPinsKey) {
            _lastPinsKey = pinsKey;
            Future.microtask(_refresh);
          }
          var theme = Theme.of(context);
          var tools = pins.map(quickToolOf).whereType<QuickTool>().toList();
          return Row(children: [
            for (var tool in tools) ...[
              IconButton(
                  tooltip: tool.name(AppLocalizations.of(context)!),
                  // 设计稿 .tbtn：32x32 点击盒
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  // 未启用灰色，启用才主色高亮
                  icon: SvgIcon(tool.icon,
                      size: 17,
                      color: _active[tool.id] == true
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant),
                  onPressed: () async {
                    await tool.launch(context, widget.proxyServer);
                    // 弹窗类工具关闭后刷新状态；独立窗口类在下次固定项变化/启动时刷新
                    _refresh();
                  }),
              const SizedBox(width: 6),
            ],
            _menuButton(context, appConfiguration),
          ]);
        });
  }

  Widget _menuButton(BuildContext context, AppConfiguration appConfiguration) {
    var localizations = AppLocalizations.of(context)!;
    var theme = Theme.of(context);
    return PopupMenuButton<String>(
        tooltip: localizations.allFunctions,
        icon: SvgIcon('dots', size: 17, color: Theme.of(context).colorScheme.onSurfaceVariant),
        position: PopupMenuPosition.under,
        itemBuilder: (menuContext) => [
              PopupMenuItem<String>(
                  enabled: false,
                  height: 26,
                  padding: const EdgeInsets.only(left: 14),
                  child: Text(localizations.trafficControl,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurfaceVariant))),
              for (var tool in trafficQuickTools) _menuRow(context, tool, appConfiguration),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                  height: 40,
                  child: Text(localizations.customizeToolbar, style: TextStyle(color: theme.colorScheme.primary)),
                  onTap: () => showDialog(
                      context: context,
                      builder: (_) => CustomizeToolbarDialog(appConfiguration: appConfiguration))),
            ]);
  }

  PopupMenuItem<String> _menuRow(BuildContext context, QuickTool tool, AppConfiguration appConfiguration) {
    var localizations = AppLocalizations.of(context)!;
    var theme = Theme.of(context);
    return PopupMenuItem<String>(
        value: tool.id,
        height: 40,
        padding: EdgeInsets.zero,
        onTap: () {
          tool.launch(context, widget.proxyServer);
        },
        child: SizedBox(
            height: 40,
            child: Row(children: [
              const SizedBox(width: 14),
              SvgIcon(tool.icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(child: Text(tool.name(localizations), style: const TextStyle(fontSize: 13))),
              ValueListenableBuilder<List<String>>(
                  valueListenable: appConfiguration.toolbarPins,
                  builder: (context, pins, _) {
                    var pinned = pins.contains(tool.id);
                    return InkWell(
                        onTap: () => toggleToolbarPin(appConfiguration, tool.id),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            child: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined,
                                size: 16,
                                color: pinned ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant)));
                  }),
            ])));
  }
}

class CustomizeToolbarDialog extends StatelessWidget {
  final AppConfiguration appConfiguration;

  const CustomizeToolbarDialog({super.key, required this.appConfiguration});

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    return Dialog(
        child: ValueListenableBuilder<List<String>>(
            valueListenable: appConfiguration.toolbarPins,
            builder: (context, pins, _) {
              var theme = Theme.of(context);
              var pinnedTools = pins.map(quickToolOf).whereType<QuickTool>().toList();
              return ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
                        child: Row(children: [
                          Text(localizations.customizeToolbar,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          TextButton(
                              onPressed: () {
                                appConfiguration.toolbarPins.value = List<String>.of(AppConfiguration.defaultToolbarPins);
                                appConfiguration.flushConfig();
                              },
                              child: Text(localizations.restoreDefaults)),
                          const CloseButton(),
                        ])),
                    Flexible(
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(localizations.pinnedDragSort,
                                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 8),
                              if (pinnedTools.isEmpty)
                                const SizedBox(height: 4)
                              else
                                ReorderableListView(
                                    shrinkWrap: true,
                                    buildDefaultDragHandles: false,
                                    padding: EdgeInsets.zero,
                                    onReorderItem: (oldIndex, newIndex) {
                                      var list = List<String>.of(appConfiguration.toolbarPins.value);
                                      var id = list.removeAt(oldIndex);
                                      list.insert(newIndex, id);
                                      appConfiguration.toolbarPins.value = list;
                                      appConfiguration.flushConfig();
                                    },
                                    children: [
                                      for (var i = 0; i < pinnedTools.length; i++)
                                        _pinnedChip(context, pinnedTools[i], i)
                                    ]),
                              const SizedBox(height: 14),
                              Text(localizations.pinToolsHint,
                                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 8),
                              Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [for (var tool in quickTools) _toolGridItem(context, tool, pins.contains(tool.id))]),
                            ])))
                  ]));
            }));
  }

  Widget _pinnedChip(BuildContext context, QuickTool tool, int index) {
    var theme = Theme.of(context);
    var localizations = AppLocalizations.of(context)!;
    return Align(
        key: ValueKey(tool.id),
        alignment: Alignment.centerLeft,
        child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.35))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                      padding: const EdgeInsets.only(left: 8, top: 7, bottom: 7),
                      child:
                          Icon(Icons.drag_indicator, size: 16, color: theme.colorScheme.onSurfaceVariant))),
              const SizedBox(width: 6),
              SvgIcon(tool.icon, size: 15, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Padding(
                  padding: const EdgeInsets.only(right: 6, top: 7, bottom: 7),
                  child: Text(tool.name(localizations), style: const TextStyle(fontSize: 12.5))),
              InkWell(
                  onTap: () => toggleToolbarPin(appConfiguration, tool.id),
                  child: Padding(
                      padding: const EdgeInsets.only(left: 2, right: 6, top: 7, bottom: 7),
                      child: Icon(Icons.close, size: 15, color: theme.colorScheme.onSurfaceVariant))),
            ])));
  }

  Widget _toolGridItem(BuildContext context, QuickTool tool, bool pinned) {
    var theme = Theme.of(context);
    var localizations = AppLocalizations.of(context)!;
    return InkWell(
        onTap: () => toggleToolbarPin(appConfiguration, tool.id),
        borderRadius: BorderRadius.circular(9),
        child: Container(
            width: 86,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                color: pinned ? theme.colorScheme.primary.withValues(alpha: 0.06) : null,
                border: Border.all(color: theme.dividerColor.withValues(alpha: pinned ? 0 : 0.5))),
            // 设计稿 .cz-item：图标+文字整体在格子里水平居中（Stack 默认 topStart 会导致短名字左偏）
            child: Stack(alignment: Alignment.topCenter, children: [
              Column(children: [
                SvgIcon(tool.icon, size: 19, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(height: 5),
                Text(tool.name(localizations),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurface)),
              ]),
              Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: pinned ? okColor(theme) : theme.colorScheme.primary),
                      child: Icon(pinned ? Icons.check : Icons.add, size: 11, color: Colors.white))),
            ])));
  }
}
