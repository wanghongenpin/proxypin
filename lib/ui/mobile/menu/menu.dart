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

import 'package:date_format/date_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/ui/mobile/mobile.dart';
import 'package:proxypin/ui/mobile/setting/app_filter.dart';
import 'package:proxypin/ui/mobile/setting/ssl.dart';
import 'package:proxypin/ui/mobile/widgets/highlight.dart';
import 'package:proxypin/ui/mobile/widgets/remote_device.dart';

/// +号菜单
class MoreMenu extends StatelessWidget {
  final ProxyServer proxyServer;
  final ValueNotifier<RemoteModel> remoteDevice;

  const MoreMenu({super.key, required this.proxyServer, required this.remoteDevice});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return PopupMenuButton(
      offset: const Offset(0, 30),
      child: const SizedBox(height: 38, width: 38, child: Icon(Icons.more_vert, size: 26)),
      itemBuilder: (BuildContext context) {
        return <PopupMenuEntry>[
          PopupMenuItem(
              height: 32,
              child: ListTile(
                  dense: true,
                  title: Text(localizations.httpsProxy),
                  leading:
                      proxyServer.enableSsl ? Icon(Icons.lock_open) : Icon(Icons.https_outlined, color: Colors.red),
                  onTap: () {
                    navigator(context, MobileSslWidget(proxyServer: proxyServer));
                  })),
          if (Platform.isAndroid)
            PopupMenuItem(
                height: 32,
                child: ListTile(
                    dense: true,
                    title: Text(localizations.appWhitelist),
                    leading: const Icon(Icons.android_rounded),
                    onTap: () {
                      navigator(context, AppWhitelist(proxyServer: proxyServer));
                    })),
          PopupMenuItem(
              height: 32,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.devices),
                title: Text(localizations.remoteDevice),
                onTap: () {
                  Navigator.maybePop(context);
                  navigator(context, RemoteDevicePage(proxyServer: proxyServer, remoteDevice: remoteDevice));
                },
              )),
          const PopupMenuDivider(height: 0),
          PopupMenuItem(
              height: 32,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.search),
                title: Text(localizations.search),
                onTap: () async {
                  await Navigator.maybePop(context);

                  MobileApp.searchStateKey.currentState?.showSearch();
                },
              )),
          PopupMenuItem(
              height: 32,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.highlight_outlined),
                title: Text('${localizations.keyword}${localizations.highlight}'),
                onTap: () {
                  navigator(context, const KeywordHighlight());
                },
              )),
          PopupMenuItem(
              height: 32,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.share_outlined),
                title: Text(localizations.viewExport),
                onTap: () async {
                  Navigator.maybePop(context);
                  var name = formatDate(DateTime.now(), [m, '-', d, ' ', HH, ':', nn, ':', ss]);
                  MobileApp.requestStateKey.currentState?.export(context, 'ProxyPin$name');
                },
              )),
        ];
      },
    );
  }

  void navigator(BuildContext context, Widget widget) async {
    await Navigator.maybePop(context);
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (BuildContext context) => widget),
      );
    }
  }
}
