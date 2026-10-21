/*
 * Copyright 2026 Hongen Wang
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 */

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/network_condition_manager.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/mobile/setting/weak_network.dart';

/// 手机端「网络限制」入口 ListTile
///
/// 用于抽屉菜单和底部导航配置页共用；启用时在标题旁展示一个小圆点，
/// 提醒用户当前网络已被人为限速，避免"网络怎么变慢了"的困惑。
///
/// [color] 图标颜色（配置页用主题色，抽屉不传保持默认灰）；
/// [leading] 自定义前导图标（配置页传描边 SVG，抽屉不传用默认 Material 图标）；
/// [titleStyle] 标题样式；[contentPadding] 行内边距；
/// [trailing] 抽屉里通常不带箭头，配置页需要 chevron，外部传入即可；
/// [showStatus] 行尾展示状态摘要（未开启 / 启用中 · N 条规则，对齐桌面流量控制页），
/// 开启后不再显示标题旁的小圆点。
class WeakNetworkMenuTile extends StatefulWidget {
  final Color? color;
  final Widget? leading;
  final TextStyle? titleStyle;
  final EdgeInsetsGeometry? contentPadding;
  final Widget? trailing;
  final bool showStatus;

  const WeakNetworkMenuTile(
      {super.key,
      this.color,
      this.leading,
      this.titleStyle,
      this.contentPadding,
      this.trailing,
      this.showStatus = false});

  @override
  State<WeakNetworkMenuTile> createState() => _WeakNetworkMenuTileState();
}

class _WeakNetworkMenuTileState extends State<WeakNetworkMenuTile> {
  NetworkConditionManager? _manager;

  @override
  void initState() {
    super.initState();
    NetworkConditionManager.instance.then((m) {
      if (!mounted) return;
      setState(() => _manager = m);
      m.addListener(_onChanged);
    });
  }

  @override
  void dispose() {
    _manager?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  int get _activeRuleCount => _manager?.rules.where((r) => r.enabled).length ?? 0;

  bool get _isActive => (_manager?.enabled ?? false) && _activeRuleCount > 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    // 生效时给标题带一个圆点徽标，视觉上等同于桌面端工具栏指示器；
    // 行尾已展示状态摘要时不再重复圆点
    final showDot = _isActive && !widget.showStatus;
    final title = showDot
        ? Row(mainAxisSize: MainAxisSize.min, children: [
            Text(l10n.weakNetwork, style: widget.titleStyle),
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
          ])
        : Text(l10n.weakNetwork, style: widget.titleStyle);

    // 行尾状态摘要：只在生效时展示绿色规则数；关闭是弱网的常态，不显示「未开启」
    Widget? trailing = widget.trailing;
    if (widget.showStatus && _manager != null) {
      final on = _manager!.enabled;
      final String? status = on && _activeRuleCount > 0 ? l10n.rulesCount(_activeRuleCount) : null;
      if (status != null) {
        trailing = Row(mainAxisSize: MainAxisSize.min, children: [
          Text(status,
              style: TextStyle(fontSize: 12, color: on ? okColor(theme) : theme.colorScheme.onSurfaceVariant)),
          if (widget.trailing != null) widget.trailing!,
        ]);
      }
    }

    return ListTile(
      title: title,
      contentPadding: widget.contentPadding,
      leading: widget.leading ?? Icon(Icons.speed, color: widget.color),
      trailing: trailing,
      onTap: () async {
        final m = _manager ?? await NetworkConditionManager.instance;
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => MobileWeakNetwork(manager: m)),
          );
        }
      },
    );
  }
}
