/*
 * 上报服务器配置页面
 */
import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/components/manager/report_server_manager.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';

import '../../../l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

// 以弹框的方式展示上报服务器管理
Future<void> showReportServersDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 570,
        height: 560,
        child: const ReportServersPage(),
      ),
    ),
  );
}

class ReportServersPage extends StatefulWidget {
  const ReportServersPage({super.key});

  @override
  State<ReportServersPage> createState() => _ReportServersPageState();
}

class _ReportServersPageState extends State<ReportServersPage> {
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
    final list = manager.servers;
    setState(() {
      _servers = List.of(list);
      _loading = false;
    });
  }

  InputBorder focusedBorder() {
    return OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2));
  }

  // 统一的新增/编辑弹窗
  Future<ReportServer?> _showServerDialog({ReportServer? initial}) async {
    final nameCtrl = TextEditingController(text: initial?.name ?? '');
    final matchUrlCtrl = TextEditingController(text: initial?.matchUrl ?? '');
    final serverUrlCtrl = TextEditingController(text: initial?.serverUrl ?? '');
    String compression = initial?.compression ?? 'none';
    bool enabled = initial?.enabled ?? true;

    // 紧凑的 Outline 输入框装饰
    InputDecoration dec({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 12),
        errorStyle: const TextStyle(height: 0, fontSize: 0),
        focusedBorder: focusedBorder(),
        isDense: true,
        border: const OutlineInputBorder());

    Widget labeled(String label, Widget field, {bool expanded = true}) => Row(
          children: [
            SizedBox(width: AppLocalizations.of(context)!.localeName == 'en' ? 95 : 85, child: Text(label)),
            const SizedBox(width: 12),
            expanded ? Expanded(child: field) : field,
          ],
        );

    final formKey = GlobalKey<FormState>();

    final result = await showDialog<ReportServer>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(initial == null ? localizations.addReportServer : localizations.editReportServer,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          content: Form(
              key: formKey,
              child: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      labeled(
                        '${localizations.name}: ',
                        TextField(controller: nameCtrl, decoration: dec(hint: localizations.pleaseEnter)),
                      ),
                      const SizedBox(height: 12),
                      labeled(
                        '${localizations.match} URL: ',
                        TextFormField(
                            controller: matchUrlCtrl,
                            keyboardType: TextInputType.url,
                            validator: (val) => val?.isNotEmpty == true ? null : "",
                            decoration: dec(hint: 'https://example.com/api/*')),
                      ),
                      const SizedBox(height: 12),
                      labeled(
                        '${localizations.serverUrl}: ',
                        TextFormField(
                            controller: serverUrlCtrl,
                            keyboardType: TextInputType.url,
                            validator: (val) => val?.isNotEmpty == true ? null : "",
                            decoration: dec(hint: 'http://example.com/report')),
                      ),
                      const SizedBox(height: 12),
                      labeled(
                          '${localizations.compression}: ',
                          expanded: false,
                          SizedBox(
                            width: 100,
                            child: DropdownButtonFormField<String>(
                              // use `value` for compatibility with older SDKs
                              value: compression,
                              decoration: dec(),
                              isDense: true,
                              items: [
                                DropdownMenuItem(value: 'none', child: Text(localizations.compressionNone)),
                                DropdownMenuItem(value: 'gzip', child: Text("GZIP")),
                              ],
                              onChanged: (v) => compression = v ?? 'none',
                            ),
                          )),
                      const SizedBox(height: 12),
                      labeled(
                        '${localizations.enable}: ',
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SwitchWidget(value: enabled, scale: 0.83, onChanged: (v) => enabled = v),
                        ),
                      ),
                    ],
                  ),
                ),
              )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text(localizations.cancel),
            ),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState as FormState).validate()) {
                  FlutterToastr.show("${localizations.serverUrl} ${localizations.cannotBeEmpty}", context,
                      position: FlutterToastr.top);
                  return;
                }

                final matchUrl = matchUrlCtrl.text.trim();
                var serverUrl = serverUrlCtrl.text.trim();
                // 修复此前的前缀判断逻辑：仅当不以 http/https 开头时补全
                if (!serverUrl.startsWith('http://') && !serverUrl.startsWith('https://')) {
                  serverUrl = 'http://$serverUrl';
                }

                final server = ReportServer(
                  name: nameCtrl.text.trim(),
                  matchUrl: matchUrl,
                  serverUrl: serverUrl,
                  enabled: enabled,
                  compression: compression,
                );
                Navigator.pop(ctx, server);
              },
              child: Text(localizations.save),
            ),
          ],
        );
      },
    );

    return result;
  }

  Future<void> _addServerDialog() async {
    final server = await _showServerDialog();
    if (server != null) {
      final manager = await ReportServerManager.instance;
      await manager.add(server);
      await _load();
    }
  }

  Future<void> _editServerDialog(int index) async {
    final initial = _servers[index];
    final server = await _showServerDialog(initial: initial);
    if (server != null) {
      final manager = await ReportServerManager.instance;
      await manager.update(index, server);
      setState(() => _servers[index] = server);
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
        automaticallyImplyLeading: false,
        title: Text(localizations.reportServers),
        centerTitle: true,
        actions: [

          TextButton.icon(
            label: Text(localizations.newBuilt),
            onPressed: _addServerDialog,
            icon: const Icon(Icons.add),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: localizations.useGuide,
            onPressed: _openGuide,
            icon: const Icon(Icons.help_outline,size: 21),
          ),
          IconButton(
            tooltip: localizations.close,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close, size: 22),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _servers.isEmpty
              ? Center(child: Text(localizations.emptyData))
              : Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 38,
                        dataRowMinHeight: 40,
                        dataRowMaxHeight: 48,
                        horizontalMargin: 12,
                        showBottomBorder: true,
                        dividerThickness: 0.26,
                        columnSpacing: 8,
                        columns: [
                          DataColumn(label: Center(child: Text(localizations.name))),
                          DataColumn(label: Center(child: Text(localizations.enable))),
                          DataColumn(label: Center(child: Text('${localizations.match} URL'))),
                          DataColumn(label: Center(child: Text(localizations.serverUrl))),
                          DataColumn(label: Center(child: Text(localizations.action))),
                        ],
                        rows: [
                          for (final entry in _servers.asMap().entries)
                            DataRow(cells: [
                              DataCell(
                                  SizedBox(
                                      width: 65,
                                      child: Text(
                                        entry.value.name.isEmpty ? '-' : entry.value.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.fade,
                                      )),
                                  onTap: () => _editServerDialog(entry.key)),
                              DataCell(Center(
                                  child: SizedBox(
                                      width: 45,
                                      child: SwitchWidget(
                                        value: entry.value.enabled,
                                        scale: 0.73,
                                        onChanged: (v) async {
                                          final manager = await ReportServerManager.instance;
                                          await manager.toggleEnabled(entry.key, v);
                                          setState(() => _servers[entry.key] = entry.value.copyWith(enabled: v));
                                        },
                                      )))),
                              DataCell(
                                  SizedBox(
                                    width: 155,
                                    child: Tooltip(
                                      message: entry.value.matchUrl,
                                      child: Text(entry.value.matchUrl, overflow: TextOverflow.ellipsis, maxLines: 1),
                                    ),
                                  ),
                                  onTap: () => _editServerDialog(entry.key)),
                              DataCell(
                                  SizedBox(
                                    width: 155,
                                    child: Tooltip(
                                      message: entry.value.serverUrl,
                                      child: Text(entry.value.serverUrl, overflow: TextOverflow.ellipsis, maxLines: 1),
                                    ),
                                  ),
                                  onTap: () => _editServerDialog(entry.key)),
                              DataCell(Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: localizations.edit,
                                      onPressed: () => _editServerDialog(entry.key),
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                    ),
                                    IconButton(
                                      tooltip: localizations.delete,
                                      onPressed: () => _confirmDelete(entry.key),
                                      icon: const Icon(Icons.delete_outline, size: 18),
                                    ),
                                  ],
                                ),
                              )),
                            ])
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}
