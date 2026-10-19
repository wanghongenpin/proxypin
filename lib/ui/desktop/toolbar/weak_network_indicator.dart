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
import 'package:proxypin/ui/desktop/setting/weak_network.dart';

/// 顶部工具栏「网络限制」指示器
///
/// - 弱网未启用（或没有生效规则）时完全不显示，避免占位打扰；
/// - 启用时显示 speed 图标 + 生效规则数徽标，tooltip 提示用户网络已被人为限速；
/// - 点击直接打开弱网设置弹窗。
///
/// @author wanghongen
class WeakNetworkIndicator extends StatefulWidget {
  const WeakNetworkIndicator({super.key});

  @override
  State<WeakNetworkIndicator> createState() => _WeakNetworkIndicatorState();
}

class _WeakNetworkIndicatorState extends State<WeakNetworkIndicator> {
  NetworkConditionManager? _manager;

  AppLocalizations get l10n => AppLocalizations.of(context)!;

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

  Future<void> _openDialog() async {
    final m = _manager;
    if (m == null) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WeakNetworkDialog(manager: m),
    );
    if (mounted) setState(() {});
  }

  /// 生效规则绑定的预设名（取第一条启用规则），用于徽章展示「弱网 3G」
  String? get _activeProfileName {
    final m = _manager;
    if (m == null) return null;
    final rule = m.rules.where((r) => r.enabled).firstOrNull;
    if (rule == null) return null;
    final profile = m.findProfile(rule.profileId) ?? m.defaultProfile;
    return profileDisplayName(l10n, profile);
  }

  @override
  Widget build(BuildContext context) {
    // 设计稿 .badge：浅色 #FFF3E8 底 + #B76E00 字；暗黑 16% --warn 底 + --warn 字
    if (!_isActive) return const SizedBox.shrink();
    final profileName = _activeProfileName;
    final theme = Theme.of(context);
    return Tooltip(
      message: '${l10n.weakNetwork} · ${l10n.enable}',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _openDialog,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: warnBadgeBg(theme), borderRadius: BorderRadius.circular(10)),
          child: Text(profileName == null ? l10n.weakNetwork : '${l10n.weakNetwork} $profileName',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: warnBadgeText(theme))),
        ),
      ),
    );
  }
}
