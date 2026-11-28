import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Android 网卡信息（原生 NetInterfaces 枚举，类型取自系统网络或按命名推断）
class NetInterfaceInfo {
  final String name;

  /// any / wifi / cellular / ethernet / vpn / tether / loopback / other
  final String type;
  final bool up;
  final List<String> addresses;

  /// 系统当前默认网络
  final bool isDefault;

  const NetInterfaceInfo(this.name, this.type,
      {this.up = true, this.addresses = const [], this.isDefault = false});

  static const any = NetInterfaceInfo('any', 'any');

  factory NetInterfaceInfo.fromMap(Map m) => NetInterfaceInfo(m['name'] ?? '', m['type'] ?? 'other',
      up: m['up'] == true,
      addresses: List<String>.from(m['addresses'] ?? const []),
      isDefault: m['isDefault'] == true);

  /// 已连接（启用且有地址）
  bool get connected => type == 'any' || (up && addresses.isNotEmpty);

  /// 本机流量可经由的出口网卡（Root 模式按网卡捕获可选）
  bool get isUplink => const {'wifi', 'cellular', 'ethernet', 'other'}.contains(type);

  String label(bool isCN) => switch (type) {
        'any' => isCN ? '全部网卡' : 'All interfaces',
        'wifi' => 'Wi-Fi',
        'cellular' => isCN ? '移动数据' : 'Mobile data',
        'ethernet' => isCN ? '以太网' : 'Ethernet',
        'vpn' => 'VPN',
        'tether' => isCN ? '热点/共享' : 'Hotspot/Tether',
        'loopback' => isCN ? '本机回环' : 'Loopback',
        _ => isCN ? '其它' : 'Other',
      };

  IconData get icon => switch (type) {
        'any' => Icons.all_inclusive,
        'wifi' => Icons.wifi,
        'cellular' => Icons.signal_cellular_alt,
        'ethernet' => Icons.settings_ethernet,
        'vpn' => Icons.vpn_lock_outlined,
        'tether' => Icons.wifi_tethering,
        'loopback' => Icons.loop,
        _ => Icons.lan_outlined,
      };

  static const MethodChannel _channel = MethodChannel('com.proxy/rawCapture');

  static Future<List<NetInterfaceInfo>> list() async {
    try {
      final result = await _channel.invokeListMethod<Map>('interfaces') ?? const [];
      final list = result.map(NetInterfaceInfo.fromMap).toList();
      return list.isEmpty ? [any] : list;
    } catch (_) {
      return [any];
    }
  }
}

/// 网卡选项行：图标 + 名称 + 类型 / 状态 / 地址
class NetInterfaceTile extends StatelessWidget {
  final NetInterfaceInfo info;
  final bool dense;

  const NetInterfaceTile(this.info, {super.key, this.dense = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCN = Localizations.localeOf(context).languageCode == 'zh';
    final muted = !info.connected;
    final color = muted ? theme.disabledColor : null;
    final sub = <String>[
      if (info.type != 'any') info.label(isCN),
      if (info.isDefault) isCN ? '默认网络' : 'default',
      if (info.type != 'any' && !info.connected) isCN ? '未连接' : 'down',
      if (info.addresses.isNotEmpty) info.addresses.first,
    ].join(' · ');
    return Row(children: [
      Icon(info.icon, size: 18, color: color ?? theme.colorScheme.primary),
      const SizedBox(width: 10),
      Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(info.type == 'any' ? '${info.label(isCN)} (any)' : info.name,
            style: TextStyle(fontSize: 14, color: color, fontFamily: info.type == 'any' ? null : 'monospace')),
        if (sub.isNotEmpty)
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: color ?? theme.colorScheme.onSurfaceVariant)),
      ])),
    ]);
  }
}
