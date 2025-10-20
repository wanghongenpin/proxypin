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
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/components/manager/request_block_manager.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/storage/histories.dart';
import 'package:proxypin/ui/mobile/setting/request_map.dart';
import 'package:proxypin/ui/toolbox/toolbox.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/mobile/setting/preference.dart';
import 'package:proxypin/ui/mobile/request/favorite.dart';
import 'package:proxypin/ui/mobile/request/history.dart';
import 'package:proxypin/ui/mobile/setting/app_filter.dart';
import 'package:proxypin/ui/mobile/setting/filter.dart';
import 'package:proxypin/ui/mobile/setting/request_block.dart';
import 'package:proxypin/ui/mobile/setting/request_rewrite.dart';
import 'package:proxypin/ui/mobile/setting/script.dart';
import 'package:proxypin/ui/mobile/setting/ssl.dart';
import 'package:proxypin/ui/mobile/widgets/about.dart';
import 'package:proxypin/utils/listenable_list.dart';

///左侧抽屉
class DrawerWidget extends StatelessWidget {
  final ProxyServer proxyServer;
  final ListenableList<HttpRequest> container;
  final HistoryTask historyTask;

  DrawerWidget({super.key, required this.proxyServer, required this.container})
      : historyTask = HistoryTask.ensureInstance(proxyServer.configuration, container);

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    return Drawer(
        backgroundColor: Theme.of(context).cardColor,
        child: ListView(
          children: [
            DrawerHeader(
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white,
                      child: Center(
                          child: Image.asset(
                        'assets/icon_foreground.png',
                        width: 52,
                      ))),
                  const SizedBox(width: 12),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('ProxyPin', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(isCN ? "全平台开源免费抓包软件" : "Full platform open source free capture HTTP(S) traffic software",
                            style: Theme.of(context).textTheme.bodySmall)
                      ])
                ])),
            // Favorites & History
            ListTile(
                leading: const Icon(Icons.favorite),
                title: Text(localizations.favorites),
                onTap: () => navigator(context, MobileFavorites(proxyServer: proxyServer))),
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(localizations.history),
              onTap: () => navigator(
                  context, MobileHistory(proxyServer: proxyServer, container: container, historyTask: historyTask)),
            ),
            const Divider(thickness: 0.3, height: 0),
            ListTile(
                leading: const Icon(Icons.construction),
                title: Text(localizations.toolbox),
                onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (BuildContext context) {
                        return Scaffold(
                            appBar: AppBar(title: Text(localizations.toolbox), centerTitle: true),
                            body: Toolbox(proxyServer: proxyServer));
                      }),
                    )),
            ListTile(
                title: Text(localizations.httpsProxy),
                leading: proxyServer.enableSsl ? Icon(Icons.lock_open) : Icon(Icons.https),
                onTap: () => navigator(context, MobileSslWidget(proxyServer: proxyServer))),
            const Divider(thickness: 0.3, height: 0),
            ListTile(
                title: Text(localizations.filter),
                leading: const Icon(Icons.filter_alt_outlined),
                onTap: () => navigator(context, FilterMenu(proxyServer: proxyServer))),
            ListTile(
                title: Text(localizations.requestBlock),
                leading: const Icon(Icons.block_flipped),
                onTap: () async {
                  var requestBlockManager = await RequestBlockManager.instance;
                  if (context.mounted) {
                    navigator(context, MobileRequestBlock(requestBlockManager: requestBlockManager));
                  }
                }),
            ListTile(
                title: Text(localizations.requestRewrite),
                leading: const Icon(Icons.edit_outlined),
                onTap: () async {
                  var requestRewrites = await RequestRewriteManager.instance;
                  if (context.mounted) {
                    navigator(context, MobileRequestRewrite(requestRewrites: requestRewrites));
                  }
                }),
            ListTile(
                title: Text(localizations.requestMap),
                leading: Icon(Icons.swap_horiz_outlined),
                onTap: () => navigator(context, MobileRequestMapPage())),
            ListTile(
                title: Text(localizations.script),
                leading: const Icon(Icons.code),
                onTap: () => navigator(context, const MobileScript())),
            ListTile(
                title: Text(localizations.setting),
                leading: const Icon(Icons.settings),
                onTap: () => navigator(
                    context,
                    futureWidget(
                        AppConfiguration.instance,
                        (appConfiguration) =>
                            Preference(proxyServer: proxyServer, appConfiguration: appConfiguration)))),
            ListTile(
                title: Text(localizations.about),
                leading: const Icon(Icons.info_outline),
                onTap: () => navigator(context, const About())),
            const SizedBox(height: 20)
          ],
        ));
  }
}

///跳转页面
void navigator(BuildContext context, Widget widget) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (BuildContext context) {
      return widget;
    }),
  );
}

///抓包过滤菜单
class FilterMenu extends StatelessWidget {
  final ProxyServer proxyServer;

  const FilterMenu({super.key, required this.proxyServer});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return Scaffold(
        appBar: AppBar(title: Text(localizations.filter, style: const TextStyle(fontSize: 16)), centerTitle: true),
        body: Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
                color: Colors.transparent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.13)),
                    borderRadius: BorderRadius.circular(10)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(
                      title: Text(localizations.domainWhitelist),
                      trailing: const Icon(Icons.arrow_right),
                      onTap: () => navigator(
                          context,
                          MobileFilterWidget(
                              configuration: proxyServer.configuration, hostList: HostFilter.whitelist))),
                  Divider(height: 0, thickness: 0.4, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                  ListTile(
                      title: Text(localizations.domainBlacklist),
                      trailing: const Icon(Icons.arrow_right),
                      onTap: () => navigator(
                          context,
                          MobileFilterWidget(
                              configuration: proxyServer.configuration, hostList: HostFilter.blacklist))),
                  Platform.isIOS
                      ? const SizedBox()
                      : Column(mainAxisSize: MainAxisSize.min, children: [
                          Divider(
                              height: 0, thickness: 0.4, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                          ListTile(
                              title: Text(localizations.appWhitelist),
                              trailing: const Icon(Icons.arrow_right),
                              onTap: () => navigator(context, AppWhitelist(proxyServer: proxyServer))),
                          Divider(
                              height: 0, thickness: 0.4, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                          ListTile(
                              title: Text(localizations.appBlacklist),
                              trailing: const Icon(Icons.arrow_right),
                              onTap: () => navigator(context, AppBlacklist(proxyServer: proxyServer)))
                        ])
                ]))));
  }
}
