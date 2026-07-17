/*
 * Copyright 2026 Hongen Wang
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * https://www.apache.org/licenses/LICENSE-2.0
 */
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/network_condition_manager.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';

/// Dropdown 下拉里"新增预设"项使用的哨兵值
const String _kNewProfileValue = '__new__';

/// URL 规则输入框的技术标签（非用户可见业务文案，保留原字符串）
const String _kUrlRulePatternLabel = 'URL Rule Pattern';

/// 内置预设 name 字段为 l10n key，这里集中做一次映射；
/// 自建预设直接返回其 name。
String _profileDisplayName(AppLocalizations l10n, NetworkConditionProfile p) {
  if (!p.isBuiltin) return p.name;
  switch (p.name) {
    case 'weakNetworkPresetOffline':
      return l10n.weakNetworkPresetOffline;
    case 'weakNetworkPreset2G':
      return "2G";
    case 'weakNetworkPreset3G':
      return "3G";
    case 'weakNetworkPreset4G':
      return "4G";
    case 'weakNetworkPreset5G':
      return '5G';
    case 'weakNetworkPresetWifi':
      return 'Wi-Fi';
    case 'weakNetworkPresetSlow':
      return l10n.weakNetworkPresetSlow;
    case 'weakNetworkPresetWeak':
      return l10n.weakNetworkPresetWeak;
  }
  return p.name;
}

/// 构建 profile 下拉里通用的“新增预设”菜单项
DropdownMenuItem<String> _buildAddProfileItem(BuildContext context, {double fontSize = 12}) {
  final theme = Theme.of(context);
  final l10n = AppLocalizations.of(context)!;
  return DropdownMenuItem(
    value: _kNewProfileValue,
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.add, size: 14, color: theme.colorScheme.primary),
      const SizedBox(width: 4),
      Text('${l10n.add} ${l10n.weakNetworkPreset}',
          style: TextStyle(fontSize: fontSize, color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
    ]),
  );
}

/// Network Throttling 设置面板（桌面）
class WeakNetworkDialog extends StatefulWidget {
  final NetworkConditionManager manager;

  const WeakNetworkDialog({super.key, required this.manager});

  @override
  State<WeakNetworkDialog> createState() => _WeakNetworkDialogState();
}

class _WeakNetworkDialogState extends State<WeakNetworkDialog> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;

  NetworkConditionManager get m => widget.manager;

  String _profileLabel(NetworkConditionProfile p) => _profileDisplayName(l10n, p);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      titlePadding: const EdgeInsets.only(left: 24, top: 16, right: 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      actionsPadding: const EdgeInsets.only(right: 24, bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(children: [
        Icon(Icons.speed, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(l10n.weakNetwork, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const Spacer(),
        const CloseButton(),
      ]),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _rulesHeader(theme),
            const SizedBox(height: 8),
            _rulesList(theme),
            const SizedBox(height: 5),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.close, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _rulesHeader(ThemeData theme) {
    return Row(children: [
      SwitchWidget(
          scale: 0.75,
          value: m.enabled,
          onChanged: (v) {
            setState(() => m.enabled = v);
            m.flushConfig();
          }),
      const SizedBox(width: 6),
      Text(l10n.enable, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      const SizedBox(width: 16),
      Container(height: 16, width: 1, color: theme.dividerColor.withValues(alpha: 0.5)),
      const SizedBox(width: 16),
      Text(l10n.weakNetworkRules, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      const SizedBox(width: 6),
      Text('${m.rules.length}',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: theme.colorScheme.primary)),
      const Spacer(),
      TextButton.icon(
        style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
        icon: const Icon(Icons.settings_outlined, size: 15),
        onPressed: _manageProfiles,
        label: Text('${l10n.edit} ${l10n.weakNetworkPreset}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ),
      const SizedBox(width: 4),
      TextButton.icon(
        style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
        icon: const Icon(Icons.add, size: 16),
        onPressed: _addRule,
        label: Text(l10n.add, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    ]);
  }

  Widget _rulesList(ThemeData theme) {
    if (m.rules.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3), width: 1),
        ),
        child: Column(children: [
          Icon(Icons.wifi_off_rounded, size: 40, color: theme.hintColor.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(l10n.emptyData, style: TextStyle(fontSize: 12, color: theme.hintColor, fontWeight: FontWeight.w500)),
        ]),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 340),
      child: SingleChildScrollView(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35), width: 1),
          ),
          child: Column(children: [
            for (int i = 0; i < m.rules.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 0.5, color: theme.dividerColor.withValues(alpha: 0.25)),
              _ruleTile(theme, i),
            ]
          ]),
        ),
      ),
    );
  }

  Widget _ruleTile(ThemeData theme, int index) {
    final r = m.rules[index];
    final p = m.findProfile(r.profileId) ?? m.defaultProfile;
    final isActive = r.enabled && m.enabled;

    return InkWell(
      onSecondaryTapDown: (d) => _showRuleMenu(d, index),
      hoverColor: theme.colorScheme.primary.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Container(
            width: 2,
            height: 28,
            decoration: BoxDecoration(
              color: isActive ? theme.colorScheme.primary : theme.hintColor.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          SwitchWidget(
              scale: 0.55,
              value: r.enabled,
              onChanged: (v) {
                setState(() => r.enabled = v);
                m.flushConfig();
              }),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => _editUrl(index),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    r.url.isEmpty ? '—' : r.url,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w500,
                      color: r.enabled ? theme.textTheme.bodyLarge?.color : theme.hintColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(_profileSummary(p),
                      style: TextStyle(fontSize: 11, color: theme.hintColor, letterSpacing: 0.1),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _profileDropdown(theme, r),
          const SizedBox(width: 8),
          IconButton(
              icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error.withValues(alpha: 0.8)),
              hoverColor: theme.colorScheme.error.withValues(alpha: 0.08),
              splashRadius: 16,
              onPressed: () => _confirmDeleteRule(index)),
        ]),
      ),
    );
  }

  Widget _profileDropdown(ThemeData theme, NetworkConditionRule r) {
    final items = <DropdownMenuItem<String>>[
      ...m.allProfiles.map((p) => DropdownMenuItem(value: p.id, child: Text(_profileLabel(p)))),
      _buildAddProfileItem(context),
    ];
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6), width: 0.8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: r.profileId,
          isDense: true,
          isExpanded: true,
          icon: Icon(Icons.unfold_more_rounded, size: 14, color: theme.hintColor),
          borderRadius: BorderRadius.circular(8),
          style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color, fontWeight: FontWeight.w500),
          items: items,
          onChanged: (v) async {
            if (v == null) return;
            if (v == _kNewProfileValue) {
              final created = await _createProfile();
              if (created != null) {
                setState(() => r.profileId = created.id);
                m.flushConfig();
              }
              return;
            }
            setState(() => r.profileId = v);
            m.flushConfig();
          },
        ),
      ),
    );
  }

  String _profileSummary(NetworkConditionProfile p) {
    final label = _profileLabel(p);
    if (p.offline) return '$label · Offline';
    final parts = <String>[label];
    if (p.responseLatencyMs > 0) parts.add('${p.responseLatencyMs}ms');
    if (p.requestLatencyMs > 0 && p.requestLatencyMs != p.responseLatencyMs) {
      parts.add('req ${p.requestLatencyMs}ms');
    }
    if (p.lossRate > 0) parts.add('${(p.lossRate * 100).toStringAsFixed(1)}% Loss');
    if (p.downloadKbps != null && p.downloadKbps! > 0) parts.add('↓ ${p.downloadKbps}k');
    if (p.uploadKbps != null && p.uploadKbps! > 0) parts.add('↑ ${p.uploadKbps}k');
    return parts.join('  |  ');
  }

  void _showRuleMenu(TapDownDetails details, int index) {
    final r = m.rules[index];
    showContextMenu(context, details.globalPosition, items: [
      PopupMenuItem(height: 35, child: Text(l10n.edit), onTap: () => _editUrl(index)),
      PopupMenuItem(
          height: 35,
          child: Text(r.enabled ? l10n.disabled : l10n.enable),
          onTap: () {
            setState(() => r.enabled = !r.enabled);
            m.flushConfig();
          }),
      const PopupMenuDivider(),
      PopupMenuItem(
          height: 35,
          child: Text(l10n.delete),
          onTap: () => _confirmDeleteRule(index)),
    ]);
  }

  Future<void> _addRule() async {
    final r = NetworkConditionRule(
      enabled: true,
      url: '',
      profileId: m.defaultProfile.id,
    );
    final saved = await showDialog<NetworkConditionRule>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RuleEditDialog(manager: m, rule: r, isNew: true, onCreateProfile: _createProfile));
    if (saved != null) {
      setState(() => m.rules.add(saved));
      m.flushConfig();
    }
  }

  Future<void> _editUrl(int index) async {
    final src = m.rules[index];
    final draft = NetworkConditionRule(enabled: src.enabled, url: src.url, profileId: src.profileId);
    final saved = await showDialog<NetworkConditionRule>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RuleEditDialog(manager: m, rule: draft, isNew: false, onCreateProfile: _createProfile));
    if (saved != null) {
      setState(() => m.rules[index] = saved);
      m.flushConfig();
    }
  }

  void _confirmDeleteRule(int index) {
    if (index < 0 || index >= m.rules.length) return;
    showConfirmDialog(context, content: l10n.confirmContent, onConfirm: () {
      setState(() => m.rules.removeAt(index));
      m.flushConfig();
    });
  }

  Future<NetworkConditionProfile?> _createProfile() async {
    final draft = NetworkConditionProfile(id: NetworkConditionManager.newCustomId(), name: '');
    final saved = await showDialog<NetworkConditionProfile>(
        context: context, barrierDismissible: false, builder: (_) => _ProfileEditDialog(profile: draft));
    if (saved != null) {
      await m.upsertCustomProfile(saved);
      setState(() {});
      return saved;
    }
    return null;
  }

  // 打开全局自定义预设管理器
  Future<void> _manageProfiles() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ManageProfilesDialog(
        manager: m,
        profileLabel: _profileLabel,
        profileSummary: _profileSummary,
      ),
    );
    setState(() {}); // 弹窗关闭后，同步刷新主面板的数据绑定状态
  }
}

/// URL 规则编辑弹窗
class _RuleEditDialog extends StatefulWidget {
  final NetworkConditionManager manager;
  final NetworkConditionRule rule;
  final bool isNew;
  final Future<NetworkConditionProfile?> Function() onCreateProfile;

  const _RuleEditDialog({
    required this.manager,
    required this.rule,
    required this.isNew,
    required this.onCreateProfile,
  });

  @override
  State<_RuleEditDialog> createState() => _RuleEditDialogState();
}

class _RuleEditDialogState extends State<_RuleEditDialog> {
  final formKey = GlobalKey<FormState>();
  late TextEditingController _urlCtrl;
  late bool _enabled;
  late String _profileId;

  NetworkConditionManager get m => widget.manager;

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.rule.url);
    _enabled = widget.rule.enabled;
    _profileId = widget.rule.profileId;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  String _profileLabel(NetworkConditionProfile p) => _profileDisplayName(l10n, p);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = m.findProfile(_profileId) ?? m.defaultProfile;
    return AlertDialog(
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(children: [
        Icon(widget.isNew ? Icons.add_link_rounded : Icons.edit_note_rounded,
            size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text('${widget.isNew ? l10n.add : l10n.edit} ${l10n.weakNetworkRules}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const Spacer(),
        SwitchWidget(scale: 0.65, value: _enabled, onChanged: (v) => setState(() => _enabled = v)),
      ]),
      content: SizedBox(
        width: 480,
        child: Form(
          key: formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextFormField(
              controller: _urlCtrl,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                labelText: _kUrlRulePatternLabel,
                labelStyle: TextStyle(fontSize: 12),
                hintText: 'https://example.com/api/*',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? l10n.cannotBeEmpty : null,
            ),
            const SizedBox(height: 18),
            Text(l10n.weakNetworkPreset,
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant, width: 0.8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _profileId,
                  isExpanded: true,
                  isDense: true,
                  icon: Icon(Icons.unfold_more_rounded, size: 16, color: theme.hintColor),
                  borderRadius: BorderRadius.circular(10),
                  style: TextStyle(fontSize: 13, color: theme.textTheme.bodyMedium?.color),
                  items: [
                    ...m.allProfiles.map((p) => DropdownMenuItem(value: p.id, child: Text(_profileLabel(p)))),
                    _buildAddProfileItem(context, fontSize: 13),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    if (v == _kNewProfileValue) {
                      final created = await widget.onCreateProfile();
                      if (created != null) setState(() => _profileId = created.id);
                      return;
                    }
                    setState(() => _profileId = v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            _profilePreview(theme, selected),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel, style: TextStyle(color: theme.hintColor))),
        ElevatedButton(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final r = widget.rule;
              r.enabled = _enabled;
              r.url = _urlCtrl.text.trim();
              r.profileId = _profileId;
              r.resetCache();
              Navigator.of(context).pop(r);
            },
            child: Text(l10n.save)),
      ],
    );
  }

  Widget _profilePreview(ThemeData theme, NetworkConditionProfile p) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _previewCard(theme, p, isUpload: false)),
        const SizedBox(width: 12),
        Expanded(child: _previewCard(theme, p, isUpload: true)),
      ]),
    );
  }

  Widget _previewCard(ThemeData theme, NetworkConditionProfile p, {required bool isUpload}) {
    final title = isUpload ? l10n.weakNetworkUpload : l10n.weakNetworkDownload;
    final bw = isUpload ? p.uploadKbps : p.downloadKbps;
    final lat = isUpload ? p.requestLatencyMs : p.responseLatencyMs;

    final cardAccentColor = isUpload ? Colors.blue : Colors.teal;

    String fmtBw() {
      if (p.offline) return '—';
      if (bw == null || bw <= 0) return '∞';
      if (bw >= 1000) return '${(bw / 1000).toStringAsFixed(bw % 1000 == 0 ? 0 : 1)} Mbps';
      return '$bw kbps';
    }

    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: theme.hintColor)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cardAccentColor.withValues(alpha: 0.25), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isUpload ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 16,
                color: cardAccentColor,
              ),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cardAccentColor)),
            ],
          ),
          const SizedBox(height: 10),
          line(l10n.weakNetworkBandwidth, fmtBw()),
          Divider(height: 6, thickness: 0.5, color: theme.dividerColor.withValues(alpha: 0.15)),
          line(l10n.weakNetworkLatency, lat <= 0 ? '0 ms' : '$lat ms'),
          Divider(height: 6, thickness: 0.5, color: theme.dividerColor.withValues(alpha: 0.15)),
          line(l10n.weakNetworkLossRate, '${(p.lossRate * 100).toStringAsFixed(1)}%'),
        ],
      ),
    );
  }
}

/// 自建预设编辑对话框
class _ProfileEditDialog extends StatefulWidget {
  final NetworkConditionProfile profile;

  const _ProfileEditDialog({required this.profile});

  @override
  State<_ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<_ProfileEditDialog> {
  final formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _upBwCtrl;
  late TextEditingController _upLatCtrl;
  late TextEditingController _dnBwCtrl;
  late TextEditingController _dnLatCtrl;
  late TextEditingController _lossCtrl;

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nameCtrl = TextEditingController(text: p.name);
    _upBwCtrl = TextEditingController(text: p.uploadKbps?.toString() ?? '');
    _upLatCtrl = TextEditingController(text: p.requestLatencyMs == 0 ? '' : p.requestLatencyMs.toString());
    _dnBwCtrl = TextEditingController(text: p.downloadKbps?.toString() ?? '');
    _dnLatCtrl = TextEditingController(text: p.responseLatencyMs == 0 ? '' : p.responseLatencyMs.toString());
    _lossCtrl = TextEditingController(text: p.lossRate == 0 ? '' : (p.lossRate * 100).toStringAsFixed(1));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _upBwCtrl.dispose();
    _upLatCtrl.dispose();
    _dnBwCtrl.dispose();
    _dnLatCtrl.dispose();
    _lossCtrl.dispose();
    super.dispose();
  }

  int? _parseInt(String t) {
    final s = t.trim();
    return s.isEmpty ? null : int.tryParse(s);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Icon(Icons.tune_rounded, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(widget.profile.name.isEmpty ? '${l10n.add} ${l10n.weakNetworkPreset}' : l10n.edit,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: '${l10n.weakNetworkPreset} ${l10n.name}',
                labelStyle: const TextStyle(fontSize: 12),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? l10n.cannotBeEmpty : null,
            ),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _sectionCard(theme, isUpload: false)),
              const SizedBox(width: 12),
              Expanded(child: _sectionCard(theme, isUpload: true)),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5), width: 0.8),
              ),
              child: Row(children: [
                Icon(Icons.broken_image_outlined, size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Text(l10n.weakNetworkLossRate, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const Spacer(),
                SizedBox(width: 140, child: _num('', _lossCtrl, '%', integer: false)),
              ]),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel, style: TextStyle(color: theme.hintColor))),
        ElevatedButton(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final p = widget.profile;
              p.name = _nameCtrl.text.trim();
              p.offline = false;
              p.uploadKbps = _parseInt(_upBwCtrl.text);
              p.requestLatencyMs = _parseInt(_upLatCtrl.text) ?? 0;
              p.downloadKbps = _parseInt(_dnBwCtrl.text);
              p.responseLatencyMs = _parseInt(_dnLatCtrl.text) ?? 0;
              final loss = double.tryParse(_lossCtrl.text.trim()) ?? 0;
              p.lossRate = (loss / 100).clamp(0.0, 1.0);
              Navigator.of(context).pop(p);
            },
            child: Text(l10n.save)),
      ],
    );
  }

  Widget _sectionCard(ThemeData theme, {required bool isUpload}) {
    final title = isUpload ? l10n.weakNetworkUpload : l10n.weakNetworkDownload;
    final bwCtrl = isUpload ? _upBwCtrl : _dnBwCtrl;
    final latCtrl = isUpload ? _upLatCtrl : _dnLatCtrl;
    final accentColor = isUpload ? Colors.blue : Colors.teal;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: Row(
          children: [
            Icon(isUpload ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14, color: accentColor),
            const SizedBox(width: 4),
            Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accentColor)),
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6), width: 0.8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _num(l10n.weakNetworkBandwidth, bwCtrl, 'kbps', integer: true),
          const SizedBox(height: 10),
          _num(l10n.weakNetworkLatency, latCtrl, 'ms', integer: true),
        ]),
      ),
    ]);
  }

  Widget _num(String label, TextEditingController ctrl, String suffix, {required bool integer}) {
    final fmt = <TextInputFormatter>[
      LengthLimitingTextInputFormatter(7),
      FilteringTextInputFormatter.allow(RegExp(integer ? r'[0-9]' : r'[0-9.]')),
    ];
    return TextField(
      controller: ctrl,
      inputFormatters: fmt,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
      decoration: InputDecoration(
        labelText: label.isEmpty ? null : label,
        labelStyle: const TextStyle(fontSize: 11),
        hintText: '0',
        suffixText: suffix,
        suffixStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(6))),
      ),
    );
  }
}

/// 核心新增：专门用于编辑/删除自定义预设的管理面板
class _ManageProfilesDialog extends StatefulWidget {
  final NetworkConditionManager manager;
  final String Function(NetworkConditionProfile) profileLabel;
  final String Function(NetworkConditionProfile) profileSummary;

  const _ManageProfilesDialog({
    required this.manager,
    required this.profileLabel,
    required this.profileSummary,
  });

  @override
  State<_ManageProfilesDialog> createState() => _ManageProfilesDialogState();
}

class _ManageProfilesDialogState extends State<_ManageProfilesDialog> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;

  NetworkConditionManager get m => widget.manager;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 过滤出所有由用户自建的非系统预设
    final customProfiles = m.allProfiles.where((p) => !p.isBuiltin).toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.only(left: 20, top: 14, right: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      actionsPadding: const EdgeInsets.only(right: 20, bottom: 12),
      title: Row(children: [
        Icon(Icons.tune_rounded, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text('${l10n.edit} ${l10n.weakNetworkPreset}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const Spacer(),
        const CloseButton(),
      ]),
      content: SizedBox(
        width: 460,
        child: customProfiles.isEmpty
            ? Container(
          padding: const EdgeInsets.symmetric(vertical: 40),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.layers_clear_outlined, size: 36, color: theme.hintColor.withValues(alpha: 0.35)),
              const SizedBox(height: 10),
              Text(l10n.emptyData,
                  style: TextStyle(fontSize: 12, color: theme.hintColor, fontWeight: FontWeight.w500)),
            ],
          ),
        )
            : ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: SingleChildScrollView(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4), width: 0.8),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < customProfiles.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 0.5, color: theme.dividerColor.withValues(alpha: 0.2)),
                    _profileRow(theme, customProfiles[i]),
                  ]
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }

  Widget _profileRow(ThemeData theme, NetworkConditionProfile p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.profileLabel(p), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 3),
            Text(widget.profileSummary(p),
                style: TextStyle(fontSize: 11, color: theme.hintColor, fontFamily: 'monospace')),
          ]),
        ),
        // 编辑单条自定义预设
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 16),
          hoverColor: theme.colorScheme.primary.withValues(alpha: 0.08),
          splashRadius: 16,
          onPressed: () async {
            final saved = await showDialog<NetworkConditionProfile>(
              context: context,
              barrierDismissible: false,
              builder: (_) => _ProfileEditDialog(profile: p),
            );
            if (saved != null) {
              await m.upsertCustomProfile(saved);
              setState(() {}); // 刷新当前列表
            }
          },
        ),
        const SizedBox(width: 4),
        // 删除单条自定义预设
        IconButton(
          icon: Icon(Icons.delete_outline, size: 16, color: theme.colorScheme.error.withValues(alpha: 0.8)),
          hoverColor: theme.colorScheme.error.withValues(alpha: 0.08),
          splashRadius: 16,
          onPressed: () {
            showConfirmDialog(context, content: l10n.confirmContent, onConfirm: () async {
              // manager 内部已负责把引用该 profile 的规则回退到默认预设并 flush
              await m.deleteCustomProfile(p.id);
              if (mounted) setState(() {});
            });
          },
        ),
      ]),
    );
  }
}
