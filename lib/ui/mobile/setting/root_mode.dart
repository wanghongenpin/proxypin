import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/native/net_interfaces.dart';
import 'package:proxypin/native/root_proxy.dart';
import 'package:proxypin/native/vpn.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/mobile/raw_capture/raw_capture_page.dart';
import 'package:proxypin/utils/ip.dart';

/// Android Root 模式设置页：iptables 透明代理，不占用 VPN 通道。
class RootModeSettingPage extends StatefulWidget {
  final ProxyServer proxyServer;

  const RootModeSettingPage({super.key, required this.proxyServer});

  @override
  State<RootModeSettingPage> createState() => _RootModeSettingPageState();
}

class _RootModeSettingPageState extends State<RootModeSettingPage> {
  late final TextEditingController _portsController;
  final FocusNode _portsFocus = FocusNode();
  bool _checking = false;
  bool _dirty = false;

  Configuration get configuration => widget.proxyServer.configuration;

  bool get isCN => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    _portsController = TextEditingController(text: configuration.rootRedirectPorts);
    _portsFocus.addListener(() {
      if (!_portsFocus.hasFocus) _savePorts();
    });
  }

  @override
  void dispose() {
    _savePorts();
    _portsFocus.dispose();
    _portsController.dispose();
    if (_dirty) _applyIfRunning();
    super.dispose();
  }

  void _savePorts() {
    final text = _portsController.text.trim();
    if (text == configuration.rootRedirectPorts) return;
    configuration.rootRedirectPorts = text;
    configuration.flushConfig();
    _dirty = true;
  }

  /// 抓包运行中修改配置时立即按新模式重启通道
  Future<void> _applyIfRunning() async {
    if (!Vpn.isVpnStarted) return;
    final host = await localIp(readCache: false);
    await Vpn.restartVpn(host, widget.proxyServer.port, configuration);
  }

  Future<void> _toggleRoot(bool value) async {
    if (value) {
      setState(() => _checking = true);
      final available = await RootProxy.isRootAvailable();
      if (!mounted) return;
      setState(() => _checking = false);
      if (!available) {
        FlutterToastr.show(isCN ? '未获取到 Root 权限' : 'Root permission not granted', context, duration: 3);
        return;
      }
    }
    setState(() => configuration.rootModeEnabled = value);
    await configuration.flushConfig();
    await _applyIfRunning();
    _dirty = false;
  }

  Future<void> _pickInterfaces() async {
    final all = await NetInterfaceInfo.list();
    if (!mounted) return;
    final uplinks = all.where((e) => e.isUplink).toList();
    // 已选但当前不存在的网卡（如未连接的移动数据）也保留显示
    for (final name in configuration.rootInterfaces) {
      if (!uplinks.any((e) => e.name == name)) uplinks.add(NetInterfaceInfo(name, 'other', up: false));
    }
    final selected = configuration.rootInterfaces.toSet();
    final result = await showDialog<Set<String>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialog) => AlertDialog(
                  title: Text(isCN ? '捕获网卡' : 'Interfaces', style: const TextStyle(fontSize: 16)),
                  contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  scrollable: true,
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        isCN
                            ? '只捕获经由所选网卡发出的流量；不选 = 全部。'
                            : 'Only capture traffic leaving via the selected interfaces. None = all.',
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 6),
                    for (final e in uplinks)
                      CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: selected.contains(e.name),
                          title: NetInterfaceTile(e),
                          onChanged: (v) => setDialog(() => v == true ? selected.add(e.name) : selected.remove(e.name))),
                  ]),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, <String>{}), child: Text(isCN ? '全部' : 'All')),
                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text(isCN ? '取消' : 'Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, selected), child: Text(isCN ? '确定' : 'OK')),
                  ],
                )));
    if (result == null) return;
    setState(() => configuration.rootInterfaces = result.toList());
    await configuration.flushConfig();
    _dirty = true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant);

    return Scaffold(
        appBar: AppBar(
            centerTitle: true, title: Text(isCN ? 'Root 模式' : 'Root Mode', style: const TextStyle(fontSize: 16))),
        body: ListView(padding: const EdgeInsets.all(14), children: [
          Text(
              isCN
                  ? '使用 iptables 将应用的 TCP 流量透明重定向到 ProxyPin，不占用系统 VPN，可与其它 VPN 应用同时使用。'
                      '应用白名单/黑名单、代理忽略域名（IP/CIDR/域名）同样生效。需要 Magisk / KernelSU / APatch 等 Root 授权。'
                  : 'Uses iptables to transparently redirect app TCP traffic to ProxyPin without occupying the system VPN, '
                      'so it can run alongside other VPN apps. App whitelist/blacklist and proxy ignore list (IP/CIDR/domain) still apply. '
                      'Requires root (Magisk / KernelSU / APatch).',
              style: hint),
          const SizedBox(height: 12),
          Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              child: Column(children: [
                ListTile(
                    title: Text(isCN ? '启用 Root 模式' : 'Enable Root Mode'),
                    subtitle: Text(isCN ? '代替 VPN 抓包' : 'Capture without VPN', style: hint),
                    trailing: _checking
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : SwitchWidget(value: configuration.rootModeEnabled, scale: 0.8, onChanged: _toggleRoot)),
                const Divider(height: 0.5, thickness: 0.5),
                ListTile(
                    title: Text(isCN ? '屏蔽 IPv6 TCP' : 'Block IPv6 TCP'),
                    subtitle: Text(
                        isCN
                            ? '代理仅监听 IPv4，拒绝被捕获应用的 IPv6 连接使其回落到 IPv4'
                            : 'Proxy listens on IPv4 only; reject IPv6 so apps fall back to IPv4',
                        style: hint),
                    trailing: SwitchWidget(
                        value: configuration.rootBlockIpv6,
                        scale: 0.8,
                        onChanged: (value) async {
                          setState(() => configuration.rootBlockIpv6 = value);
                          await configuration.flushConfig();
                          _dirty = true;
                        })),
                const Divider(height: 0.5, thickness: 0.5),
                ListTile(
                    title: Text(isCN ? '屏蔽 QUIC (HTTP/3)' : 'Block QUIC (HTTP/3)'),
                    subtitle: Text(
                        isCN
                            ? '拒绝被捕获应用的 UDP 443，使其回落到可抓包的 TCP'
                            : 'Reject UDP 443 so apps fall back to capturable TCP',
                        style: hint),
                    trailing: SwitchWidget(
                        value: configuration.rootBlockQuic,
                        scale: 0.8,
                        onChanged: (value) async {
                          setState(() => configuration.rootBlockQuic = value);
                          await configuration.flushConfig();
                          _dirty = true;
                        })),
              ])),
          const SizedBox(height: 12),
          Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              child: Column(children: [
                ListTile(
                    title: Text(isCN ? '捕获网卡' : 'Interfaces'),
                    subtitle: Text(
                        configuration.rootInterfaces.isEmpty
                            ? (isCN ? '全部网卡' : 'All interfaces')
                            : configuration.rootInterfaces.join(', '),
                        style: hint),
                    trailing: const Icon(Icons.keyboard_arrow_right),
                    onTap: _pickInterfaces),
                const Divider(height: 0.5, thickness: 0.5),
                ListTile(
                    title: Text(isCN ? '捕获热点 / 共享设备' : 'Capture hotspot / tethered devices'),
                    subtitle: Text(
                        isCN
                            ? '连接本机热点、USB 或蓝牙共享的电脑 / 手机流量也进入代理，无需在对方设置代理。'
                                '对方需信任 ProxyPin 证书才能解密 HTTPS（在对方浏览器打开 http://<手机热点IP>:${widget.proxyServer.port}/ssl 下载）；'
                                '请先开启热点再启动抓包。'
                            : 'Traffic of devices using this phone\'s hotspot / USB / Bluetooth tethering also goes through the proxy, '
                                'no proxy setup needed on them. They must trust the ProxyPin CA for HTTPS (download from http://<hotspot IP>:${widget.proxyServer.port}/ssl). '
                                'Turn on the hotspot before starting.',
                        style: hint),
                    trailing: SwitchWidget(
                        value: configuration.rootCaptureTether,
                        scale: 0.8,
                        onChanged: (value) async {
                          setState(() => configuration.rootCaptureTether = value);
                          await configuration.flushConfig();
                          _dirty = true;
                        })),
              ])),
          const SizedBox(height: 12),
          Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              child: ListTile(
                  leading: const Icon(Icons.lan_outlined),
                  title: Text(isCN ? '原始抓包 (tcpdump)' : 'Raw Capture (tcpdump)'),
                  subtitle: Text(isCN ? '抓取全部协议，导出 pcap' : 'All protocols, export pcap', style: hint),
                  trailing: const Icon(Icons.keyboard_arrow_right),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RawCapturePage())))),
          const SizedBox(height: 16),
          Text(isCN ? '重定向端口' : 'Redirect Ports', style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(
              isCN
                  ? '逗号分隔，支持范围如 8000-8100；留空表示全部 TCP 端口（非 HTTP 协议的流量也会进入代理，可能导致部分应用异常）'
                  : 'Comma separated, ranges like 8000-8100 supported. Empty = all TCP ports (non-HTTP traffic will also enter the proxy and may break some apps)',
              style: hint),
          const SizedBox(height: 8),
          TextField(
              controller: _portsController,
              focusNode: _portsFocus,
              style: const TextStyle(fontSize: 14),
              onTapOutside: (_) => _portsFocus.unfocus(),
              onSubmitted: (_) => _savePorts(),
              decoration: const InputDecoration(
                  isDense: true, contentPadding: EdgeInsets.all(10), border: OutlineInputBorder())),
          Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: () {
                    _portsController.text = '80,443,8080,8443';
                    _savePorts();
                  },
                  child: Text(isCN ? '恢复默认' : 'Reset'))),
          const SizedBox(height: 8),
          Text(
              isCN
                  ? '提示：\n'
                      '· 仅捕获 TCP；UDP 不经过代理，开启「屏蔽 QUIC」可让 HTTP/3 回落到 TCP。\n'
                      '· 修改配置后若抓包正在运行会自动重新应用规则。\n'
                      '· App 被强杀时规则可能残留，下次启动 ProxyPin 会自动清理。'
                  : 'Notes:\n'
                      '· Only TCP is captured. Enable "Block QUIC" so HTTP/3 falls back to TCP.\n'
                      '· Rules are re-applied automatically when capture is running.\n'
                      '· If the app is force-killed, stale rules are cleaned on next launch.',
              style: hint),
        ]));
  }
}
