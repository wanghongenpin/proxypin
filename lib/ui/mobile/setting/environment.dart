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
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/environment_manager.dart';
import 'package:proxypin/network/util/random.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:url_launcher/url_launcher.dart';

/// 环境变量管理页(移动端)
///
/// - AppBar 显示"环境变量"
/// - 顶部下拉:激活环境(None / Global-only / 各命名环境)
/// - 中部 Tab:每个环境一个 Tab(含 Global + 添加)
/// - 下方:所选环境的变量表(可编辑/启用/删除)
///
/// @author wanghongen
class MobileEnvironmentPage extends StatefulWidget {
  const MobileEnvironmentPage({super.key});

  @override
  State<MobileEnvironmentPage> createState() => _MobileEnvironmentPageState();
}

class _MobileEnvironmentPageState extends State<MobileEnvironmentPage> {
  EnvironmentManager? manager;

  /// 工作副本 —— 所有编辑都作用在这上面,保存时才写回单例
  List<Environment>? _draft;

  /// 激活环境 id 的工作副本(null = 无环境)
  String? _draftActiveId;

  /// 当前正在编辑的环境 id(可能是 global)
  String? currentId;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  /// 词语拼接:CJK/泰文不加空格,其他语言用空格
  String _join(String a, String b) {
    final code = localizations.localeName;
    final noSpace = code.startsWith('zh') || code == 'th' || code == 'ja' || code == 'ko';
    return noSpace ? '$a$b' : '$a $b';
  }

  @override
  void initState() {
    super.initState();
    EnvironmentManager.instance.then((m) {
      if (!mounted) return;
      setState(() {
        manager = m;
        _draft = m.environments.map((e) => e.copy()).toList();
        _draftActiveId = m.activeId;
        currentId = _draftGlobal.id;
      });
    });
  }

  Environment get _draftGlobal =>
      _draft!.firstWhere((e) => e.isGlobal, orElse: () => _draft!.first);

  List<Environment> get _draftNamed => _draft!.where((e) => !e.isGlobal).toList();

  Environment? get current {
    final d = _draft;
    if (d == null) return null;
    return d.firstWhere((e) => e.id == currentId, orElse: () => _draftGlobal);
  }

  Future<void> _save() async {
    final m = manager;
    final d = _draft;
    if (m == null || d == null) return;
    m.applyFrom(d);
    m.setActive(_draftActiveId);
    await m.flushConfig();
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<String?> _promptText({required String title, required String hint, String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 15)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint, isDense: true, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(localizations.cancel)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: Text(localizations.confirm)),
        ],
      ),
    );
  }

  void _addEnvironment() async {
    final name = await _promptText(
        title: _join(localizations.add, localizations.environment), hint: localizations.name);
    final m = manager;
    if (name == null || name.trim().isEmpty || m == null || _draft == null) return;
    final env = Environment(id: RandomUtil.randomString(8), name: name.trim());
    // 实时落库
    m.upsertEnvironment(env);
    await m.flushConfig();
    if (!mounted) return;
    setState(() {
      _draft!.add(env.copy());
      currentId = env.id;
    });
  }

  void _renameEnvironment(Environment env) async {
    if (env.isGlobal) return;
    final name = await _promptText(
        title: localizations.edit, hint: localizations.name, initial: env.name);
    final m = manager;
    if (name == null || name.trim().isEmpty || m == null) return;
    // 实时落库
    m.renameEnvironment(env.id, name.trim());
    await m.flushConfig();
    if (!mounted) return;
    setState(() => env.name = name.trim());
  }

  void _deleteEnvironment(Environment env) {
    if (env.isGlobal || _draft == null) return;
    showConfirmDialog(context, content: localizations.envDeleteConfirm, onConfirm: () async {
      final m = manager;
      if (m == null) return;
      // 实时落库
      m.removeEnvironment(env.id);
      await m.flushConfig();
      if (!mounted) return;
      setState(() {
        _draft!.remove(env);
        if (_draftActiveId == env.id) _draftActiveId = null;
        currentId = _draftGlobal.id;
      });
    });
  }

  Future<void> _openGuide() async {
    final cn = 'https://github.com/wanghongenpin/proxypin/wiki/%E7%8E%AF%E5%A2%83%E5%8F%98%E9%87%8F';
    final en = 'https://github.com/wanghongenpin/proxypin/wiki/Environment-Variables';
    final url = localizations.localeName.startsWith('zh') ? cn : en;
    try {
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        if (mounted) FlutterToastr.show('Open guide failed', context);
      }
    } catch (_) {
      if (mounted) FlutterToastr.show('Open guide failed', context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = current;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        appBar: AppBar(
          title: Text(localizations.environmentVariables,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          toolbarHeight: 36,
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: localizations.useGuide,
              onPressed: _openGuide,
              icon: const Icon(Icons.help_outline, size: 20),
            ),
            TextButton(
              onPressed: _save,
              child: Text(localizations.save, style: const TextStyle(fontSize: 14)),
            ),
          ],
        ),
        body: _draft == null || cur == null
            ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(10),
              child: Column(children: [
                const SizedBox(height: 4),
                // 激活环境切换
                Row(children: [
                  Text('${localizations.environment}: ',
                      style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: DropdownButton<String?>(
                      isDense: true,
                      isExpanded: true,
                      value: _draftActiveId,
                      hint: Text(localizations.envNone, style: const TextStyle(fontSize: 13)),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(localizations.envNone, style: const TextStyle(fontSize: 13)),
                        ),
                        ..._draftNamed.map((e) => DropdownMenuItem<String?>(
                              value: e.id,
                              child: Text(e.name, style: const TextStyle(fontSize: 13)),
                            )),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _draftActiveId = v;
                        });
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(localizations.envUsageHint.replaceFirst('%s', '{{name}}'),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                // 环境选择器 (Chips)
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _envChip(_draftGlobal),
                      for (final e in _draftNamed) _envChip(e),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: ActionChip(
                          avatar: const Icon(Icons.add, size: 16),
                          label: Text(_join(localizations.add, localizations.environment),
                              style: const TextStyle(fontSize: 12)),
                          onPressed: _addEnvironment,
                        ),
                      ),
                    ],
                  ),
                ),
                // 变量列表
                Expanded(
                    child: _VariableList(env: cur, onChanged: () => setState(() {}))),
              ]),
            ),
      ),
    );
  }

  Widget _envChip(Environment env) {
    final sel = env.id == currentId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: GestureDetector(
        onLongPress: env.isGlobal ? null : () => _showEnvMenu(env),
        child: ChoiceChip(
          avatar: Icon(env.isGlobal ? Icons.public : Icons.folder_outlined,
              size: 14, color: sel ? Theme.of(context).colorScheme.primary : Colors.grey),
          label: Text(env.isGlobal ? localizations.envGlobal : env.name, style: const TextStyle(fontSize: 12)),
          selected: sel,
          showCheckmark: false,
          onSelected: (_) => setState(() => currentId = env.id),
        ),
      ),
    );
  }

  /// 长按命名环境弹菜单:重命名 / 删除
  Future<void> _showEnvMenu(Environment env) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(localizations.edit),
            onTap: () => Navigator.of(ctx).pop('rename'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: Text(localizations.delete, style: const TextStyle(color: Colors.red)),
            onTap: () => Navigator.of(ctx).pop('delete'),
          ),
        ]),
      ),
    );
    if (action == 'rename') _renameEnvironment(env);
    if (action == 'delete') _deleteEnvironment(env);
  }
}

class _VariableList extends StatefulWidget {
  final Environment env;
  final VoidCallback onChanged;

  const _VariableList({required this.env, required this.onChanged});

  @override
  State<_VariableList> createState() => _VariableListState();
}

class _VariableListState extends State<_VariableList> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    final vars = widget.env.variables;
    return Column(children: [
      Row(children: [
        Text(widget.env.isGlobal ? localizations.envGlobal : widget.env.name,
            style: const TextStyle(fontSize: 13, color: Colors.grey)),
        const Spacer(),
        TextButton.icon(
          onPressed: () {
            setState(() {
              vars.add(EnvironmentVariable(key: '', value: ''));
              widget.onChanged();
            });
          },
          icon: const Icon(Icons.add, size: 18),
          label: Text(localizations.add, style: const TextStyle(fontSize: 12)),
        ),
      ]),
      // 表头
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.08)),
        child: Row(children: [
          const SizedBox(width: 40),
          Expanded(flex: 4, child: Text(localizations.name, style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 6),
          Expanded(flex: 6, child: Text(localizations.value, style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 30),
        ]),
      ),
      Expanded(
        child: vars.isEmpty
            ? Center(
                child: Text(localizations.envEmptyHint, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              )
            : ListView.builder(
                itemCount: vars.length,
                itemBuilder: (ctx, i) => _VarRow(
                  key: ValueKey('${widget.env.id}-$i-${vars[i].hashCode}'),
                  v: vars[i],
                  onChanged: widget.onChanged,
                  onDelete: () {
                    setState(() {
                      vars.removeAt(i);
                      widget.onChanged();
                    });
                  },
                ),
              ),
      ),
    ]);
  }
}

class _VarRow extends StatefulWidget {
  final EnvironmentVariable v;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  const _VarRow({super.key, required this.v, required this.onChanged, required this.onDelete});

  @override
  State<_VarRow> createState() => _VarRowState();
}

class _VarRowState extends State<_VarRow> {
  late final TextEditingController keyCtrl;
  late final TextEditingController valueCtrl;

  @override
  void initState() {
    super.initState();
    keyCtrl = TextEditingController(text: widget.v.key);
    valueCtrl = TextEditingController(text: widget.v.value);
  }

  @override
  void dispose() {
    keyCtrl.dispose();
    valueCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Checkbox(
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          value: widget.v.enabled,
          onChanged: (v) => setState(() {
            widget.v.enabled = v ?? false;
            widget.onChanged();
          }),
        ),
        Expanded(
          flex: 4,
          child: TextField(
            controller: keyCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: l.name,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            onChanged: (v) {
              widget.v.key = v;
              widget.onChanged();
            },
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 6,
          child: TextField(
            controller: valueCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: l.value,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            onChanged: (v) {
              widget.v.value = v;
              widget.onChanged();
            },
          ),
        ),
        IconButton(
          onPressed: widget.onDelete,
          icon: Icon(Icons.delete_outline, size: 18, color: Colors.grey.shade500),
        ),
      ]),
    );
  }
}
