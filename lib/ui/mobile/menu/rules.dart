/*
 * Copyright 2023 Hongen Wang All rights reserved.
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

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/request_block_manager.dart';
import 'package:proxypin/network/components/manager/request_breakpoint_manager.dart';
import 'package:proxypin/network/components/manager/request_crypto_manager.dart';
import 'package:proxypin/network/components/manager/request_map_manager.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/components/manager/script_manager.dart';
import 'package:proxypin/ui/mobile/setting/request_block.dart';
import 'package:proxypin/ui/mobile/setting/request_breakpoint.dart';
import 'package:proxypin/ui/mobile/setting/request_crypto.dart';
import 'package:proxypin/ui/mobile/setting/request_map.dart';
import 'package:proxypin/ui/mobile/setting/request_rewrite.dart';
import 'package:proxypin/ui/mobile/setting/script.dart';

/// 移动端「规则」tab：流量控制状态总览，点击 push 到现有页面（页面零改动）
class MobileRulesPage extends StatefulWidget {
  const MobileRulesPage({super.key});

  @override
  State<MobileRulesPage> createState() => _MobileRulesPageState();
}

class _MobileRulesPageState extends State<MobileRulesPage> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  RequestBlockManager? _blockManager;
  RequestRewriteManager? _rewriteManager;
  RequestMapManager? _mapManager;
  RequestCryptoManager? _cryptoManager;
  ScriptManager? _scriptManager;
  RequestBreakpointManager? _breakpointManager;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    var block = await RequestBlockManager.instance;
    var rewrite = await RequestRewriteManager.instance;
    var map = await RequestMapManager.instance;
    var crypto = await RequestCryptoManager.instance;
    var script = await ScriptManager.instance;
    var breakpoint = await RequestBreakpointManager.instance;
    if (!mounted) return;
    setState(() {
      _blockManager = block;
      _rewriteManager = rewrite;
      _mapManager = map;
      _cryptoManager = crypto;
      _scriptManager = script;
      _breakpointManager = breakpoint;
    });
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);

    var rows = <Widget>[
      _ruleRow(
          icon: Icons.block_flipped,
          title: localizations.requestBlock,
          desc: localizations.requestBlockDesc,
          status: _ruleStatus(_blockManager?.enabled, _blockManager?.list.length),
          onTap: () => _open(() async =>
              MobileRequestBlock(requestBlockManager: _blockManager ?? await RequestBlockManager.instance))),
      _ruleRow(
          icon: Icons.edit_outlined,
          title: localizations.requestRewrite,
          desc: localizations.requestRewriteDesc,
          status: _ruleStatus(_rewriteManager?.enabled, _rewriteManager?.rules.length),
          onTap: () => _open(() async =>
              MobileRequestRewrite(requestRewrites: _rewriteManager ?? await RequestRewriteManager.instance))),
      _ruleRow(
          icon: Icons.swap_horiz_outlined,
          title: localizations.requestMap,
          desc: localizations.requestMapDesc,
          status: _ruleStatus(_mapManager?.enabled, _mapManager?.rules.length),
          onTap: () => _open(() async => MobileRequestMapPage())),
      _ruleRow(
          icon: Icons.lock_outline,
          title: localizations.requestCrypto,
          desc: localizations.requestCryptoDesc,
          status: _ruleStatus(_cryptoManager?.enabled, _cryptoManager?.rules.length),
          onTap: () => _open(() async => const MobileRequestCryptoPage())),
      _ruleRow(
          icon: Icons.javascript_outlined,
          title: localizations.script,
          desc: localizations.scriptDesc,
          status: _ruleStatus(_scriptManager?.enabled, _scriptManager?.list.length, isScript: true),
          onTap: () => _open(() async => const MobileScript())),
      _ruleRow(
          icon: Icons.bug_report_outlined,
          title: localizations.breakpoint,
          desc: localizations.breakpointDesc,
          status: _ruleStatus(_breakpointManager?.enabled, _breakpointManager?.list.length),
          onTap: () => _open(() async =>
              MobileRequestBreakpointPage(manager: _breakpointManager ?? await RequestBreakpointManager.instance))),
    ];

    var children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(Padding(
            padding: const EdgeInsets.only(left: 49),
            child: Divider(height: 0, thickness: 0.3, color: theme.dividerColor.withValues(alpha: 0.22))));
      }
      children.add(rows[i]);
    }

    return Scaffold(
        appBar: PreferredSize(
            preferredSize: const Size.fromHeight(42),
            child: AppBar(
              title:
                  Text(localizations.trafficControl, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
              centerTitle: true,
            )),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          Card(
              color: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.13)),
                  borderRadius: BorderRadius.circular(10)),
              child: Column(children: children)),
        ]));
  }

  String _ruleStatus(bool? enabled, int? count, {bool isScript = false}) {
    if (enabled != true) {
      return localizations.notEnabled;
    }
    return isScript ? localizations.statusEnabledScripts(count ?? 0) : localizations.statusEnabledRules(count ?? 0);
  }

  Widget _ruleRow(
      {required IconData icon,
      required String title,
      required String desc,
      required String status,
      required VoidCallback onTap}) {
    var theme = Theme.of(context);
    var on = status != localizations.notEnabled;
    return InkWell(
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(icon, size: 21, color: theme.colorScheme.primary.withValues(alpha: 0.85)),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant)),
              ])),
              const SizedBox(width: 10),
              Text(status,
                  style: TextStyle(
                      fontSize: 11.5, color: on ? const Color(0xFF1F8B4C) : theme.colorScheme.onSurfaceVariant)),
              Icon(Icons.arrow_forward_ios, size: 14, color: theme.colorScheme.onSurfaceVariant),
            ])));
  }

  /// 打开对应页面（异步构建，管理器未加载完成时先加载），返回后刷新状态
  Future<void> _open(Future<Widget> Function() builder) async {
    var page = await builder();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (context) => page));
    _reload();
  }
}
