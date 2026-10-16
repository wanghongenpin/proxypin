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

class MobileClientCertPage extends StatefulWidget {
  const MobileClientCertPage({super.key});

  @override
  State<MobileClientCertPage> createState() => _MobileClientCertPageState();
}

class _MobileClientCertPageState extends State<MobileClientCertPage> {
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

  Future<void> _addCert() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['p12', 'pfx']);
    if (file == null || !mounted) return;

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MobileClientCertEditPage(file: file)),
    );

    if (result == true && mounted) {
      FlutterToastr.show(localizations.success, context);
      setState(() {});
    }
  }

  Future<void> _editCert(ClientCertItem item) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MobileClientCertEditPage(item: item)),
    );
    if (result == true && mounted) setState(() {});
  }

  // 长按菜单
  void _showMenus(ClientCertItem item) {
    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        enableDrag: true,
        builder: (context) {
          return Wrap(alignment: WrapAlignment.center, children: [
            BottomSheetItem(text: localizations.edit, onPressed: () => _editCert(item)),
            const Divider(thickness: 0.5, height: 1),
            BottomSheetItem(
                text: item.enabled ? localizations.disabled : localizations.enable,
                onPressed: () async {
                  item.enabled = !item.enabled;
                  await _manager!.flushConfig();
                  setState(() {});
                }),
            const Divider(thickness: 0.5, height: 1),
            BottomSheetItem(
                text: localizations.delete,
                onPressed: () {
                  showConfirmDialog(context, onConfirm: () async {
                    await _manager!.remove(item);
                    setState(() {});
                  });
                }),
            Container(color: Theme.of(context).hoverColor, height: 8),
            TextButton(
              child: Container(
                  height: 45,
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(localizations.cancel, textAlign: TextAlign.center)),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ]);
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.clientCertificate, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: localizations.newBuilt,
            onPressed: _addCert,
            icon: const Icon(Icons.add, size: 26),
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _manager!.list.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.verified_user_outlined, size: 52, color: Colors.grey.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text(localizations.emptyData, style: TextStyle(color: Colors.grey.withValues(alpha: 0.8))),
                ]))
              : ListView.separated(
                  itemCount: _manager!.list.length,
                  separatorBuilder: (_, __) => const Divider(height: 0, thickness: 0.3),
                  itemBuilder: (ctx, idx) {
                    final item = _manager!.list[idx];
                    final expired = item.isExpired;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      leading: SizedBox(
                          width: 32,
                          child: SwitchWidget(
                              value: item.enabled,
                              scale: 0.8,
                              onChanged: (v) async {
                                item.enabled = v;
                                await _manager!.flushConfig();
                                setState(() {});
                              })),
                      title: Text(item.name?.isNotEmpty == true ? item.name! : item.host,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item.host, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('${localizations.expires} ${_fmtDate(item.notAfter)}',
                            style: TextStyle(fontSize: 12, color: expired ? Colors.red : Colors.grey)),
                      ]),
                      onTap: () => _editCert(item),
                      onLongPress: () => _showMenus(item),
                    );
                  },
                ),
    );
  }
}

class MobileClientCertEditPage extends StatefulWidget {
  final PlatformFile? file;
  final ClientCertItem? item;

  const MobileClientCertEditPage({super.key, this.file, this.item});

  @override
  State<MobileClientCertEditPage> createState() => _MobileClientCertEditPageState();
}

class _MobileClientCertEditPageState extends State<MobileClientCertEditPage> {
  late TextEditingController _nameCtrl;
  late TextEditingController _hostCtrl;
  late TextEditingController _passwordCtrl;

  final _formKey = GlobalKey<FormState>();

  X509CertificateData? _certDetails;

  bool get isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.item?.name ?? '');
    _hostCtrl = TextEditingController(text: widget.item?.host ?? '');
    _passwordCtrl = TextEditingController();
    _initCertInfo();
  }

  /// 编辑时读取证书详情; 导入时尝试无密码静默解析, 用 CN 预填名称
  Future<void> _initCertInfo() async {
    if (isEdit) {
      final details = await widget.item!.certDetails();
      if (mounted) setState(() => _certDetails = details);
      return;
    }

    try {
      final bytes = await widget.file!.readAsBytes();
      final pems = Pkcs12.parsePkcs12(bytes);
      if (pems.length > 1) {
        final details = X509Utils.x509CertificateFromPem(pems[1]);
        if (mounted) {
          setState(() => _certDetails = details);
          final cn = details.subject['2.5.4.3'];
          if (_nameCtrl.text.isEmpty && cn?.isNotEmpty == true) {
            _nameCtrl.text = cn!;
          }
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  InputDecoration dec({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        focusedBorder:
            OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)),
        isDense: true,
        border: const OutlineInputBorder(),
      );

  Widget labeled(String label, Widget field) => Row(
        children: [
          SizedBox(width: AppLocalizations.of(context)!.localeName == 'en' ? 95 : 85, child: Text(label)),
          const SizedBox(width: 12),
          Expanded(child: field),
        ],
      );

  Future<void> _onSave() async {
    final localizations = AppLocalizations.of(context)!;
    if (!isEdit) {
      if (!(_formKey.currentState as FormState).validate()) {
        FlutterToastr.show("${localizations.domain} ${localizations.cannotBeEmpty}", context,
            position: FlutterToastr.top);
        return;
      }
      try {
        final manager = await ClientCertManager.instance;
        await manager.importPkcs12(
          await widget.file!.readAsBytes(),
          _passwordCtrl.text.isEmpty ? null : _passwordCtrl.text,
          host: _hostCtrl.text.trim(),
          name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        );
        if (mounted) Navigator.of(context).pop(true);
      } catch (e, st) {
        logger.e('import client cert error', error: e, stackTrace: st);
        if (mounted) FlutterToastr.show(localizations.importFailed, context);
      }
      return;
    }

    if (_hostCtrl.text.trim().isEmpty) {
      FlutterToastr.show("${localizations.domain} ${localizations.cannotBeEmpty}", context,
          position: FlutterToastr.top);
      return;
    }
    widget.item!.name = _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim();
    widget.item!.host = _hostCtrl.text.trim();
    await (await ClientCertManager.instance).flushConfig();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? localizations.edit : localizations.importClientCert),
        centerTitle: true,
        actions: [
          TextButton(onPressed: _onSave, child: Text(isEdit ? localizations.save : localizations.import)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                labeled(localizations.name, TextField(controller: _nameCtrl, decoration: dec())),
                const SizedBox(height: 12),
                labeled(
                  '${localizations.domain} *',
                  TextFormField(
                    controller: _hostCtrl,
                    keyboardType: TextInputType.url,
                    validator: (v) => v?.isNotEmpty == true ? null : '',
                    decoration: dec(hint: '*.example.com'),
                  ),
                ),
                if (!isEdit) ...[
                  const SizedBox(height: 12),
                  labeled(
                    localizations.password,
                    TextField(controller: _passwordCtrl, obscureText: true, decoration: dec()),
                  ),
                ],
                if (_certDetails != null) ...[
                  const SizedBox(height: 16),
                  const Divider(thickness: 0.5),
                  const SizedBox(height: 8),
                  _certInfo(_certDetails!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 证书信息, 样式对齐 mobile/setting/ssl.dart 的 _certDetails
  Widget _certInfo(X509CertificateData details) {
    final localizations = AppLocalizations.of(context)!;
    final infoLabelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]);
    final infoValueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500);

    Widget kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: infoLabelStyle),
          const SizedBox(width: 12),
          Expanded(child: SelectableText(v, style: infoValueStyle, textAlign: TextAlign.right)),
        ]));

    return Column(children: [
      kv('Name', details.subject['2.5.4.3'] ?? '-'),
      kv('Issuer', details.issuer['2.5.4.3'] ?? '-'),
      kv(localizations.expires, details.validity.notAfter.toLocal().toString().split(' ').first),
      kv('Fingerprint', details.sha1Thumbprint ?? '-'),
    ]);
  }
}
