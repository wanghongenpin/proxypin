/*
 * Copyright 2024 Hongen Wang All rights reserved.
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
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/components/manager/hosts_manager.dart';
import 'package:proxypin/network/components/manager/request_block_manager.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/storage/histories.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/mobile/menu/drawer.dart';
import 'package:proxypin/ui/mobile/setting/hosts.dart';
import 'package:proxypin/ui/mobile/setting/preference.dart';
import 'package:proxypin/ui/mobile/mobile.dart';
import 'package:proxypin/ui/mobile/request/favorite.dart';
import 'package:proxypin/ui/mobile/request/history.dart';
import 'package:proxypin/ui/mobile/setting/request_block.dart';
import 'package:proxypin/ui/mobile/setting/request_rewrite.dart';
import 'package:proxypin/ui/mobile/setting/script.dart';
import 'package:proxypin/ui/mobile/setting/ssl.dart';
import 'package:proxypin/ui/mobile/widgets/about.dart';

import '../setting/request_map.dart';

/// @author wanghongen
/// 2024/9/30
class MePage extends StatefulWidget {
  final ProxyServer proxyServer;

  const MePage({super.key, required this.proxyServer});

  @override
  State<StatefulWidget> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  late ProxyServer proxyServer = widget.proxyServer;

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    Color color = Theme.of(context).colorScheme.primary.withOpacity(0.85);

    return Scaffold(
        appBar: PreferredSize(
            preferredSize: const Size.fromHeight(42),
            child: AppBar(
              title: Text(localizations.me, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
              centerTitle: true,
            )),
        body: ListView(
          padding: const EdgeInsets.only(top: 5, left: 5),
          children: [
            const SizedBox(height: 10),
            ListTile(
                title: Text(localizations.httpsProxy),
                leading: Icon(proxyServer.enableSsl ? Icons.lock_open : Icons.https, color: color),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => navigator(context, MobileSslWidget(proxyServer: proxyServer))),
            const Divider(thickness: 0.35),
            ListTile(
                leading: Icon(Icons.favorite_outline, color: color),
                title: Text(localizations.favorites),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => navigator(context, MobileFavorites(proxyServer: proxyServer))),
            ListTile(
              leading: Icon(Icons.history, color: color),
              title: Text(localizations.history),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => navigator(
                  context,
                  MobileHistory(
                      proxyServer: proxyServer,
                      container: MobileApp.container,
                      historyTask: HistoryTask.ensureInstance(proxyServer.configuration, MobileApp.container))),
            ),
            const Divider(thickness: 0.35),
            ListTile(
                title: Text(localizations.filter),
                leading: Icon(Icons.filter_alt_outlined, color: color),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => navigator(context, FilterMenu(proxyServer: proxyServer))),
            ListTile(
                title: Text(localizations.hosts),
                leading: Icon(Icons.domain, color: color),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () async {
                  var hostsManager = await HostsManager.instance;
                  if (context.mounted) {
                    navigator(context, HostsPage(hostsManager: hostsManager));
                  }
                }),
            ListTile(
                title: Text(localizations.requestBlock),
                leading: Icon(Icons.block_flipped, color: color),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () async {
                  var requestBlockManager = await RequestBlockManager.instance;
                  if (context.mounted) {
                    navigator(context, MobileRequestBlock(requestBlockManager: requestBlockManager));
                  }
                }),
            ListTile(
                title: Text(localizations.requestRewrite),
                leading: Icon(Icons.edit_outlined, color: color),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () async {
                  var requestRewrites = await RequestRewriteManager.instance;
                  if (context.mounted) {
                    navigator(context, MobileRequestRewrite(requestRewrites: requestRewrites));
                  }
                }),
            ListTile(
                title: Text(localizations.requestMap),
                leading: Icon(Icons.swap_horiz_outlined, color: color),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => navigator(context, MobileRequestMapPage())),
            ListTile(
                title: Text(localizations.script),
                leading: Icon(Icons.javascript_outlined, color: color),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => navigator(context, const MobileScript())),
            ListTile(
                title: Text(localizations.setting),
                leading: Icon(Icons.settings_outlined, color: color),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => navigator(
                    context,
                    futureWidget(
                        AppConfiguration.instance,
                        (appConfiguration) =>
                            Preference(proxyServer: proxyServer, appConfiguration: appConfiguration)))),
            ListTile(
                title: Text(localizations.about),
                leading: Icon(Icons.info_outline, color: color),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => navigator(context, const About())),
            const SizedBox(height: 20)
          ],
        ));
  }

  void navigator(BuildContext context, Widget widget) async {
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (BuildContext context) => widget),
      );
    }
  }
}
