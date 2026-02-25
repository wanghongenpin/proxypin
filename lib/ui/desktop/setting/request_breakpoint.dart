import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/request_breakpoint_manager.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';

import '../../component/app_dialog.dart' show CustomToast;
import '../../component/http_method_popup.dart';

class RequestBreakpointPage extends StatefulWidget {
  final int? windowId;

  const RequestBreakpointPage({super.key, this.windowId});

  @override
  State<RequestBreakpointPage> createState() => _RequestBreakpointPageState();
}

class _RequestBreakpointPageState extends State<RequestBreakpointPage> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;
  List<RequestBreakpointRule> rules = [];
  bool enabled = false;
  RequestBreakpointManager? manager;

  Set<int> selected = {};
  bool isPressed = false;
  Offset? lastPressPosition;

  Future<void> _refreshConfig() async {
    if (widget.windowId != null) {
      await DesktopMultiWindow.invokeMethod(0, "refreshRequestBreakpoint");
    }
  }

  Future<void> _save() async {
    await manager?.save();
    await _refreshConfig();
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
    File file = File(path);
    try {
      String content = await file.readAsString();
      List<dynamic> list = jsonDecode(content);
      var rules = list.map((e) => RequestBreakpointRule.fromJson(e)).toList();
      for (var rule in rules) {
        manager?.list.add(rule);
      }
      await _save();
      setState(() {
        this.rules = manager!.list;
      });

      if (mounted) CustomToast.success(localizations.importSuccess).show(context);
    } catch (e) {
      if (mounted) CustomToast.error(localizations.importFailed).show(context);
    }
  }

  Future<void> _export(List<RequestBreakpointRule> exportRules) async {
    if (exportRules.isEmpty) return;

    String? outputFile;
    if (Platform.isMacOS) {
      outputFile = await DesktopMultiWindow.invokeMethod(0, "saveFile", {"fileName": 'request_breakpoint_rules.json'});
      if (widget.windowId != null) WindowController.fromWindowId(widget.windowId!).show();
    } else {
      outputFile = await FilePicker.platform.saveFile(fileName: 'request_breakpoint_rules.json');
    }
    if (outputFile == null) return;
    File file = File(outputFile);
    try {
      var json = exportRules.map((e) => e.toJson()).toList();
      await file.writeAsString(jsonEncode(json));
      if (mounted) CustomToast.success(localizations.exportSuccess).show(context);
    } catch (e) {
      if (mounted) CustomToast.error(localizations.exportFailed).show(context);
    }
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(onKeyEvent);
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
    HardwareKeyboard.instance.removeHandler(onKeyEvent);
    super.dispose();
  }

  bool onKeyEvent(KeyEvent event) {
    if (HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.escape) && Navigator.canPop(context)) {
      Navigator.maybePop(context);
      return true;
    }

    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
        return true;
      }
      if (widget.windowId != null) {
        WindowController.fromWindowId(widget.windowId!).close();
      }
      return true;
    }
    return false;
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
                        width: isEN ? 280 : 250,
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
                      TextButton.icon(
                          icon: const Icon(Icons.add, size: 18), label: Text(localizations.add), onPressed: _editRule),
                      const SizedBox(width: 5),
                      TextButton.icon(
                          icon: const Icon(Icons.input_rounded, size: 18),
                          onPressed: _import,
                          label: Text(localizations.import)),
                    ])),
                    const SizedBox(width: 15)
                  ]),
                  const SizedBox(height: 10),
                  Expanded(child: _buildList())
                ]))));
  }

  Widget _buildList() {
    return GestureDetector(
      onSecondaryTap: () {
        if (lastPressPosition == null) {
          return;
        }
        _showMenu(lastPressPosition!);
      },
      onTapDown: (details) {
        if (selected.isEmpty) {
          return;
        }
        if (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) {
          return;
        }
        setState(() {
          selected.clear();
        });
      },
      child: Listener(
        onPointerUp: (event) => isPressed = false,
        onPointerDown: (event) {
          lastPressPosition = event.localPosition;
          if (event.buttons == kPrimaryMouseButton) {
            isPressed = true;
          }
        },
        child: Container(
          padding: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.withValues(alpha: 0.2))),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 5, bottom: 5),
                child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
                  Container(width: 150, padding: const EdgeInsets.only(left: 10), child: Text(localizations.name)),
                  SizedBox(width: 50, child: Text(localizations.enable, textAlign: TextAlign.center)),
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
        ),
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
      onDoubleTap: () => _editRule(rule: rule),
      onSecondaryTapDown: (details) => _showMenu(details.globalPosition, index: index),
      onHover: (hover) {
        if (isPressed && !selected.contains(index)) {
          setState(() {
            selected.add(index);
          });
        }
      },
      onTap: () {
        if (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) {
          setState(() {
            selected.contains(index) ? selected.remove(index) : selected.add(index);
          });
          return;
        }
        if (selected.isEmpty) {
          return;
        }
        setState(() {
          selected.clear();
        });
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
            width: 150,
            child: Text(rule.name ?? "",
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          SizedBox(
              width: 50,
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

  void _showMenu(Offset position, {int? index}) {
    if (index != null) {
      if (!selected.contains(index)) {
        setState(() {
          selected.clear();
          selected.add(index);
        });
      }
    }

    showContextMenu(context, position, items: [
      PopupMenuItem(
        height: 32,
        child: Text(localizations.edit),
        onTap: () {
          if (selected.length == 1) {
            _editRule(rule: rules[selected.first]);
          }
        },
      ),
      PopupMenuItem(
        height: 32,
        child: Text(localizations.export),
        onTap: () async {
          if (selected.isEmpty) return;
          var list = selected.toList();
          List<RequestBreakpointRule> exportRules = [];
          for (var i in list) {
            exportRules.add(rules[i]);
          }
          await _export(exportRules);
          setState(() {
            selected.clear();
          });
        },
      ),
      PopupMenuItem(
        height: 32,
        child: Text(localizations.delete),
        onTap: () async {
          if (selected.isEmpty) return;
          var list = selected.toList();
          list.sort((a, b) => b.compareTo(a)); // Remove from end to avoid index shift issues
          for (var i in list) {
            rules.removeAt(i);
          }
          setState(() {
            selected.clear();
          });
          await _save();
        },
      ),
    ]);
  }

  void _editRule({RequestBreakpointRule? rule}) {
    showDialog(
      context: context,
      builder: (context) => InterceptRuleDialog(rule: rule),
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

class InterceptRuleDialog extends StatefulWidget {
  final RequestBreakpointRule? rule;

  const InterceptRuleDialog({super.key, this.rule});

  @override
  State<InterceptRuleDialog> createState() => _InterceptRuleDialogState();
}

class _InterceptRuleDialogState extends State<InterceptRuleDialog> {
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

  InputDecoration decoration(String label, {String? hintText}) {
    return InputDecoration(
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelText: label,
        hintText: hintText,
        isDense: true,
        border: const OutlineInputBorder());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
          widget.rule == null
              ? "${localizations.add} ${localizations.breakpointRule}"
              : "${localizations.edit} ${localizations.breakpointRule}",
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      actionsPadding: const EdgeInsets.only(right: 15, bottom: 15),
      contentPadding: const EdgeInsets.only(left: 20, right: 20, top: 15, bottom: 15),
      content: Container(
        constraints: const BoxConstraints(minWidth: 350, maxWidth: 500),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  SizedBox(width: 55, child: Text('${localizations.enable}:')),
                  SwitchWidget(value: rule.enabled, onChanged: (val) => rule.enabled = val, scale: 0.8)
                ]),
                const SizedBox(height: 5),
                textField('${localizations.name}:', nameInput, localizations.pleaseEnter),
                const SizedBox(height: 10),
                Row(children: [
                  SizedBox(width: 60, child: Text('URL:')),
                  Expanded(
                    child: TextFormField(
                      controller: urlInput,
                      style: const TextStyle(fontSize: 14),
                      validator: (val) => val?.isNotEmpty == true ? null : localizations.cannotBeEmpty,
                      decoration: InputDecoration(
                        hintText: 'https://www.example.com/api/*',
                        hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
                        errorStyle: const TextStyle(height: 0, fontSize: 0),
                        focusedBorder: focusedBorder(),
                        isDense: true,
                        border: const OutlineInputBorder(),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 6, right: 6),
                          child: MethodPopupMenu(
                            value: _method,
                            showSeparator: true,
                            onChanged: (val) {
                              setState(() {
                                _method = val;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Text(localizations.breakpoint, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                const SizedBox(height: 5),
                Container(
                  decoration: BoxDecoration(
                      // border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(5)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child: CheckboxListTile(
                        contentPadding: const EdgeInsets.only(left: 10),
                        title: Text(localizations.request, style: const TextStyle(fontSize: 14)),
                        value: _interceptRequest,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        visualDensity: const VisualDensity(vertical: -4),
                        onChanged: (val) {
                          setState(() {
                            _interceptRequest = val!;
                          });
                        },
                      )),
                      // Container(height: 30, width: 0.5, color: Colors.grey.withValues(alpha: 0.5)),
                      Expanded(
                          child: CheckboxListTile(
                        contentPadding: const EdgeInsets.only(left: 10),
                        title: Text(localizations.response, style: const TextStyle(fontSize: 14)),
                        value: _interceptResponse,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        visualDensity: const VisualDensity(vertical: -4),
                        onChanged: (val) {
                          setState(() {
                            _interceptResponse = val!;
                          });
                        },
                      )),
                      Expanded(child: SizedBox()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) {
              CustomToast.error("URL ${localizations.cannotBeEmpty}").show(context, alignment: Alignment.topCenter);
              return;
            }

            rule.name = nameInput.text;
            rule.url = urlInput.text;
            rule.method = _method;
            rule.interceptRequest = _interceptRequest;
            rule.interceptResponse = _interceptResponse;
            Navigator.pop(context, rule);
          },
          child: Text(localizations.save),
        ),
      ],
    );
  }

  Widget textField(String label, TextEditingController controller, String hint,
      {bool required = false, FormFieldSetter<String>? onSaved}) {
    return Row(children: [
      SizedBox(width: 60, child: Text(label)),
      Expanded(
          child: TextFormField(
        controller: controller,
        style: const TextStyle(fontSize: 14),
        validator: (val) => val?.isNotEmpty == true || !required ? null : "",
        onSaved: onSaved,
        decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            errorStyle: const TextStyle(height: 0, fontSize: 0),
            focusedBorder: focusedBorder(),
            isDense: true,
            border: const OutlineInputBorder()),
      ))
    ]);
  }

  InputBorder focusedBorder() {
    return OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2));
  }
}
