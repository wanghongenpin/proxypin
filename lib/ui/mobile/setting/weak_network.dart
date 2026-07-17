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

/// 构建 profile 下拉里通用的"新增预设"菜单项
DropdownMenuItem<String> _buildAddProfileItem(BuildContext context) {
  final theme = Theme.of(context);
  final l10n = AppLocalizations.of(context)!;
  return DropdownMenuItem(
    value: _kNewProfileValue,
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.add, size: 16, color: theme.colorScheme.primary),
      const SizedBox(width: 6),
      Text('${l10n.add} ${l10n.weakNetworkPreset}',
          style: TextStyle(fontSize: 14, color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
    ]),
  );
}

/// Network Throttling 设置页面（手机端入口）
class MobileWeakNetwork extends StatefulWidget {
  final NetworkConditionManager manager;

  const MobileWeakNetwork({super.key, required this.manager});

  @override
  State<MobileWeakNetwork> createState() => _MobileWeakNetworkState();
}

class _MobileWeakNetworkState extends State<MobileWeakNetwork> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;

  NetworkConditionManager get m => widget.manager;

  String _profileLabel(NetworkConditionProfile p) => _profileDisplayName(l10n, p);

  String _profileSummary(NetworkConditionProfile p) {
    final label = _profileLabel(p);
    if (p.offline) return '$label · Offline';
    final parts = <String>[];
    if (p.responseLatencyMs > 0) parts.add('${p.responseLatencyMs}ms');
    if (p.requestLatencyMs > 0 && p.requestLatencyMs != p.responseLatencyMs) {
      parts.add('req ${p.requestLatencyMs}ms');
    }
    if (p.lossRate > 0) parts.add('${(p.lossRate * 100).toStringAsFixed(1)}% Loss');
    if (p.downloadKbps != null && p.downloadKbps! > 0) parts.add('↓ ${p.downloadKbps}k');
    if (p.uploadKbps != null && p.uploadKbps! > 0) parts.add('↑ ${p.uploadKbps}k');
    return parts.isEmpty ? label : '$label  |  ${parts.join('  |  ')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.weakNetwork, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        actions: [
          // 预设管理入口
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: '${l10n.edit} ${l10n.weakNetworkPreset}',
            onPressed: _manageProfiles,
          ),
          // 全局弱网开关
          SwitchWidget(
            scale: 0.8,
            value: m.enabled,
            onChanged: (v) {
              setState(() => m.enabled = v);
              m.flushConfig();
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _buildRulesList(theme),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRule,
        icon: const Icon(Icons.add),
        label: Text(l10n.add),
      ),
    );
  }

  Widget _buildRulesList(ThemeData theme) {
    if (m.rules.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 64, color: theme.hintColor.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(l10n.emptyData,
                style: TextStyle(fontSize: 14, color: theme.hintColor, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: m.rules.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final r = m.rules[index];
        final p = m.findProfile(r.profileId) ?? m.defaultProfile;
        final isActive = r.enabled && m.enabled;

        return Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isActive
                  ? theme.colorScheme.primary.withValues(alpha: 0.4)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _editUrl(index),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  SwitchWidget(
                    scale: 0.7,
                    value: r.enabled,
                    onChanged: (v) {
                      setState(() => r.enabled = v);
                      m.flushConfig();
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.url.isEmpty ? '—' : r.url,
                          style: const TextStyle(fontSize: 14, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _profileSummary(p),
                          style: TextStyle(fontSize: 12, color: theme.hintColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error.withValues(alpha: 0.8)),
                    onPressed: () => _confirmDeleteRule(index),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _confirmDeleteRule(int index) {
    if (index < 0 || index >= m.rules.length) return;
    showConfirmDialog(context, content: l10n.confirmContent, onConfirm: () {
      if (!mounted) return;
      setState(() => m.rules.removeAt(index));
      m.flushConfig();
    });
  }

  Future<void> _addRule() async {
    final r = NetworkConditionRule(enabled: true, url: '', profileId: m.defaultProfile.id);
    final saved = await Navigator.of(context).push<NetworkConditionRule>(
      MaterialPageRoute(
          builder: (_) => _MobileRuleEditPage(manager: m, rule: r, isNew: true, onCreateProfile: _createProfile)),
    );
    if (saved != null) {
      setState(() => m.rules.add(saved));
      m.flushConfig();
    }
  }

  Future<void> _editUrl(int index) async {
    final src = m.rules[index];
    final draft = NetworkConditionRule(enabled: src.enabled, url: src.url, profileId: src.profileId);
    final saved = await Navigator.of(context).push<NetworkConditionRule>(
      MaterialPageRoute(
          builder: (_) => _MobileRuleEditPage(manager: m, rule: draft, isNew: false, onCreateProfile: _createProfile)),
    );
    if (saved != null) {
      setState(() => m.rules[index] = saved);
      m.flushConfig();
    }
  }

  Future<NetworkConditionProfile?> _createProfile() async {
    final draft = NetworkConditionProfile(id: NetworkConditionManager.newCustomId(), name: '');
    final saved = await Navigator.of(context).push<NetworkConditionProfile>(
      MaterialPageRoute(builder: (_) => _MobileProfileEditPage(profile: draft, isNew: true)),
    );
    if (saved != null) {
      await m.upsertCustomProfile(saved);
      setState(() {});
      return saved;
    }
    return null;
  }

  Future<void> _manageProfiles() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MobileManageProfilesPage(
          manager: m,
          profileLabel: _profileLabel,
          profileSummary: _profileSummary,
        ),
      ),
    );
    setState(() {}); // 从管理器返回后同步刷新主页面规则绑定状态
  }
}

/// 移动端：规则编辑全屏页面
class _MobileRuleEditPage extends StatefulWidget {
  final NetworkConditionManager manager;
  final NetworkConditionRule rule;
  final bool isNew;
  final Future<NetworkConditionProfile?> Function() onCreateProfile;

  const _MobileRuleEditPage({
    required this.manager,
    required this.rule,
    required this.isNew,
    required this.onCreateProfile,
  });

  @override
  State<_MobileRuleEditPage> createState() => _MobileRuleEditPageState();
}

class _MobileRuleEditPageState extends State<_MobileRuleEditPage> {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = m.findProfile(_profileId) ?? m.defaultProfile;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.isNew ? l10n.add : l10n.edit} ${l10n.weakNetworkRules}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          SwitchWidget(scale: 0.75, value: _enabled, onChanged: (v) => setState(() => _enabled = v)),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextFormField(
              controller: _urlCtrl,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              decoration: InputDecoration(
                labelText: _kUrlRulePatternLabel,
                hintText: 'https://example.com/api/*',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? l10n.cannotBeEmpty : null,
            ),
            const SizedBox(height: 24),
            Text(l10n.weakNetworkPreset,
                style:
                    TextStyle(fontSize: 14, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.outlineVariant, width: 0.8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _profileId,
                  isExpanded: true,
                  icon: Icon(Icons.unfold_more_rounded, size: 18, color: theme.hintColor),
                  borderRadius: BorderRadius.circular(12),
                  items: [
                    ...m.allProfiles.map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(_profileDisplayName(l10n, p), style: const TextStyle(fontSize: 14)),
                        )),
                    _buildAddProfileItem(context),
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
            const SizedBox(height: 24),
            _buildProfilePreview(theme, selected),
          ]),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            child: Text(l10n.save, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }

  Widget _buildProfilePreview(ThemeData theme, NetworkConditionProfile p) {
    return Column(
      children: [
        _previewCard(theme, p, isUpload: false),
        const SizedBox(height: 12),
        _previewCard(theme, p, isUpload: true),
      ],
    );
  }

  Widget _previewCard(ThemeData theme, NetworkConditionProfile p, {required bool isUpload}) {
    final title = isUpload ? l10n.weakNetworkUpload : l10n.weakNetworkDownload;
    final bw = isUpload ? p.uploadKbps : p.downloadKbps;
    final lat = isUpload ? p.requestLatencyMs : p.responseLatencyMs;
    final accentColor = isUpload ? Colors.blue : Colors.teal;

    String fmtBw() {
      if (p.offline) return '—';
      if (bw == null || bw <= 0) return '∞';
      if (bw >= 1000) return '${(bw / 1000).toStringAsFixed(bw % 1000 == 0 ? 0 : 1)} Mbps';
      return '$bw kbps';
    }

    Widget row(String label, String val) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: theme.hintColor)),
              Text(val, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.2), width: 1.2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(isUpload ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  size: 16, color: accentColor),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accentColor)),
            ],
          ),
          const SizedBox(height: 10),
          row(l10n.weakNetworkBandwidth, fmtBw()),
          Divider(height: 8, thickness: 0.5, color: theme.dividerColor.withValues(alpha: 0.15)),
          row(l10n.weakNetworkLatency, lat <= 0 ? '0 ms' : '$lat ms'),
          Divider(height: 8, thickness: 0.5, color: theme.dividerColor.withValues(alpha: 0.15)),
          row(l10n.weakNetworkLossRate, '${(p.lossRate * 100).toStringAsFixed(1)}%'),
        ],
      ),
    );
  }
}

/// 移动端：预设参数编辑全屏页面
class _MobileProfileEditPage extends StatefulWidget {
  final NetworkConditionProfile profile;
  final bool isNew;

  const _MobileProfileEditPage({required this.profile, required this.isNew});

  @override
  State<_MobileProfileEditPage> createState() => _MobileProfileEditPageState();
}

class _MobileProfileEditPageState extends State<_MobileProfileEditPage> {
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? '${l10n.add} ${l10n.weakNetworkPreset}' : l10n.edit,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: '${l10n.weakNetworkPreset} ${l10n.name}',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? l10n.cannotBeEmpty : null,
              ),
              const SizedBox(height: 20),
              _buildSectionCard(theme, isUpload: false),
              const SizedBox(height: 16),
              _buildSectionCard(theme, isUpload: true),
              const SizedBox(height: 16),
              // 丢包率
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.broken_image_outlined, size: 18, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Text(l10n.weakNetworkLossRate,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    SizedBox(width: 120, child: _buildNumField('', _lossCtrl, '%', isInteger: false)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            child: Text(l10n.save, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard(ThemeData theme, {required bool isUpload}) {
    final title = isUpload ? l10n.weakNetworkUpload : l10n.weakNetworkDownload;
    final bwCtrl = isUpload ? _upBwCtrl : _dnBwCtrl;
    final latCtrl = isUpload ? _upLatCtrl : _dnLatCtrl;
    final accentColor = isUpload ? Colors.blue : Colors.teal;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isUpload ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  size: 16, color: accentColor),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accentColor)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildNumField(l10n.weakNetworkBandwidth, bwCtrl, 'kbps', isInteger: true)),
              const SizedBox(width: 12),
              Expanded(child: _buildNumField(l10n.weakNetworkLatency, latCtrl, 'ms', isInteger: true)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNumField(String label, TextEditingController ctrl, String suffix, {required bool isInteger}) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        LengthLimitingTextInputFormatter(7),
        FilteringTextInputFormatter.allow(RegExp(isInteger ? r'[0-9]' : r'[0-9.]')),
      ],
      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
      decoration: InputDecoration(
        labelText: label.isEmpty ? null : label,
        labelStyle: const TextStyle(fontSize: 11),
        hintText: '0',
        suffixText: suffix,
        suffixStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

/// 移动端：管理/编辑/删除自定义预设的全屏设置页面
class _MobileManageProfilesPage extends StatefulWidget {
  final NetworkConditionManager manager;
  final String Function(NetworkConditionProfile) profileLabel;
  final String Function(NetworkConditionProfile) profileSummary;

  const _MobileManageProfilesPage({
    required this.manager,
    required this.profileLabel,
    required this.profileSummary,
  });

  @override
  State<_MobileManageProfilesPage> createState() => _MobileManageProfilesPageState();
}

class _MobileManageProfilesPageState extends State<_MobileManageProfilesPage> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;

  NetworkConditionManager get m => widget.manager;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 只过滤出自建的预设
    final customProfiles = m.allProfiles.where((p) => !p.isBuiltin).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('${l10n.edit} ${l10n.weakNetworkPreset}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: customProfiles.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.layers_clear_outlined, size: 48, color: theme.hintColor.withValues(alpha: 0.4)),
                  const SizedBox(height: 12),
                  Text(l10n.emptyData,
                      style: TextStyle(fontSize: 14, color: theme.hintColor, fontWeight: FontWeight.w500)),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: customProfiles.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final p = customProfiles[index];
                return Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    title: Text(widget.profileLabel(p),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        widget.profileSummary(p),
                        style: TextStyle(fontSize: 11, color: theme.hintColor, fontFamily: 'monospace'),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () async {
                            final saved = await Navigator.of(context).push<NetworkConditionProfile>(
                              MaterialPageRoute(builder: (_) => _MobileProfileEditPage(profile: p, isNew: false)),
                            );
                            if (saved != null) {
                              await m.upsertCustomProfile(saved);
                              setState(() {});
                            }
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                          onPressed: () {
                            showConfirmDialog(context, content: l10n.confirmContent, onConfirm: () async {
                              await m.deleteCustomProfile(p.id);
                              if (mounted) setState(() {});
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        mini: true,
        onPressed: () async {
          final draft = NetworkConditionProfile(id: NetworkConditionManager.newCustomId(), name: '');
          final saved = await Navigator.of(context).push<NetworkConditionProfile>(
            MaterialPageRoute(builder: (_) => _MobileProfileEditPage(profile: draft, isNew: true)),
          );
          if (saved != null) {
            await m.upsertCustomProfile(saved);
            setState(() {});
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
