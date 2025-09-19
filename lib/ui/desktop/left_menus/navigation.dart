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
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/desktop/preference.dart';
import 'package:url_launcher/url_launcher.dart';

///左侧导航栏
/// @author wanghongen
/// 2024/8/6
class LeftNavigationBar extends StatefulWidget {
  final AppConfiguration appConfiguration;
  final ProxyServer proxyServer;
  final ValueNotifier<int> selectIndex;

  const LeftNavigationBar(
      {super.key, required this.appConfiguration, required this.proxyServer, required this.selectIndex});

  @override
  State<StatefulWidget> createState() {
    return _LeftNavigationBarState();
  }
}

class _LeftNavigationBarState extends State<LeftNavigationBar> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  List<NavigationRailDestination> get destinations => [
        NavigationRailDestination(
            padding: const EdgeInsets.only(bottom: 5),
            icon: Icon(Icons.workspaces_outlined),
            label: Text(localizations.requests, style: Theme.of(context).textTheme.bodySmall)),
        NavigationRailDestination(
            padding: const EdgeInsets.only(bottom: 5),
            icon: Icon(Icons.favorite_outline_outlined),
            label: Text(localizations.favorites, style: Theme.of(context).textTheme.bodySmall)),
        NavigationRailDestination(
            padding: const EdgeInsets.only(bottom: 5),
            icon: Icon(Icons.history_outlined),
            label: Text(localizations.history, style: Theme.of(context).textTheme.bodySmall)),
        NavigationRailDestination(
            padding: const EdgeInsets.only(bottom: 5),
            icon: Icon(Icons.hardware_outlined),
            label: Text(localizations.toolbox, style: Theme.of(context).textTheme.bodySmall)),
      ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
        valueListenable: widget.selectIndex,
        builder: (_, index, __) {
          if (index == -1) {
            return const SizedBox();
          }

          return Container(
            width: localizations.localeName == 'en' ? 70 : 57,
            decoration:
                BoxDecoration(border: Border(right: BorderSide(color: Theme.of(context).dividerColor, width: 0.2))),
            child: Column(children: <Widget>[
              SizedBox(
                height: 320,
                child: leftNavigation(index),
              ),
              Expanded(
                  child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Tooltip(
                      message: localizations.preference,
                      preferBelow: false,
                      child: IconButton(
                          onPressed: () {
                            showDialog(
                                context: context,
                                builder: (_) => Preference(widget.appConfiguration, widget.proxyServer.configuration));
                          },
                          icon: Icon(Icons.settings_outlined, color: Colors.grey.shade500))),
                  const SizedBox(height: 5),
                  Tooltip(
                      preferBelow: true,
                      message: localizations.feedback,
                      child: IconButton(
                        onPressed: () => launchUrl(Uri.parse("https://github.com/wanghongenpin/proxypin/issues")),
                        icon: Icon(Icons.feedback_outlined, color: Colors.grey.shade500),
                      )),
                  const SizedBox(height: 10),
                ],
              ))
            ]),
          );
        });
  }

  //left menu eg: requests, favorites, history, toolbox
  Widget leftNavigation(int index) {
    return NavigationRail(
        minWidth: 57,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        selectedIconTheme: IconTheme.of(context).copyWith(color: Theme.of(context).colorScheme.primary, size: 22),
        unselectedIconTheme:
            IconTheme.of(context).copyWith(color: IconTheme.of(context).color?.withOpacity(0.55), size: 22),
        labelType: NavigationRailLabelType.all,
        destinations: destinations,
        selectedIndex: index,
        onDestinationSelected: (int index) {
          widget.selectIndex.value = index;
        });
  }
}
