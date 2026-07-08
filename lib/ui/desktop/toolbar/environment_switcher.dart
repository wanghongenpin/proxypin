/*
 * Copyright 2026 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 */

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/environment_manager.dart';
import 'package:proxypin/utils/flutter_compat.dart';
import 'package:proxypin/ui/desktop/setting/environment.dart';

/// 顶部工具栏的环境切换器
///
/// - 显示当前激活环境名(未激活时显示 "No Environment")
/// - 点击展开菜单:命名环境列表 + "管理环境…" 入口
///
/// @author wanghongen
class EnvironmentSwitcher extends StatefulWidget {
  const EnvironmentSwitcher({super.key});

  @override
  State<EnvironmentSwitcher> createState() => _EnvironmentSwitcherState();
}

class _EnvironmentSwitcherState extends State<EnvironmentSwitcher> {
  EnvironmentManager? manager;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    EnvironmentManager.instance.then((m) {
      if (!mounted) return;
      setState(() => manager = m);
      m.addListener(_onChanged);
    });
  }

  @override
  void dispose() {
    manager?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openManage() async {
    await showEnvironmentDialog(context);
    if (mounted) setState(() {});
  }

  PopupMenuItem<String> _checkedItem({
    required String value,
    required bool checked,
    required String label,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        SizedBox(
          width: 20,
          child: checked ? const Icon(Icons.check, size: 16) : null,
        ),
        const SizedBox(width: 6),
        Flexible(child: Text(label, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = manager;
    final label = m?.active?.name ?? localizations.envNone;

    return PopupMenuButton<String>(
      tooltip: localizations.environment,
      position: PopupMenuPosition.under,
      onSelected: (value) async {
        if (value == '__manage__') {
          await _openManage();
          return;
        }
        if (value == '__none__') {
          m?.setActive(null);
        } else {
          m?.setActive(value);
        }
        await m?.flushConfig();
      },
      itemBuilder: (ctx) {
        final items = <PopupMenuEntry<String>>[];
        items.add(_checkedItem(
          value: '__none__',
          checked: m?.activeId == null,
          label: localizations.envNone,
        ));
        final named = m?.namedEnvironments ?? const <Environment>[];
        if (named.isNotEmpty) {
          items.add(const PopupMenuDivider(height: 5));
          for (final e in named) {
            items.add(_checkedItem(
              value: e.id,
              checked: m?.activeId == e.id,
              label: e.name,
            ));
          }
        }
        items.add(const PopupMenuDivider(height: 5));
        items.add(PopupMenuItem<String>(
          value: '__manage__',
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            const Icon(Icons.tune, size: 16),
            const SizedBox(width: 8),
            Text(localizations.envManage, style: const TextStyle(fontSize: 12)),
          ]),
        ));
        return items;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(4),
        ),
        constraints: const BoxConstraints(maxWidth: 160),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            m?.active != null ? Icons.public : Icons.public_off,
            size: 16,
            color: Colors.grey.shade600,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey.shade600),
        ]),
      ),
    );
  }
}
