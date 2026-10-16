/*
 * Copyright 2026 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/client_cert_manager.dart';
import 'package:proxypin/network/util/cert/cert_data.dart';
import 'package:proxypin/network/util/cert/pkcs12.dart';
import 'package:proxypin/network/util/cert/x509.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';

/// 以弹框方式展示客户端证书管理
Future<void> showClientCertDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const ClientCertDialog(),
  );
}

class ClientCertDialog extends StatefulWidget {
  const ClientCertDialog({super.key});

  @override
  State<ClientCertDialog> createState() => _ClientCertDialogState();
}

class _ClientCertDialogState extends State<ClientCertDialog> {
  ClientCertManager? _manager;
  bool _loading = true;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final manager = await ClientCertManager.instance;
    if (!mounted) return;
    setState(() {
      _manager = manager;
      _loading = false;
    });
  }

  String _fmtDate(int? millis) {
    if (millis == null) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.only(left: 20, top: 10, right: 15),
      contentPadding: const EdgeInsets.symmetric(horizontal: 15),
      scrollable: true,
      title: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Expanded(child: SizedBox()),
        Text(localizations.clientCertificate, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        const Expanded(child: SizedBox()),
        const Align(alignment: Alignment.topRight, child: CloseButton())
      ]),
      content: SizedBox(
        width: 560,
        height: 480,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                Row(children: [
                  Container(width: 15),
                  Text(localizations.enable),
                  const SizedBox(width: 10),
                  SwitchWidget(
                      scale: 0.8,
                      value: _manager!.enabled,
                      onChanged: (value) async {
                        _manager!.enabled = value;
                        await _manager!.flushConfig();
                        setState(() {});
                      }),
                  const Expanded(child: SizedBox()),
                  TextButton.icon(
                      icon: const Icon(Icons.add, size: 18), onPressed: _addCert, label: Text(localizations.newBuilt)),
                  const SizedBox(width: 5),
                ]),
                const SizedBox(height: 8),
                Container(
                    height: 405,
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.withValues(alpha: 0.2))),
                    child: Column(children: [
                      const SizedBox(height: 5),
                      Row(children: [
                        Container(width: 15),
                        SizedBox(
                            width: 50, child: Text(localizations.enable, style: const TextStyle(fontSize: 14))),
                        Container(width: 15),
                        SizedBox(width: 140, child: Text(localizations.name, style: const TextStyle(fontSize: 14))),
                        Container(width: 15),
                        Expanded(child: Text(localizations.domain, style: const TextStyle(fontSize: 14))),
                        Container(width: 15),
                        SizedBox(width: 90, child: Text(localizations.expires, style: const TextStyle(fontSize: 14))),
                      ]),
                      const Divider(thickness: 0.5),
                      Expanded(
                          child: _manager!.list.isEmpty
                              ? Center(
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.verified_user_outlined, size: 46, color: Colors.grey.withValues(alpha: 0.5)),
                                  const SizedBox(height: 10),
                                  Text(localizations.emptyData, style: TextStyle(color: Colors.grey.withValues(alpha: 0.8))),
                                ]))
                              : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _manager!.list.length,
                                  padding: const EdgeInsets.only(right: 10),
                                  itemBuilder: (_, index) => _row(_manager!.list[index], index.isEven)))
                    ])),
              ]),
      ),
    );
  }

  Widget _row(ClientCertItem item, bool isEven) {
    var primaryColor = Theme.of(context).colorScheme.primary;
    final expired = item.isExpired;

    return InkWell(
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        hoverColor: primaryColor.withValues(alpha: 0.3),
        onSecondaryTapDown: (details) => _showMenus(details, item),
        onDoubleTap: () => _editCert(item),
        onTap: () {},
        child: Container(
            color: isEven ? Colors.grey.withValues(alpha: 0.1) : null,
            height: 35,
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(
                  width: 50,
                  child: SwitchWidget(
                      scale: 0.6,
                      value: item.enabled,
                      onChanged: (val) async {
                        item.enabled = val;
                        await _manager!.flushConfig();
                        setState(() {});
                      })),
              Container(width: 15),
              SizedBox(
                  width: 140,
                  child: Tooltip(
                      message: item.name ?? '',
                      child: Text(item.name?.isNotEmpty == true ? item.name! : '-',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)))),
              Container(width: 15),
              Expanded(
                  child: Tooltip(
                      message: item.host,
                      child: Text(item.host,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)))),
              Container(width: 15),
              SizedBox(
                  width: 90,
                  child: Tooltip(
                      message: expired ? localizations.expired : '',
                      child: Text(_fmtDate(item.notAfter),
                          style: TextStyle(
                              fontSize: 13, color: expired ? Colors.red : Colors.grey.withValues(alpha: 0.9))))),
            ])));
  }

  // 右键菜单
  void _showMenus(TapDownDetails details, ClientCertItem item) {
    showContextMenu(context, details.globalPosition, items: [
      PopupMenuItem(height: 35, child: Text(localizations.edit), onTap: () => _editCert(item)),
      PopupMenuItem(
          height: 35,
          child: item.enabled ? Text(localizations.disabled) : Text(localizations.enable),
          onTap: () async {
            item.enabled = !item.enabled;
            await _manager!.flushConfig();
            setState(() {});
          }),
      const PopupMenuDivider(),
      PopupMenuItem(height: 35, child: Text(localizations.delete), onTap: () => _confirmDelete(item)),
    ]);
  }

  Future<void> _confirmDelete(ClientCertItem item) async {
    showConfirmDialog(context, onConfirm: () async {
      await _manager!.remove(item);
      setState(() {});
    });
  }

  InputBorder _focusedBorder() {
    return OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2));
  }

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        errorStyle: const TextStyle(height: 0, fontSize: 0),
        focusedBorder: _focusedBorder(),
        isDense: true,
        border: const OutlineInputBorder(),
      );

  Widget _buildLabel(String label, Widget field) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: localizations.localeName == 'en' ? 108 : 88, child: Text(label)),
          const SizedBox(width: 12),
          Expanded(child: field),
        ],
      );

  Future<void> _addCert() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['p12', 'pfx']);
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();

    // 尝试无密码静默解析, 用证书 CN 预填名称
    String? certName;
    try {
      final pems = Pkcs12.parsePkcs12(bytes);
      if (pems.length > 1) {
        certName = X509Utils.x509CertificateFromPem(pems[1]).subject['2.5.4.3'];
      }
    } catch (_) {}

    if (!mounted) return;

    final nameCtrl = TextEditingController(text: certName ?? '');
    final hostCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(localizations.importClientCert,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLabel(localizations.name, TextField(controller: nameCtrl, decoration: _inputDecoration())),
                  const SizedBox(height: 12),
                  _buildLabel('${localizations.domain} *',
                      TextFormField(
                          controller: hostCtrl,
                          keyboardType: TextInputType.url,
                          validator: (val) => val?.isNotEmpty == true ? null : '',
                          decoration: _inputDecoration(hint: '*.example.com'))),
                  const SizedBox(height: 12),
                  _buildLabel(localizations.password,
                      TextField(controller: passwordCtrl, obscureText: true, decoration: _inputDecoration())),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(localizations.cancel)),
            FilledButton(
              onPressed: () async {
                if (!(formKey.currentState as FormState).validate()) {
                  FlutterToastr.show("${localizations.domain} ${localizations.cannotBeEmpty}", context,
                      position: FlutterToastr.top);
                  return;
                }
                try {
                  await _manager!.importPkcs12(
                    bytes,
                    passwordCtrl.text.isEmpty ? null : passwordCtrl.text,
                    host: hostCtrl.text.trim(),
                    name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e, st) {
                  logger.e('import client cert error', error: e, stackTrace: st);
                  if (ctx.mounted) FlutterToastr.show(localizations.importFailed, ctx);
                }
              },
              child: Text(localizations.import),
            ),
          ],
        ),
      );

      if (result == true && mounted) {
        FlutterToastr.show(localizations.success, context);
        setState(() {});
      }
    } finally {
      nameCtrl.dispose();
      hostCtrl.dispose();
      passwordCtrl.dispose();
    }
  }

  Future<void> _editCert(ClientCertItem item) async {
    final nameCtrl = TextEditingController(text: item.name ?? '');
    final hostCtrl = TextEditingController(text: item.host);
    final certDetails = await item.certDetails();
    if (!mounted) return;

    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(localizations.edit, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLabel(localizations.name, TextField(controller: nameCtrl, decoration: _inputDecoration())),
                const SizedBox(height: 12),
                _buildLabel('${localizations.domain} *',
                    TextField(controller: hostCtrl, decoration: _inputDecoration(hint: '*.example.com'))),
                if (certDetails != null) ...[
                  const SizedBox(height: 16),
                  const Divider(thickness: 0.5),
                  const SizedBox(height: 8),
                  ..._certInfoRows(certDetails),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(localizations.cancel)),
            FilledButton(
              onPressed: () async {
                if (hostCtrl.text.trim().isEmpty) {
                  FlutterToastr.show("${localizations.domain} ${localizations.cannotBeEmpty}", context,
                      position: FlutterToastr.top);
                  return;
                }
                item.name = nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim();
                item.host = hostCtrl.text.trim();
                await _manager!.flushConfig();
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: Text(localizations.save),
            ),
          ],
        ),
      );

      if (result == true && mounted) setState(() {});
    } finally {
      nameCtrl.dispose();
      hostCtrl.dispose();
    }
  }

  /// 证书详情行, 样式对齐 pc_cert.dart
  List<Widget> _certInfoRows(X509CertificateData cert) {
    final infoLabelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]);
    final infoValueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500);

    Widget row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Text(label, style: infoLabelStyle),
          const SizedBox(width: 12),
          Expanded(child: SelectableText(value, style: infoValueStyle, textAlign: TextAlign.right)),
        ]));

    return [
      row('Name', cert.subject['2.5.4.3'] ?? '-'),
      row('Issuer', cert.issuer['2.5.4.3'] ?? '-'),
      row(localizations.expires, cert.validity.notAfter.toLocal().toString().split(' ').first),
      row('Fingerprint', cert.sha1Thumbprint ?? '-'),
    ];
  }
}
