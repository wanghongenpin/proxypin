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
import 'package:proxypin/ui/component/proxy_port_setting.dart';
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

import '../../component/widgets.dart';
import '../setting/proxy.dart';
import '../setting/request_map.dart';

/// @author wanghongen
/// 2024/9/30
class ConfigPage extends StatefulWidget {
  final ProxyServer proxyServer;

  const ConfigPage({super.key, required this.proxyServer});

  @override
  State<StatefulWidget> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  late ProxyServer proxyServer = widget.proxyServer;
  late HistoryTask historyTask;

  @override
  void initState() {
    super.initState();
    historyTask = HistoryTask.ensureInstance(proxyServer.configuration, MobileApp.container);
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    Color color = Theme.of(context).colorScheme.primary.withValues(alpha: 0.85);

    Widget section(List<Widget> tiles) => Card(
          color: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
              side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.13)),
              borderRadius: BorderRadius.circular(10)),
          child: Column(children: tiles),
        );

    Widget arrow = const Icon(Icons.arrow_forward_ios, size: 16);

    return Scaffold(
        appBar: PreferredSize(
            preferredSize: const Size.fromHeight(42),
            child: AppBar(
              title: Text(localizations.config, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
              centerTitle: true,
            )),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            section([
              ListTile(
                  leading: Icon(Icons.favorite_outline, color: color),
                  title: Text(localizations.favorites),
                  trailing: arrow,
                  onTap: () => navigator(context, MobileFavorites(proxyServer: proxyServer))),
              Divider(height: 0, thickness: 0.3, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
              ListTile(
                leading: Icon(Icons.history, color: color),
                title: Text(localizations.history),
                trailing: arrow,
                onTap: () => navigator(context,
                    MobileHistory(proxyServer: proxyServer, container: MobileApp.container, historyTask: historyTask)),
              ),
            ]),
            const SizedBox(height: 12),
            section([
              ListTile(
                  title: Text(localizations.hosts),
                  leading: Icon(Icons.domain, color: color),
                  trailing: arrow,
                  onTap: () async {
                    var hostsManager = await HostsManager.instance;
                    if (context.mounted) {
                      navigator(context, HostsPage(hostsManager: hostsManager));
                    }
                  }),
              Divider(height: 0, thickness: 0.3, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
              ListTile(
                  title: Text(localizations.requestBlock),
                  leading: Icon(Icons.block_flipped, color: color),
                  trailing: arrow,
                  onTap: () async {
                    var requestBlockManager = await RequestBlockManager.instance;
                    if (context.mounted) {
                      navigator(context, MobileRequestBlock(requestBlockManager: requestBlockManager));
                    }
                  }),
              Divider(height: 0, thickness: 0.3, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
              ListTile(
                  title: Text(localizations.requestRewrite),
                  leading: Icon(Icons.edit_outlined, color: color),
                  trailing: arrow,
                  onTap: () async {
                    var requestRewrites = await RequestRewriteManager.instance;
                    if (context.mounted) {
                      navigator(context, MobileRequestRewrite(requestRewrites: requestRewrites));
                    }
                  }),
              Divider(height: 0, thickness: 0.3, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
              ListTile(
                  title: Text(localizations.requestMap),
                  leading: Icon(Icons.swap_horiz_outlined, color: color),
                  trailing: arrow,
                  onTap: () => navigator(context, MobileRequestMapPage())),
              Divider(height: 0, thickness: 0.3, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
              ListTile(
                  title: Text(localizations.script),
                  leading: Icon(Icons.javascript_outlined, color: color),
                  trailing: arrow,
                  onTap: () => navigator(context, const MobileScript())),
            ]),
            const SizedBox(height: 16)
          ],
        ));
  }
}

void navigator(BuildContext context, Widget widget) async {
  if (context.mounted) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (BuildContext context) => widget),
    );
  }
}

class SettingPage extends StatelessWidget {
  final ProxyServer proxyServer;
  final AppConfiguration appConfiguration;

  const SettingPage({super.key, required this.proxyServer, required this.appConfiguration});

  @override
  Widget build(BuildContext context) {
    final configuration = proxyServer.configuration;

    AppLocalizations localizations = AppLocalizations.of(context)!;
    bool isEn = appConfiguration.language?.languageCode == 'en';

    Widget section(List<Widget> tiles) => Card(
          color: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
              side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.13)),
              borderRadius: BorderRadius.circular(10)),
          child: Column(children: tiles),
        );

    return Scaffold(
        appBar: PreferredSize(
            preferredSize: const Size.fromHeight(42),
            child: AppBar(
              title: Text(localizations.setting, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
              centerTitle: true,
            )),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          section([
            ListTile(
                title: Text(localizations.httpsProxy),
                trailing: const Icon(Icons.keyboard_arrow_right),
                onTap: () => navigator(context, MobileSslWidget(proxyServer: proxyServer))),
            Divider(height: 0, thickness: 0.3, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
            ListTile(
                title: Text(localizations.filter),
                trailing: const Icon(Icons.keyboard_arrow_right),
                onTap: () => navigator(context, FilterMenu(proxyServer: proxyServer))),
          ]),
          const SizedBox(height: 12),
          // Port and switches
          Card(
              color: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.13)),
                  borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                PortWidget(
                    proxyServer: proxyServer,
                    title: '${localizations.proxy}${isEn ? ' ' : ''}${localizations.port}',
                    textStyle: const TextStyle(fontSize: 16)),
                Divider(height: 0, thickness: 0.3, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                ListTile(
                    title: const Text("SOCKS5"),
                    trailing: SwitchWidget(
                        value: configuration.enableSocks5,
                        scale: 0.8,
                        onChanged: (value) {
                          configuration.enableSocks5 = value;
                          proxyServer.configuration.flushConfig();
                        })),
                Divider(height: 0, thickness: 0.3, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                ListTile(
                    title: Text(localizations.enabledHTTP2),
                    trailing: SwitchWidget(
                        value: configuration.enabledHttp2,
                        scale: 0.8,
                        onChanged: (value) {
                          configuration.enabledHttp2 = value;
                          proxyServer.configuration.flushConfig();
                        })),
                Divider(height: 0, thickness: 0.3, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                ListTile(
                    title: Text(localizations.externalProxy),
                    trailing: const Icon(Icons.keyboard_arrow_right),
                    onTap: () {
                      showDialog(
                          context: context,
                          builder: (_) => ExternalProxyDialog(configuration: proxyServer.configuration));
                    }),
              ])),
          const SizedBox(height: 12),
          section([
            ListTile(
                title: Text(localizations.setting),
                trailing: const Icon(Icons.keyboard_arrow_right),
                onTap: () =>
                    navigator(context, Preference(proxyServer: proxyServer, appConfiguration: appConfiguration))),
            Divider(height: 0, thickness: 0.3, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
            ListTile(
                title: Text(localizations.about),
                trailing: const Icon(Icons.keyboard_arrow_right),
                onTap: () => navigator(context, const About())),
          ]),
          const SizedBox(height: 8),
        ]));
  }
}
