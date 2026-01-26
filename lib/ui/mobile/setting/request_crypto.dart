import 'dart:convert';
import 'dart:io';
import 'dart:collection';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/request_crypto_manager.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';

bool _refresh = false;

Future<void> _refreshConfig({bool force = false}) async {
  if (force) {
    _refresh = false;
    await RequestCryptoManager.instance.then((manager) => manager.flushConfig());
    return;
  }

  if (_refresh) return;
  _refresh = true;
  Future.delayed(const Duration(milliseconds: 800), () async {
    _refresh = false;
    await RequestCryptoManager.instance.then((manager) => manager.flushConfig());
  });
}

class MobileRequestCryptoPage extends StatefulWidget {
  const MobileRequestCryptoPage({super.key});

  @override
  State<MobileRequestCryptoPage> createState() => _MobileRequestCryptoPageState();
}

class _MobileRequestCryptoPageState extends State<MobileRequestCryptoPage> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  bool enabled = false;
  bool selectionMode = false;
  final Set<int> selected = HashSet<int>();
  bool changed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = localizations;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.requestCrypto, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        toolbarHeight: 36,
        centerTitle: true,
      ),
      persistentFooterButtons: selectionMode ? [_buildSelectionFooter()] : null,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: futureWidget(
          RequestCryptoManager.instance,
          loading: true,
          (manager) {
            enabled = manager.enabled;

            return Column(
              children: [
                Row(
                  children: [
                    Text("${l10n.enable} ${l10n.requestCrypto}"),
                    const SizedBox(width: 8),
                    SwitchWidget(
                      value: enabled,
                      scale: 0.8,
                      onChanged: (val) {
                        enabled = val;
                        manager.enabled = val;
                        changed = true;
                        setState(() {});
                        _refreshConfig();
                      },
                    ),
                  ],
                ),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: () => _addRule(manager),
                    label: Text(l10n.add),
                  ),
                  const SizedBox(width: 5),
                  TextButton.icon(
                    icon: const Icon(Icons.input_rounded, size: 20),
                    onPressed: () => _import(manager),
                    label: Text(l10n.import),
                  ),
                ]),
                const SizedBox(height: 10),
                Expanded(child: _buildRuleList(manager)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRuleList(RequestCryptoManager manager) {
    final l10n = localizations;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final rules = manager.rules;

    return Scaffold(
      body: Container(
        padding: const EdgeInsets.only(top: 10, bottom: 30),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.2))),
        child: rules.isEmpty
            ? const Center(child: Text('-'))
            : Scrollbar(
                child: ListView(children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Container(width: 70, padding: const EdgeInsets.only(left: 10), child: Text(l10n.name)),
                    SizedBox(width: 46, child: Text(l10n.enable, textAlign: TextAlign.center)),
                    const VerticalDivider(),
                    const Expanded(child: Text('URL')),
                  ],
                ),
                const Divider(thickness: 0.5),
                Column(
                    children: List.generate(rules.length, (index) {
                  final rule = rules[index];
                  return InkWell(
                      highlightColor: Colors.transparent,
                      splashColor: Colors.transparent,
                      hoverColor: primaryColor.withOpacity(0.3),
                      onLongPress: () => _showRuleActions(manager, index),
                      onTap: () {
                        if (selectionMode) {
                          setState(() {
                            if (!selected.add(index)) {
                              selected.remove(index);
                            }
                          });
                          return;
                        }
                        _editRule(manager, index);
                      },
                      child: Container(
                          color: selected.contains(index)
                              ? primaryColor.withOpacity(0.8)
                              : index.isEven
                                  ? Colors.grey.withOpacity(0.1)
                                  : null,
                          height: 45,
                          padding: const EdgeInsets.all(5),
                          child: Row(children: [
                            SizedBox(
                                width: 70,
                                child: Text(rule.name.isEmpty ? '-' : rule.name,
                                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                            SizedBox(
                                width: 35,
                                child: SwitchWidget(
                                    scale: 0.65,
                                    value: rule.enabled,
                                    onChanged: (val) {
                                      rule.enabled = val;
                                      changed = true;
                                      setState(() {});
                                      _refreshConfig();
                                    })),
                            const SizedBox(width: 20),
                            Expanded(
                                child: Text(rule.urlPattern.isEmpty ? l10n.emptyMatchAll : rule.urlPattern,
                                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                          ])));
                }))
              ])),
      ),
    );
  }

  Stack _buildSelectionFooter() {
    final l10n = localizations;
    return Stack(children: [
      Container(
          height: 50,
          width: double.infinity,
          margin: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.2)))),
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
                                final m = await RequestCryptoManager.instance;
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

  Future<void> _addRule(RequestCryptoManager manager) async {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MobileCryptoRuleEditPage())).then((value) {
      if (value != null && mounted) {
        setState(() {});
        _refreshConfig(force: true);
      }
    });
  }

  Future<void> _editRule(RequestCryptoManager manager, int index) async {
    final rule = manager.rules[index];
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MobileCryptoRuleEditPage(rule: rule))).then((value) {
      if (value != null && mounted) {
        setState(() {});
        _refreshConfig(force: true);
      }
    });
  }

  void _showRuleActions(RequestCryptoManager manager, int index) {
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
            ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.edit),
                onTap: () {
                  Navigator.pop(ctx);
                  _editRule(manager, index);
                }),
            const Divider(thickness: 0.5, height: 5),
            BottomSheetItem(text: l10n.export, onPressed: () => _export(manager, indexes: [index])),
            const Divider(thickness: 0.5, height: 5),
            BottomSheetItem(
                text: manager.rules[index].enabled ? l10n.disabled : l10n.enable,
                onPressed: () {
                  manager.rules[index].enabled = !manager.rules[index].enabled;
                  changed = true;
                  setState(() {});
                  _refreshConfig();
                }),
            const Divider(thickness: 0.5, height: 5),
            BottomSheetItem(
                text: l10n.delete,
                onPressed: () {
                  Navigator.pop(ctx);
                  _removeRule(manager, index);
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

  Future<void> _removeRule(RequestCryptoManager manager, int index) async {
    await manager.removeRule(index);
    if (!mounted) return;
    changed = true;
    setState(() {});
    _refreshConfig(force: true);
  }

  Future<void> _removeSelected() async {
    final l10n = localizations;
    if (selected.isEmpty) return;
    showConfirmDialog(context, content: l10n.confirmContent, onConfirm: () async {
      final manager = await RequestCryptoManager.instance;
      final indexes = selected.toList()..sort((a, b) => b.compareTo(a));
      for (final idx in indexes) {
        await manager.removeRule(idx);
      }
      if (!mounted) return;
      changed = true;
      setState(() {
        selectionMode = false;
        selected.clear();
      });
      _refreshConfig(force: true);
      if (mounted) FlutterToastr.show(l10n.deleteSuccess, context);
    });
  }

  Future<void> _import(RequestCryptoManager manager) async {
    try {
      FilePickerResult? result =
          await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      final path = result?.files.single.path;
      if (path == null) return;
      final content = await File(path).readAsString();
      final List list = jsonDecode(content);
      for (final item in list) {
        await manager.addRule(CryptoRule.fromJson(Map<String, dynamic>.from(item)));
      }
      if (!mounted) return;
      changed = true;
      setState(() {});
      _refreshConfig(force: true);
      FlutterToastr.show(localizations.importSuccess, context);
    } catch (e) {
      logger.e('导入失败', error: e);
      if (mounted) FlutterToastr.show('${localizations.importFailed} $e', context);
    }
  }

  Future<void> _export(RequestCryptoManager manager, {List<int>? indexes}) async {
    try {
      if (manager.rules.isEmpty) return;
      final keys = (indexes == null || indexes.isEmpty)
          ? List<int>.generate(manager.rules.length, (i) => i)
          : (indexes.toList()..sort());
      final data = keys.map((i) => manager.rules[i].toJson()).toList();
      final path = await FilePicker.platform.saveFile(fileName: 'request_crypto.json');
      if (path == null) return;
      await File(path).writeAsString(jsonEncode(data));
      if (mounted) FlutterToastr.show(localizations.exportSuccess, context);
    } catch (e) {
      logger.e('导出失败', error: e);
      if (mounted) FlutterToastr.show('Export failed: $e', context);
    }
  }
}

/// Mobile editor page for a single crypto rule.
///
/// This mirrors the mobile rewrite editor pattern: push to a page, edit, and save.
class MobileCryptoRuleEditPage extends StatefulWidget {
  final CryptoRule? rule;

  const MobileCryptoRuleEditPage({super.key, this.rule});

  @override
  State<MobileCryptoRuleEditPage> createState() => _MobileCryptoRuleEditPageState();
}

class _MobileCryptoRuleEditPageState extends State<MobileCryptoRuleEditPage> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late CryptoRule _rule;

  late TextEditingController nameController;
  late TextEditingController patternController;
  late TextEditingController fieldController;

  // key + iv
  late TextEditingController keyController;
  late TextEditingController ivController;

  bool enabled = true;
  String mode = 'CBC';
  String padding = 'PKCS7';
  int length = 256;

  // formats & sources
  String keyFormat = 'text'; // text | base64
  String ivSource = 'manual'; // manual | prefix
  int ivPrefixLength = 16;

  @override
  void initState() {
    super.initState();

    _rule = (widget.rule ?? CryptoRule.newRule());

    nameController = TextEditingController(text: _rule.name);
    patternController = TextEditingController(text: _rule.urlPattern);
    fieldController = TextEditingController(text: _rule.field ?? '');

    enabled = _rule.enabled;
    mode = _rule.config.mode;
    padding = _rule.config.padding;
    length = _rule.config.keyLength;

    // key format handling (only text/base64)
    final storedKey = _rule.config.key.trim();
    if (storedKey.startsWith('base64:')) {
      keyFormat = 'base64';
      keyController = TextEditingController(text: storedKey.substring(7));
    } else {
      keyFormat = 'text';
      keyController = TextEditingController(text: storedKey);
    }

    // iv source and value
    ivSource = _rule.config.ivSource;
    ivPrefixLength = _rule.config.ivPrefixLength;

    final storedIv = _rule.config.iv.trim();
    if (storedIv.startsWith('base64:')) {
      ivController = TextEditingController(text: storedIv.substring(7));
    } else {
      ivController = TextEditingController(text: storedIv);
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    patternController.dispose();
    fieldController.dispose();
    keyController.dispose();
    ivController.dispose();
    super.dispose();
  }

  InputDecoration _decorate(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.withOpacity(0.8)),
      isDense: true,
      border: const OutlineInputBorder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCN = Localizations.localeOf(context).languageCode == 'zh';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rule == null ? l10n.newBuilt : l10n.edit,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(l10n.save),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerLow.withAlpha((0.5 * 255).round()),
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Theme.of(context).dividerColor.withAlpha((0.2 * 255).round())),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.match, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: nameController,
                      decoration: _decorate(l10n.name),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: patternController,
                      decoration: _decorate('URL', hint: 'https://www.example.com/api/*'),
                      validator: (val) => (val == null || val.trim().isEmpty) ? l10n.cannotBeEmpty : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: fieldController,
                      decoration: _decorate(l10n.cryptoRuleField, hint: isCN ? '为空=整个 body' : 'empty = whole body'),
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.enable),
                      value: enabled,
                      onChanged: (v) => setState(() => enabled = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerLow.withAlpha((0.5 * 255).round()),
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Theme.of(context).dividerColor.withAlpha((0.2 * 255).round())),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AES', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _kvDropdown(
                          label: 'Mode',
                          child: DropdownButton<String>(
                            value: mode,
                            items: const [
                              DropdownMenuItem(value: 'ECB', child: Text('ECB')),
                              DropdownMenuItem(value: 'CBC', child: Text('CBC')),
                            ],
                            onChanged: (v) => setState(() => mode = v ?? 'CBC'),
                          ),
                        ),
                        _kvDropdown(
                          label: 'Padding',
                          child: DropdownButton<String>(
                            value: padding,
                            items: const [
                              DropdownMenuItem(value: 'PKCS7', child: Text('PKCS7')),
                              DropdownMenuItem(value: 'ZeroPadding', child: Text('ZeroPadding')),
                            ],
                            onChanged: (v) => setState(() => padding = v ?? 'PKCS7'),
                          ),
                        ),
                        _kvDropdown(
                          label: 'Key Length',
                          child: DropdownButton<int>(
                            value: length,
                            items: const [
                              DropdownMenuItem(value: 128, child: Text('128')),
                              DropdownMenuItem(value: 192, child: Text('192')),
                              DropdownMenuItem(value: 256, child: Text('256')),
                            ],
                            onChanged: (v) => setState(() => length = v ?? 256),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _chipDropdown(
                          value: keyFormat,
                          items: const [
                            DropdownMenuItem(value: 'text', child: Text('text')),
                            DropdownMenuItem(value: 'base64', child: Text('base64')),
                          ],
                          onChanged: (v) => setState(() => keyFormat = v ?? 'text'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: keyController,
                            decoration: _decorate('Key'),
                            validator: (val) => (val == null || val.trim().isEmpty) ? l10n.cannotBeEmpty : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (mode == 'CBC') ...[
                      Row(
                        children: [
                          _chipDropdown(
                            value: ivSource,
                            items: [
                              DropdownMenuItem(value: 'manual', child: Text(l10n.manual)),
                              DropdownMenuItem(value: 'prefix', child: Text(l10n.cryptoIvPrefixLabel)),
                            ],
                            onChanged: (v) => setState(() => ivSource = v ?? 'manual'),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ivSource == 'manual'
                                ? TextFormField(
                                    controller: ivController,
                                    decoration: _decorate('IV'),
                                    validator: (val) => (ivSource == 'manual' && (val == null || val.trim().isEmpty))
                                        ? l10n.cannotBeEmpty
                                        : null,
                                  )
                                : _ivPrefixLengthEditor(),
                          ),
                        ],
                      ),
                      if (ivSource == 'prefix')
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            l10n.cryptoIvPrefixTooltip,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _kvDropdown({required String label, required Widget child}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 8),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(child: child),
        ),
      ],
    );
  }

  Widget _chipDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 40,
      constraints: const BoxConstraints(minWidth: 95),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(6)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _ivPrefixLengthEditor() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            icon: const Icon(Icons.remove, size: 16),
            onPressed: () => setState(() => ivPrefixLength = math.max(1, ivPrefixLength - 1)),
          ),
          Text(ivPrefixLength.toString()),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            icon: const Icon(Icons.add, size: 16),
            onPressed: () => setState(() => ivPrefixLength = math.min(1024, ivPrefixLength + 1)),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      FlutterToastr.show(l10n.cannotBeEmpty, context, position: FlutterToastr.center);
      return;
    }

    var outKey = keyController.text.trim();
    if (!outKey.startsWith('base64:') && keyFormat == 'base64') {
      outKey = 'base64:$outKey';
    }

    String outIv = '';
    if (ivSource == 'manual') {
      outIv = ivController.text.trim();
      if (!outIv.startsWith('base64:') && keyFormat == 'base64') {
        outIv = 'base64:$outIv';
      }
    }

    final updated = _rule.copyWith(
      name: nameController.text.trim(),
      urlPattern: patternController.text.trim(),
      field: fieldController.text.trim(),
      enabled: enabled,
      config: CryptoKeyConfig(
        key: outKey,
        iv: outIv,
        ivSource: ivSource,
        ivPrefixLength: ivPrefixLength,
        mode: mode,
        padding: padding,
        keyLength: length,
      ),
    );

    final manager = await RequestCryptoManager.instance;
    final idx = manager.rules.indexOf(_rule);

    if (idx >= 0) {
      await manager.updateRule(idx, updated);
    } else {
      await manager.addRule(updated);
    }
    await manager.flushConfig();

    if (!mounted) return;
    FlutterToastr.show(l10n.saveSuccess, context);
    Navigator.of(context).pop(updated);
  }
}
