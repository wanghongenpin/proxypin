/*
 * Mobile report servers page
 */

import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/components/manager/report_server_manager.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/component/utils.dart';
import '../../../l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class ReportServersPageMobile extends StatefulWidget {
  const ReportServersPageMobile({super.key});

  @override
  State<ReportServersPageMobile> createState() => _ReportServersPageMobileState();
}

class _ReportServersPageMobileState extends State<ReportServersPageMobile> {
  List<ReportServer> _servers = [];
  bool _loading = true;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  Future<void> _openGuide() async {
    final locale = AppLocalizations.of(context)?.localeName ?? '';
    final cn = 'https://gitee.com/wanghongenpin/proxypin/wikis/%E4%B8%8A%E6%8A%A5%E6%9C%8D%E5%8A%A1%E5%99%A8';
    final en = 'https://github.com/wanghongenpin/proxypin/wiki/Report-Server';
    final url = (locale.startsWith('zh')) ? cn : en;
    final uri = Uri.parse(url);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        FlutterToastr.show('Open guide failed', context);
      }
    } catch (e) {
      FlutterToastr.show('Open guide failed: $e', context);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final manager = await ReportServerManager.instance;
    setState(() {
      _servers = List.of(manager.servers);
      _loading = false;
    });
  }

  Future<ReportServer?> _showServerDialog({ReportServer? initial}) async {
    // Push the edit page and return the created/edited ReportServer
    final result = await Navigator.of(context).push<ReportServer>(
      MaterialPageRoute(
        builder: (ctx) => ReportServerEditPageMobile(initial: initial),
      ),
    );

    return result;
  }

  Future<void> _addServer() async {
    final server = await _showServerDialog();
    if (server != null) {
      final manager = await ReportServerManager.instance;
      await manager.add(server);
      await _load();
    }
  }

  Future<void> _editServer(int index) async {
    final initial = _servers[index];
    final server = await _showServerDialog(initial: initial);
    if (server != null) {
      final manager = await ReportServerManager.instance;
      await manager.update(index, server);
      await _load();
    }
  }

  Future<void> _confirmDelete(int index) async {
    showConfirmDialog(context, onConfirm: () async {
      final manager = await ReportServerManager.instance;
      await manager.removeAt(index);
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.reportServers, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: localizations.useGuide,
            onPressed: _openGuide,
            icon: const Icon(Icons.help_outline, size: 22),
          ),
          IconButton(
            tooltip: localizations.add,
            onPressed: _addServer,
            icon: const Icon(Icons.add, size: 26),
          ),
          SizedBox(width: 5)
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _servers.isEmpty
              ? Center(child: Text(localizations.emptyData))
              : ListView.separated(
                  itemCount: _servers.length,
                  separatorBuilder: (_, __) => const Divider(height: 0, thickness: 0.3),
                  itemBuilder: (ctx, idx) {
                    final s = _servers[idx];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      leading: SizedBox(
                          width: 32,
                          child: Checkbox(
                              value: s.enabled,
                              onChanged: (v) async {
                                final manager = await ReportServerManager.instance;
                                await manager.toggleEnabled(idx, v == true);
                                await _load();
                              })),
                      title: Text(s.name.isEmpty ? '-' : s.name),
                      subtitle: Text(s.serverUrl),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // IconButton(
                          //     onPressed: () => _editServer(idx), icon: const Icon(Icons.edit_outlined, size: 23)),
                          IconButton(
                              onPressed: () => _confirmDelete(idx), icon: const Icon(Icons.delete_outline, size: 23)),
                        ],
                      ),
                      onTap: () => _editServer(idx),
                    );
                  },
                ),
    );
  }
}

// A standalone page for adding / editing a ReportServer on mobile.
class ReportServerEditPageMobile extends StatefulWidget {
  final ReportServer? initial;

  const ReportServerEditPageMobile({super.key, this.initial});

  @override
  State<ReportServerEditPageMobile> createState() => _ReportServerEditPageMobileState();
}

class _ReportServerEditPageMobileState extends State<ReportServerEditPageMobile> {
  late TextEditingController _nameCtrl;
  late TextEditingController _matchUrlCtrl;
  late TextEditingController _serverUrlCtrl;
  String _compression = 'none';
  bool _enabled = true;

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _nameCtrl = TextEditingController(text: init?.name ?? '');
    _matchUrlCtrl = TextEditingController(text: init?.matchUrl ?? '');
    _serverUrlCtrl = TextEditingController(text: init?.serverUrl ?? '');
    _compression = init?.compression ?? 'none';
    _enabled = init?.enabled ?? true;
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

  Widget labeled(String label, Widget field, {bool expanded = true}) => Row(
        children: [
          SizedBox(width: AppLocalizations.of(context)!.localeName == 'en' ? 95 : 85, child: Text(label)),
          const SizedBox(width: 12),
          expanded ? Expanded(child: field) : field,
        ],
      );

  void _onSave() {
    if (!(_formKey.currentState as FormState).validate()) {
      FlutterToastr.show(
          "${AppLocalizations.of(context)!.serverUrl} ${AppLocalizations.of(context)!.cannotBeEmpty}", context,
          position: FlutterToastr.top);
      return;
    }

    var serverUrl = _serverUrlCtrl.text.trim();
    if (!serverUrl.startsWith('http://') && !serverUrl.startsWith('https://')) {
      serverUrl = 'http://$serverUrl';
    }

    final server = ReportServer(
      name: _nameCtrl.text.trim(),
      matchUrl: _matchUrlCtrl.text.trim(),
      serverUrl: serverUrl,
      enabled: _enabled,
      compression: _compression,
    );

    Navigator.of(context).pop(server);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? localizations.addReportServer : localizations.editReportServer),
        centerTitle: true,
        actions: [
          TextButton(onPressed: _onSave, child: Text(localizations.save)),
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
                labeled('${localizations.name}: ',
                    TextField(controller: _nameCtrl, decoration: dec(hint: localizations.pleaseEnter))),
                const SizedBox(height: 12),
                labeled(
                  '${localizations.match} URL: ',
                  TextFormField(
                      controller: _matchUrlCtrl,
                      keyboardType: TextInputType.url,
                      validator: (v) => v?.isNotEmpty == true ? null : "",
                      decoration: dec(hint: 'https://example.com/api/*')),
                ),
                const SizedBox(height: 12),
                labeled(
                  '${localizations.serverUrl}: ',
                  TextFormField(
                      controller: _serverUrlCtrl,
                      keyboardType: TextInputType.url,
                      validator: (v) => v?.isNotEmpty == true ? null : "",
                      decoration: dec(hint: 'http://example.com/report')),
                ),
                const SizedBox(height: 12),
                labeled(
                  '${localizations.compression}: ',
                  expanded: false,
                  SizedBox(
                    width: 120,
                    child: DropdownButtonFormField<String>(
                      initialValue: _compression,
                      decoration: dec(),
                      items: [
                        DropdownMenuItem(value: 'none', child: Text(localizations.compressionNone)),
                        DropdownMenuItem(value: 'gzip', child: Text('GZIP')),
                      ],
                      onChanged: (v) => setState(() => _compression = v ?? 'none'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                labeled(
                  '${localizations.enable}: ',
                  Align(
                      alignment: Alignment.centerLeft,
                      child: SwitchWidget(value: _enabled, scale: 0.9, onChanged: (v) => setState(() => _enabled = v))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
