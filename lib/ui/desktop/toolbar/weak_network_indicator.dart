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

  @override
  Widget build(BuildContext context) {
    if (!_isActive) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 18),
      child: IconButton(
        tooltip: '${l10n.weakNetwork} · ${l10n.enable}',
        icon: Icon(Icons.speed, size: 21, color: theme.colorScheme.primary),
        onPressed: _openDialog,
      ),
    );
  }
}
