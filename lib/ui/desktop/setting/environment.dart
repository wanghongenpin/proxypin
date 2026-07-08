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
import 'package:proxypin/utils/flutter_compat.dart';
import 'package:url_launcher/url_launcher.dart';

/// 环境变量管理弹窗
///
/// 左侧:环境列表(Global 置顶,可增删重命名)
/// 右侧:当前选中环境的变量表(key/value/enabled)
///
/// @author wanghongen
class EnvironmentDialog extends StatefulWidget {
  final EnvironmentManager manager;

  const EnvironmentDialog({super.key, required this.manager});

  @override
  State<EnvironmentDialog> createState() => _EnvironmentDialogState();
}

class _EnvironmentDialogState extends State<EnvironmentDialog> {
  /// 工作副本 —— 所有编辑都作用在这上面,保存时才写回单例
  late List<Environment> _draft;
  late String selectedId;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  EnvironmentManager get manager => widget.manager;

  /// 词语拼接:CJK/泰文不加空格,其他语言用空格
  String _join(String a, String b) {
    final code = localizations.localeName;
    final noSpace = code.startsWith('zh') || code == 'th' || code == 'ja' || code == 'ko';
    return noSpace ? '$a$b' : '$a $b';
  }

  Environment get _draftGlobal =>
      _draft.firstWhere((e) => e.isGlobal, orElse: () => _draft.first);

  List<Environment> get _draftNamed => _draft.where((e) => !e.isGlobal).toList();

  Environment get selected => _draft.firstWhere(
        (e) => e.id == selectedId,
        orElse: () => _draftGlobal,
      );

  @override
  void initState() {
    super.initState();
    // 深拷贝所有环境,避免直接改单例
    _draft = manager.environments.map((e) => e.copy()).toList();
    selectedId = _draftGlobal.id;
  }

  Future<void> _save() async {
    manager.applyFrom(_draft);
    await manager.flushConfig();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _addEnvironment() async {
    final name = await _promptText(
      title: _join(localizations.add, localizations.environment),
      hint: localizations.name,
    );
    if (name == null || name.trim().isEmpty) return;
    final env = Environment(id: RandomUtil.randomString(8), name: name.trim());
    // 实时落库:新环境结构立刻可见,不需要等"保存"
    manager.upsertEnvironment(env);
    await manager.flushConfig();
    if (!mounted) return;
    setState(() {
      _draft.add(env.copy());
      selectedId = env.id;
    });
  }

  void _renameEnvironment(Environment env) async {
    if (env.isGlobal) return;
    final name = await _promptText(
      title: localizations.edit,
      hint: localizations.name,
      initial: env.name,
    );
    if (name == null || name.trim().isEmpty) return;
    // 实时落库:改名立刻同步到工具栏和磁盘
    manager.renameEnvironment(env.id, name.trim());
    await manager.flushConfig();
    if (!mounted) return;
    setState(() => env.name = name.trim());
  }

  void _deleteEnvironment(Environment env) async {
    if (env.isGlobal) return;
    final ok = await _confirm(localizations.envDeleteConfirm);
    if (ok != true) return;
    // 实时落库:删除立刻生效
    manager.removeEnvironment(env.id);
    await manager.flushConfig();
    if (!mounted) return;
    setState(() {
      _draft.remove(env);
      selectedId = _draftGlobal.id;
    });
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
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(localizations.cancel)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: Text(localizations.confirm)),
        ],
      ),
    );
  }

  Future<bool?> _confirm(String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(localizations.cancel)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(localizations.confirm)),
        ],
      ),
    );
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
    final envs = [_draftGlobal, ..._draftNamed];

    return AlertDialog(
      titlePadding: const EdgeInsets.only(top: 10, left: 20, right: 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
      actionsPadding: const EdgeInsets.only(right: 15, bottom: 15),
      title: Row(children: [
        Text(localizations.environmentVariables, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(localizations.envUsageHint.replaceFirst('%s', '{{name}}'),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ),
        IconButton(
          tooltip: localizations.useGuide,
          onPressed: _openGuide,
          icon: const Icon(Icons.help_outline, size: 18),
        ),
      ]),
      content: SizedBox(
        width: 780,
        height: 460,
        child: Row(children: [
          // 左侧:环境列表
          SizedBox(
            width: 200,
            child: Column(children: [
              Row(children: [
                Text(localizations.environment, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                const Spacer(),
                IconButton(
                  tooltip: _join(localizations.add, localizations.environment),
                  onPressed: _addEnvironment,
                  icon: const Icon(Icons.add, size: 18),
                ),
              ]),
              Expanded(
                child: ListView.builder(
                  itemCount: envs.length,
                  itemBuilder: (ctx, i) {
                    final env = envs[i];
                    final isSel = env.id == selectedId;
                    return InkWell(
                      onTap: () => setState(() => selectedId = env.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSel ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1) : null,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(children: [
                          Icon(env.isGlobal ? Icons.public : Icons.folder_outlined,
                              size: 16, color: isSel ? Theme.of(context).colorScheme.primary : Colors.grey),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              env.isGlobal ? localizations.envGlobal : env.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (!env.isGlobal) ...[
                            InkWell(
                              onTap: () => _renameEnvironment(env),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(Icons.edit_outlined, size: 14, color: Colors.grey.shade500),
                              ),
                            ),
                            InkWell(
                              onTap: () => _deleteEnvironment(env),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(Icons.delete_outline, size: 14, color: Colors.grey.shade500),
                              ),
                            ),
                          ],
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
          const VerticalDivider(width: 20),
          // 右侧:变量表
          Expanded(child: _VariableTable(env: selected, onChanged: () => setState(() {}))),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.cancel),
        ),
        TextButton(onPressed: _save, child: Text(localizations.save)),
      ],
    );
  }
}

class _VariableTable extends StatefulWidget {
  final Environment env;
  final VoidCallback onChanged;

  const _VariableTable({required this.env, required this.onChanged});

  @override
  State<_VariableTable> createState() => _VariableTableState();
}

class _VariableTableState extends State<_VariableTable> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    final vars = widget.env.variables;
    return Column(children: [
      Row(children: [
        Text(widget.env.isGlobal ? localizations.envGlobal : widget.env.name,
            style: const TextStyle(fontSize: 13, color: Colors.grey)),
        const Spacer(),
        IconButton(
          tooltip: localizations.add,
          onPressed: () {
            setState(() {
              vars.add(EnvironmentVariable(key: '', value: ''));
              widget.onChanged();
            });
          },
          icon: const Icon(Icons.add, size: 18),
        ),
      ]),
      const SizedBox(height: 4),
      // 表头
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.08)),
        child: Row(children: [
          const SizedBox(width: 34),
          Expanded(flex: 4, child: Text(localizations.name, style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 8),
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
                itemBuilder: (ctx, i) => _VariableRow(
                  key: ValueKey('${widget.env.id}-$i-${vars[i].hashCode}'),
                  variable: vars[i],
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

class _VariableRow extends StatefulWidget {
  final EnvironmentVariable variable;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  const _VariableRow({super.key, required this.variable, required this.onChanged, required this.onDelete});

  @override
  State<_VariableRow> createState() => _VariableRowState();
}

class _VariableRowState extends State<_VariableRow> {
  late final TextEditingController keyCtrl;
  late final TextEditingController valueCtrl;

  @override
  void initState() {
    super.initState();
    keyCtrl = TextEditingController(text: widget.variable.key);
    valueCtrl = TextEditingController(text: widget.variable.value);
  }

  @override
  void dispose() {
    keyCtrl.dispose();
    valueCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15)))),
      child: Row(children: [
        SizedBox(
          width: 34,
          child: Checkbox(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            value: widget.variable.enabled,
            onChanged: (v) => setState(() {
              widget.variable.enabled = v ?? false;
              widget.onChanged();
            }),
          ),
        ),
        Expanded(
          flex: 4,
          child: TextField(
            controller: keyCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            onChanged: (v) {
              widget.variable.key = v;
              widget.onChanged();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: TextField(
            controller: valueCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            onChanged: (v) {
              widget.variable.value = v;
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

/// 外部方便调用
Future<void> showEnvironmentDialog(BuildContext context) async {
  final manager = await EnvironmentManager.instance;
  if (!context.mounted) return;
  await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => EnvironmentDialog(manager: manager),
  );
}
