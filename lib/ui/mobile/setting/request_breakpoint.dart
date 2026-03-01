import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/request_breakpoint_manager.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/widgets.dart';

import '../../component/http_method_popup.dart';

class MobileRequestBreakpointPage extends StatefulWidget {
  const MobileRequestBreakpointPage({super.key});

  @override
  State<MobileRequestBreakpointPage> createState() => _RequestBreakpointPageState();
}

class _RequestBreakpointPageState extends State<MobileRequestBreakpointPage> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;
  List<RequestBreakpointRule> rules = [];
  bool enabled = false;
  RequestBreakpointManager? manager;

  bool selectionMode = false;
  final Set<int> selected = HashSet<int>();

  Future<void> _save() async {
    await manager?.save();
  }

  @override
  void initState() {
    super.initState();
    RequestBreakpointManager.instance.then((value) {
      manager = value;
      setState(() {
        enabled = value.enabled;
        rules = value.list;
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isEN = Localizations.localeOf(context).languageCode == 'en';

    return Scaffold(
        backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
        appBar: AppBar(
            title: Text(localizations.breakpoint, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            toolbarHeight: 36,
            centerTitle: true),
        body: Center(
            child: Container(
                padding: const EdgeInsets.only(left: 15, right: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    SizedBox(
                        width: isEN ? 230 : 160,
                        child: ListTile(
                            title: Text("${localizations.enable} ${localizations.breakpoint}"),
                            contentPadding: const EdgeInsets.only(left: 2),
                            trailing: SwitchWidget(
                                value: enabled,
                                scale: 0.8,
                                onChanged: (val) async {
                                  manager?.enabled = val;
                                  await _save();
                                  setState(() {
                                    enabled = val;
                                  });
                                }))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      IconButton(
                          icon: Icon(Icons.add, size: 22, color: Theme.of(context).colorScheme.primary),
                          onPressed: _editRule,
                          tooltip: localizations.add),
                      const SizedBox(width: 5),
                      IconButton(
                          icon: Icon(Icons.input_rounded, size: 22, color: Theme.of(context).colorScheme.primary),
                          onPressed: _import,
                          tooltip: localizations.import),
                    ])),
                    const SizedBox(width: 15)
                  ]),
                  const SizedBox(height: 10),
                  Expanded(child: _buildList()),
                  if (selectionMode) _buildSelectionFooter(),
                ]))));
  }

  Widget _buildList() {
    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.withValues(alpha: 0.2))),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 5, bottom: 5),
            child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
              Container(width: 65, padding: const EdgeInsets.only(left: 10), child: Text(localizations.name)),
              SizedBox(width: 45, child: Text(localizations.enable, textAlign: TextAlign.center)),
              const VerticalDivider(width: 10),
              Expanded(child: Text("URL", textAlign: TextAlign.center)),
              SizedBox(width: 100, child: Text(localizations.breakpoint, textAlign: TextAlign.center)),
            ]),
          ),
          const Divider(thickness: 0.5, height: 5),
          Expanded(
            child: ListView.builder(
              itemCount: rules.length,
              itemBuilder: (context, index) => _buildRow(index),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildRow(int index) {
    var primaryColor = Theme.of(context).colorScheme.primary;
    var rule = rules[index];

    return InkWell(
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      hoverColor: primaryColor.withValues(alpha: 0.3),
      onLongPress: () => _showRuleActions(index),
      onTap: () {
        if (selectionMode) {
          setState(() {
            if (!selected.add(index)) {
              selected.remove(index);
            }
          });
          return;
        }
        _editRule(rule: rule);
      },
      child: Container(
        color: selected.contains(index)
            ? primaryColor.withValues(alpha: 0.5)
            : index.isEven
                ? Colors.grey.withValues(alpha: 0.1)
                : null,
        height: 32,
        padding: const EdgeInsets.all(5),
        child: Row(children: [
          SizedBox(
            width: 65,
            child: Text(rule.name ?? "",
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          SizedBox(
              width: 45,
              child: SwitchWidget(
                  scale: 0.65,
                  value: rule.enabled,
                  onChanged: (val) async {
                    rule.enabled = val;
                    await _save();
                  })),
          const SizedBox(width: 10),
          Expanded(child: Text(rule.url, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
          SizedBox(
              width: 100,
              child: Text(
                  "${rule.interceptRequest ? localizations.request : ""}${rule.interceptRequest && rule.interceptResponse ? "/" : ""}${rule.interceptResponse ? localizations.response : ""}",
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }

  Future<void> _export(RequestBreakpointManager? manager, {List<int>? indexes}) async {
    try {
      if (manager == null || manager.list.isEmpty) return;
      final rules = manager.list;
      final keys = (indexes == null || indexes.isEmpty)
          ? List<int>.generate(rules.length, (i) => i)
          : (indexes.toList()..sort());
      final data = keys.map((i) => rules[i].toJson()).toList();
      var bytes = utf8.encode(jsonEncode(data));
      final path = await FilePicker.platform.saveFile(fileName: 'request_breakpoints.json', bytes: bytes);
      if (path == null) return;
      if (mounted) FlutterToastr.show(localizations.exportSuccess, context);
    } catch (e) {
      logger.e('导出失败', error: e);
      if (mounted) FlutterToastr.show('Export failed: $e', context);
    }
  }

  Future<void> _import() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;
      File file = File(result.files.single.path!);
      String content = await file.readAsString();
      List<dynamic> list = jsonDecode(content);
      var newRules = list.map((e) => RequestBreakpointRule.fromJson(e)).toList();
      for (var rule in newRules) {
        manager?.list.add(rule);
      }
      await _save();
      setState(() {
        rules = manager!.list;
      });

      if (mounted) FlutterToastr.show(localizations.importSuccess, context);
    } catch (e) {
      logger.e('Import failed', error: e);
      if (mounted) FlutterToastr.show(localizations.importFailed, context);
    }
  }

  Stack _buildSelectionFooter() {
    final l10n = localizations;
    return Stack(children: [
      Container(
          height: 50,
          width: double.infinity,
          margin: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.withValues(alpha: 0.2)))),
      Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Center(
              child: TextButton(
                  onPressed: () {},
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    TextButton.icon(
                        onPressed: selected.isEmpty
                            ? null
                            : () async {
                                // export selected only
                                final m = await RequestBreakpointManager.instance;
                                await _export(m, indexes: selected.toList());
                                setState(() {
                                  selected.clear();
                                  selectionMode = false;
                                });
                              },
                        icon: const Icon(Icons.share, size: 18),
                        label: Text(l10n.export, style: const TextStyle(fontSize: 14))),
                    TextButton.icon(
                        onPressed: selected.isEmpty ? null : () => _removeSelected(),
                        icon: const Icon(Icons.delete, size: 18),
                        label: Text(l10n.delete, style: const TextStyle(fontSize: 14))),
                    TextButton.icon(
                        onPressed: () {
                          setState(() {
                            selectionMode = false;
                            selected.clear();
                          });
                        },
                        icon: const Icon(Icons.cancel, size: 18),
                        label: Text(l10n.cancel, style: const TextStyle(fontSize: 14))),
                  ]))))
    ]);
  }

  void _showRuleActions(int index) {
    final l10n = localizations;
    setState(() {
      selected.add(index);
    });
    showModalBottomSheet(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        context: context,
        enableDrag: true,
        builder: (ctx) {
          return Wrap(children: [
            BottomSheetItem(
                text: l10n.multiple,
                onPressed: () {
                  setState(() => selectionMode = true);
                }),
            const Divider(thickness: 0.5, height: 5),
            BottomSheetItem(
                text: l10n.edit,
                onPressed: () {
                  _editRule(rule: rules[index]);
                }),
            const Divider(thickness: 0.5, height: 5),
            BottomSheetItem(text: l10n.export, onPressed: () => _export(manager, indexes: [index])),
            const Divider(thickness: 0.5, height: 5),
            BottomSheetItem(
                text: rules[index].enabled ? l10n.disabled : l10n.enable,
                onPressed: () {
                  rules[index].enabled = !rules[index].enabled;
                  setState(() {});
                  _save();
                }),
            const Divider(thickness: 0.5, height: 5),
            BottomSheetItem(
                text: l10n.delete,
                onPressed: () {
                  _removeRule(index);
                }),
            Container(color: Theme.of(ctx).hoverColor, height: 8),
            TextButton(
                child: Container(
                    height: 45,
                    width: double.infinity,
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(l10n.cancel, textAlign: TextAlign.center)),
                onPressed: () {
                  Navigator.of(ctx).pop();
                }),
          ]);
        }).then((value) {
      if (selectionMode) {
        return;
      }
      setState(() {
        selected.remove(index);
      });
    });
  }

  Future<void> _removeRule(int index) async {
    showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(localizations.deleteHeaderConfirm, style: const TextStyle(fontSize: 18)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localizations.cancel)),
              TextButton(
                  onPressed: () async {
                    setState(() {
                      rules.removeAt(index);
                    });
                    await _save();
                    if (context.mounted) Navigator.pop(ctx);
                  },
                  child: Text(localizations.delete)),
            ],
          );
        });
  }

  Future<void> _removeSelected() async {
    showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(localizations.deleteHeaderConfirm, style: const TextStyle(fontSize: 18)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localizations.cancel)),
              TextButton(
                  onPressed: () async {
                    var list = selected.toList();
                    list.sort((a, b) => b.compareTo(a));
                    for (var i in list) {
                      rules.removeAt(i);
                    }
                    setState(() {
                      selected.clear();
                      selectionMode = false;
                    });
                    await _save();
                    if (context.mounted) Navigator.pop(ctx);
                  },
                  child: Text(localizations.delete)),
            ],
          );
        });
  }

  void _editRule({RequestBreakpointRule? rule}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MobileBreakpointRuleEditor(rule: rule),
      ),
    ).then((value) async {
      if (value != null && value is RequestBreakpointRule) {
        setState(() {
          if (rule == null) {
            rules.add(value);
          }
        });
        await _save();
      }
    });
  }
}

class MobileBreakpointRuleEditor extends StatefulWidget {
  final RequestBreakpointRule? rule;

  const MobileBreakpointRuleEditor({super.key, this.rule});

  @override
  State<MobileBreakpointRuleEditor> createState() => _MobileBreakpointRuleEditorState();
}

class _MobileBreakpointRuleEditorState extends State<MobileBreakpointRuleEditor> {
  late RequestBreakpointRule rule;
  final _formKey = GlobalKey<FormState>();

  late TextEditingController nameInput;
  late TextEditingController urlInput;

  // Local state for methods to avoid modifying rule in-place before save
  HttpMethod? _method;
  bool _interceptRequest = true;
  bool _interceptResponse = true;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    rule = widget.rule ?? RequestBreakpointRule(url: '');
    nameInput = TextEditingController(text: rule.name);
    urlInput = TextEditingController(text: rule.url);
    _method = rule.method;
    _interceptRequest = rule.interceptRequest;
    _interceptResponse = rule.interceptResponse;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            title: Text(
                widget.rule == null
                    ? "${localizations.add} ${localizations.breakpointRule}"
                    : "${localizations.edit} ${localizations.breakpointRule}",
                style: const TextStyle(fontSize: 16)),
            actions: [
              TextButton(
                  onPressed: () {
                    if (!(_formKey.currentState?.validate() ?? false)) {
                      return;
                    }
                    rule.name = nameInput.text;
                    rule.url = urlInput.text;
                    rule.method = _method;
                    rule.interceptRequest = _interceptRequest;
                    rule.interceptResponse = _interceptResponse;
                    rule.enabled = true;
                    Navigator.pop(context, rule);
                  },
                  child: Text(localizations.save))
            ]),
        body: Padding(
            padding: const EdgeInsets.all(15),
            child: Form(
                key: _formKey,
                child: ListView(children: [
                  TextFormField(
                    controller: nameInput,
                    decoration: InputDecoration(labelText: localizations.name, border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  TextFormField(
                    controller: urlInput,
                    validator: (val) => val?.isNotEmpty == true ? null : localizations.cannotBeEmpty,
                    decoration: InputDecoration(
                        labelText: 'URL',
                        hintText: 'https://www.example.com/api/*',
                        border: const OutlineInputBorder(),
                        prefixIcon: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: MethodPopupMenu(value: _method, onChanged: (val) => setState(() => _method = val)))),
                  ),
                  const SizedBox(height: 15),
                  SwitchListTile(
                      title: Text(localizations.request),
                      value: _interceptRequest,
                      onChanged: (val) => setState(() => _interceptRequest = val)),
                  SwitchListTile(
                      title: Text(localizations.response),
                      value: _interceptResponse,
                      onChanged: (val) => setState(() => _interceptResponse = val)),
                ]))));
  }
}
