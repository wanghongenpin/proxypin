import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/request_crypto_manager.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';

bool _refresh = false;

/// 刷新配置
Future<void> _refreshConfig({bool force = false}) async {
  if (force) {
    _refresh = false;
    await RequestCryptoManager.instance.then((manager) => manager.flushConfig());
    await DesktopMultiWindow.invokeMethod(0, "refreshRequestCrypto");
    return;
  }

  if (_refresh) {
    return;
  }
  _refresh = true;
  Future.delayed(const Duration(milliseconds: 1000), () async {
    _refresh = false;
    await RequestCryptoManager.instance.then((manager) => manager.flushConfig());
    await DesktopMultiWindow.invokeMethod(0, "refreshRequestCrypto");
  });
}

class RequestCryptoPage extends StatefulWidget {
  final int? windowId;
  final RequestCryptoManager manager;

  const RequestCryptoPage({super.key, this.windowId, required this.manager});

  @override
  State<RequestCryptoPage> createState() => _RequestCryptoPageState();
}

class _RequestCryptoPageState extends State<RequestCryptoPage> {
  final Map<int, bool> selected = {};

  RequestCryptoManager get manager => widget.manager;
  bool isPressed = false;
  Offset? lastPressPosition;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
        return true;
      }
      if (widget.windowId != null) WindowController.fromWindowId(widget.windowId!).close();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
        appBar: AppBar(
            title: Text(localizations.requestCrypto, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            toolbarHeight: 36,
            centerTitle: true),
        body: Center(
            child: Container(
                padding: const EdgeInsets.only(left: 15, right: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    SizedBox(
                        width: 225,
                        child: ListTile(
                            title: Text("${localizations.enable} ${localizations.requestCrypto}"),
                            trailing: SwitchWidget(
                                value: manager.enabled,
                                scale: 0.8,
                                onChanged: (value) {
                                  manager.enabled = value;
                                  _refreshConfig();
                                }))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton.icon(
                          icon: const Icon(Icons.add, size: 18), label: Text(localizations.add), onPressed: _addRule),
                      const SizedBox(width: 5),
                      TextButton.icon(
                          icon: const Icon(Icons.input_rounded, size: 18),
                          onPressed: _import,
                          label: Text(localizations.import))
                    ])),
                    const SizedBox(width: 15)
                  ]),
                  const SizedBox(height: 16),
                  _buildRuleList()
                ]))));
  }

  Widget _buildRuleList() {
    final theme = Theme.of(context);
    return GestureDetector(
        onSecondaryTapDown: (details) => _showGlobalMenu(details.globalPosition),
        child: Listener(
            onPointerUp: (_) => isPressed = false,
            onPointerDown: (event) {
              lastPressPosition = event.localPosition;
              if (event.buttons == kPrimaryButton) {
                isPressed = true;
              }
            },
            child: Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.withAlpha((0.2 * 255).round()))),
                child: Column(children: [
                  Padding(
                      padding: EdgeInsets.only(left: 5, bottom: 5),
                      child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
                        Container(width: 80, padding: const EdgeInsets.only(left: 10), child: Text(localizations.name)),
                        SizedBox(width: 80, child: Text(localizations.enable, textAlign: TextAlign.center)),
                        const VerticalDivider(width: 24),
                        const Expanded(child: Text('URL')),
                        SizedBox(width: 220, child: Text(localizations.cryptoRuleField, textAlign: TextAlign.center)),
                        SizedBox(width: 120, child: Text(localizations.action, textAlign: TextAlign.center))
                      ])),
                  const Divider(thickness: 0.5, height: 5),
                  ...List.generate(manager.rules.length, (index) {
                    final rule = manager.rules[index];
                    final selectedState = selected[index] == true;
                    return InkWell(
                        highlightColor: Colors.transparent,
                        splashColor: Colors.transparent,
                        hoverColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                        onSecondaryTapDown: (details) => _showRowMenu(details.globalPosition, index),
                        onDoubleTap: () => _editRule(index),
                        onHover: (hover) {
                          if (isPressed && !selectedState) {
                            setState(() => selected[index] = true);
                          }
                        },
                        onTap: () {
                          if (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) {
                            setState(() => selected[index] = !(selected[index] ?? false));
                            return;
                          }
                          if (selected.isEmpty) {
                            return;
                          }
                          setState(() => selected.clear());
                        },
                        child: Container(
                            color: selectedState
                                ? theme.colorScheme.primary.withValues(alpha: 0.2)
                                : index.isEven
                                    ? Colors.grey.withAlpha((0.06 * 255).round())
                                    : null,
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(children: [
                              SizedBox(
                                  width: 80,
                                  child: Text(rule.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                              SizedBox(
                                  width: 80,
                                  child: SwitchWidget(
                                      scale: 0.7, value: rule.enabled, onChanged: (val) => _toggleRule(index, val))),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(rule.urlPattern.isEmpty ? localizations.emptyMatchAll : rule.urlPattern,
                                      overflow: TextOverflow.ellipsis)),
                              SizedBox(
                                  width: 220,
                                  child: Text(rule.field ?? '',
                                      overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
                              SizedBox(
                                  width: 120,
                                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    IconButton(
                                        icon: const Icon(Icons.edit, size: 18),
                                        tooltip: localizations.edit,
                                        onPressed: () => _editRule(index)),
                                    IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 18),
                                        tooltip: localizations.delete,
                                        onPressed: () => _removeRules([index]))
                                  ]))
                            ])));
                  })
                ]))));
  }

  Future<void> _addRule() async {
    final newRule =
        await showDialog<CryptoRule>(context: context, barrierDismissible: false, builder: (_) => CryptoRuleDialog());
    if (newRule == null) return;
    await manager.addRule(newRule);
    setState(() {});
    _refreshConfig(force: true);
  }

  Future<void> _editRule(int index) async {
    final rule = manager.rules[index];
    final updated = await showDialog<CryptoRule>(context: context, builder: (_) => CryptoRuleDialog(rule: rule));
    if (updated == null) return;
    await manager.updateRule(index, updated);
    _refreshConfig(force: true);
    setState(() {});
  }

  Future<void> _toggleRule(int index, bool value) async {
    await manager.updateRule(index, manager.rules[index].copyWith(enabled: value));
    _refreshConfig(force: true);
    setState(() {});
  }

  void _showRowMenu(Offset position, int index) {
    showContextMenu(context, position, items: [
      PopupMenuItem(height: 35, child: Text(localizations.edit), onTap: () => _editRule(index)),
      PopupMenuItem(height: 35, child: Text(localizations.delete), onTap: () => _removeRules([index]))
    ]);
  }

  void _showGlobalMenu(Offset offset) {
    showContextMenu(context, offset, items: [
      PopupMenuItem(height: 35, onTap: _addRule, child: Text(localizations.newBuilt)),
      PopupMenuItem(height: 35, child: Text(localizations.export), onTap: () => _export(selected.keys.toList())),
      const PopupMenuDivider(),
      PopupMenuItem(height: 35, child: Text(localizations.enableSelect), onTap: () => _enableStatus(true)),
      PopupMenuItem(height: 35, child: Text(localizations.disableSelect), onTap: () => _enableStatus(false)),
      const PopupMenuDivider(),
      PopupMenuItem(
          height: 35, child: Text(localizations.deleteSelect), onTap: () => _removeRules(selected.keys.toList()))
    ]);
  }

  Future<void> _removeRules(List<int> indexes) async {
    if (indexes.isEmpty) return;
    indexes.sort((a, b) => b.compareTo(a));
    for (final index in indexes) {
      await manager.removeRule(index);
    }
    selected.clear();
    _refreshConfig(force: true);
  }

  Future<void> _enableStatus(bool enable) async {
    if (selected.isEmpty) return;
    for (final entry in selected.entries) {
      if (entry.value) {
        await manager.updateRule(entry.key, manager.rules[entry.key].copyWith(enabled: enable));
      }
    }
    selected.clear();
    _refreshConfig(force: true);
  }

  Future<void> _import() async {
    String? path;
    if (Platform.isMacOS) {
      path = await DesktopMultiWindow.invokeMethod(0, "pickFiles", {
        "allowedExtensions": ['json']
      });
      if (widget.windowId != null) WindowController.fromWindowId(widget.windowId!).show();
    } else {
      FilePickerResult? result =
          await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      path = result?.files.single.path;
    }
    if (path == null) return;
    try {
      final content = await File(path).readAsString();
      final List list = jsonDecode(content);
      for (final item in list) {
        await manager.addRule(CryptoRule.fromJson(Map<String, dynamic>.from(item)));
      }
      _refreshConfig(force: true);
      if (mounted) FlutterToastr.show(localizations.importSuccess, context);
    } catch (e) {
      logger.e('导入失败 $path', error: e);
      if (mounted) FlutterToastr.show("${localizations.importFailed} $e", context);
    }
  }

  Future<void> _export(List<int> indexes) async {
    if (indexes.isEmpty) return;
    indexes.sort();
    final data = indexes.map((i) => manager.rules[i].toJson()).toList();
    String? path;
    if (Platform.isMacOS) {
      path = await DesktopMultiWindow.invokeMethod(0, "saveFile", {"fileName": 'request_crypto.json'});
      if (widget.windowId != null) WindowController.fromWindowId(widget.windowId!).show();
    } else {
      path = await FilePicker.platform.saveFile(fileName: 'request_crypto.json');
    }
    if (path == null) return;
    await File(path).writeAsString(jsonEncode(data));
    FlutterToastr.show(localizations.exportSuccess, context);
  }
}

class CryptoRuleDialog extends StatefulWidget {
  final CryptoRule? rule;

  const CryptoRuleDialog({super.key, this.rule});

  @override
  State<CryptoRuleDialog> createState() => _CryptoRuleDialogState();
}

class _CryptoRuleDialogState extends State<CryptoRuleDialog> {
  late TextEditingController nameController;
  late TextEditingController patternController;
  late TextEditingController keyController;
  late TextEditingController ivController;
  late TextEditingController fieldInputController;
  String mode = 'CBC';
  String padding = 'PKCS7';
  int length = 128;
  bool enabled = true;

  // single field support
  late String fieldItem;
  final _formKey = GlobalKey<FormState>();
  String keyFormat = 'text';
  String ivSource = 'manual';
  int ivPrefixLength = 16;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    nameController = TextEditingController(text: rule?.name ?? '');
    patternController = TextEditingController(text: rule?.urlPattern ?? '');
    keyController = TextEditingController(text: rule?.config.key);
    ivController = TextEditingController(text: rule?.config.iv);
    // single field support: initialize from first existing field if present
    fieldInputController = TextEditingController(text: rule?.field ?? '');
    mode = rule?.config.mode ?? 'CBC';
    padding = rule?.config.padding ?? 'PKCS7';
    length = rule?.config.keyLength ?? 256;
    enabled = rule?.enabled ?? true;
    fieldItem = rule?.field ?? '';
    // detect stored key/iv prefix (support base64: or plain text)
    final storedKey = rule?.config.key ?? '';
    if (storedKey.startsWith('base64:')) {
      keyFormat = 'base64';
      keyController.text = storedKey.substring(7);
    } else {
      keyFormat = 'text';
      keyController.text = storedKey;
    }

    final storedIv = rule?.config.iv ?? '';
    // keep stored iv as-is if prefixed with base64:, otherwise show raw value
    if (storedIv.startsWith('base64:')) {
      ivController.text = storedIv.substring(7);
    } else {
      ivController.text = storedIv;
    }
    // iv source and prefix length
    ivSource = rule?.config.ivSource ?? 'manual';
    ivPrefixLength = rule?.config.ivPrefixLength ?? 16;
  }

  @override
  void dispose() {
    nameController.dispose();
    patternController.dispose();
    keyController.dispose();
    ivController.dispose();
    fieldInputController.dispose();
    super.dispose();
  }

  InputDecoration decorate(BuildContext context, String? label, {String? hint, Widget? suffixIcon}) {
    return InputDecoration(
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
        isDense: true,
        border: const OutlineInputBorder());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.rule == null ? l10n.newBuilt : l10n.edit),
      scrollable: true,
      titlePadding: const EdgeInsets.only(top: 10, left: 20),
      actionsPadding: const EdgeInsets.only(right: 15, bottom: 15),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      content: Container(
        width: 550,
        constraints: const BoxConstraints(minHeight: 200, maxHeight: 560),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainerLow.withAlpha((0.5 * 255).round()),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Theme.of(context).dividerColor.withAlpha((0.2 * 255).round())),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l10n.match, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 12),
                      TextFormField(controller: nameController, decoration: decorate(context, l10n.name)),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: patternController,
                        decoration: decorate(context, "URL", hint: 'https://www.example.com/api/*'),
                        validator: (val) => val == null || val.trim().isEmpty ? l10n.cannotBeEmpty : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: fieldInputController,
                        decoration: decorate(context, l10n.cryptoRuleField, hint: 'data.field'),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.enable),
                        value: enabled,
                        onChanged: (value) => setState(() => enabled = value),
                      ),
                    ]),
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
                    padding: const EdgeInsets.all(10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text("AES", style: theme.textTheme.titleSmall),
                      const SizedBox(height: 12),
                      // Key input and format selector in a single row for nicer UI
                      Row(children: [
                        Expanded(
                          child: SizedBox(
                            child: TextFormField(
                              controller: keyController,
                              maxLength: 128,
                              decoration: decorate(context, "Key").copyWith(counterText: ''),
                              validator: (val) => val == null || val.trim().isEmpty ? l10n.cannotBeEmpty : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).dividerColor.withAlpha((0.12 * 255).round())),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: keyFormat,
                              items: const [
                                DropdownMenuItem(value: 'text', child: Text('text')),
                                DropdownMenuItem(value: 'base64', child: Text('base64')),
                              ],
                              onChanged: (v) => setState(() => keyFormat = v ?? 'text'),
                              style: Theme.of(context).textTheme.bodyMedium,
                              iconEnabledColor: Theme.of(context).colorScheme.primary,
                              itemHeight: 48,
                            ),
                          ),
                        )
                      ]),
                      const SizedBox(height: 12),
                      // Compact single-line IV controls for CBC
                      if (mode == 'CBC')
                        Row(children: [
                          // small segmented control
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'manual', label: Text('输入')),
                              ButtonSegment(value: 'prefix', label: Text('从密文取')),
                            ],
                            selected: {ivSource},
                            onSelectionChanged: (selection) => setState(() => ivSource = selection.first),
                          ),
                          const SizedBox(width: 8),
                          // narrow IV input when manual (fixed width for compactness)
                          if (ivSource == 'manual')
                            SizedBox(
                              width: 220,
                              height: 40,
                              child: TextFormField(
                                controller: ivController,
                                decoration: decorate(context, 'IV', hint: l10n.optional).copyWith(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
                                validator: (val) => (ivSource == 'manual' && (val == null || val.trim().isEmpty))
                                    ? l10n.cannotBeEmpty
                                    : null,
                              ),
                            ),
                          if (ivSource == 'manual') const SizedBox(width: 8),
                          if (ivSource == 'prefix')
                            Tooltip(
                                message: '从密文的前 N 字节提取 IV（通常为 16）',
                                child: Icon(Icons.info_outline, size: 16, color: theme.dividerColor)),
                          if (ivSource == 'prefix') const SizedBox(width: 8),
                          // compact numeric stepper (prefix length)
                          if (ivSource == 'prefix')
                            Container(
                              decoration: BoxDecoration(
                                  border: Border.all(color: theme.dividerColor.withAlpha(0x40)),
                                  borderRadius: BorderRadius.circular(4)),
                              child: Row(children: [
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.remove, size: 14),
                                  onPressed: ivSource == 'prefix'
                                      ? () => setState(() => ivPrefixLength = math.max(1, ivPrefixLength - 1))
                                      : null,
                                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                                ),
                                SizedBox(
                                    width: 36,
                                    child: Center(
                                        child: Text(ivPrefixLength.toString(), style: theme.textTheme.bodySmall))),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.add, size: 14),
                                  onPressed: ivSource == 'prefix'
                                      ? () => setState(() => ivPrefixLength = math.min(1024, ivPrefixLength + 1))
                                      : null,
                                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                                ),
                              ]),
                            ),
                        ]),
                      const SizedBox(height: 12),
                      // Compact row: Mode | Padding | Key Length
                      Row(children: [
                        Text("Mode", style: theme.textTheme.labelMedium),
                        const SizedBox(width: 8),
                        Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).dividerColor.withAlpha((0.12 * 255).round())),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: mode,
                              items: const [
                                DropdownMenuItem(value: 'ECB', child: Text('ECB')),
                                DropdownMenuItem(value: 'CBC', child: Text('CBC')),
                              ],
                              onChanged: (v) => setState(() => mode = v ?? 'ECB'),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('Padding', style: theme.textTheme.labelMedium),
                        const SizedBox(width: 8),
                        Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).dividerColor.withAlpha((0.12 * 255).round())),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: padding,
                              items: const [
                                DropdownMenuItem(value: 'PKCS7', child: Text('PKCS7')),
                                DropdownMenuItem(value: 'ZeroPadding', child: Text('ZeroPadding')),
                              ],
                              onChanged: (v) => setState(() => padding = v ?? 'PKCS7'),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('Key Length', style: theme.textTheme.labelMedium),
                        const SizedBox(width: 8),
                        Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).dividerColor.withAlpha((0.12 * 255).round())),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: length,
                              items: const [
                                DropdownMenuItem(value: 128, child: Text('128')),
                                DropdownMenuItem(value: 192, child: Text('192')),
                                DropdownMenuItem(value: 256, child: Text('256')),
                              ],
                              onChanged: (v) => setState(() => length = v ?? 128),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState as FormState).validate()) return;
            String outKey = keyController.text.trim();
            // add prefix based on selected keyFormat if user did not already include explicit prefix
            if (!(outKey.startsWith('base64:'))) {
              if (keyFormat == 'base64') {
                outKey = 'base64:$outKey';
              }
            }

            // only set explicit IV when manual source is used
            String outIv = '';
            if (ivSource == 'manual') {
              outIv = ivController.text.trim();
              if (!(outIv.startsWith('base64:'))) {
                if (keyFormat == 'base64') {
                  outIv = 'base64:$outIv';
                }
              }
            }

            // save single field from the input controller
            final savedField = fieldInputController.text.trim();
            final updated = (widget.rule ?? CryptoRule.newRule()).copyWith(
              name: nameController.text.trim(),
              urlPattern: patternController.text.trim(),
              field: savedField,
              enabled: enabled,
              config: CryptoKeyConfig(
                  key: outKey,
                  iv: outIv,
                  ivSource: ivSource,
                  ivPrefixLength: ivPrefixLength,
                  mode: mode,
                  padding: padding,
                  keyLength: length),
            );
            Navigator.of(context).pop(updated);
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
