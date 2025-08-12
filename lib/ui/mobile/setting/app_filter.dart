/*
 * Copyright 2023 Hongen Wang
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
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/native/installed_apps.dart';
import 'package:proxypin/native/vpn.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/ui/component/widgets.dart';

///应用白名单 目前只支持安卓 ios没办法获取安装的列表
///@author wang
class AppWhitelist extends StatefulWidget {
  final ProxyServer proxyServer;

  const AppWhitelist({super.key, required this.proxyServer});

  @override
  State<AppWhitelist> createState() => _AppWhitelistState();
}

class _AppWhitelistState extends State<AppWhitelist> {
  late Configuration configuration;

  bool changed = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    configuration = widget.proxyServer.configuration;
  }

  @override
  void dispose() {
    if (changed) {
      configuration.flushConfig();
      if (Vpn.isVpnStarted) {
        Vpn.restartVpn("127.0.0.1", widget.proxyServer.port, configuration);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    var appWhitelist = <Future<AppInfo>>[];
    for (var element in configuration.appWhitelist) {
      appWhitelist.add(InstalledApps.getAppInfo(element).catchError((e) {
        return AppInfo(name: isCN ? "未知应用" : "Unknown app", packageName: element, inValid: true);
      }));
    }

    return Scaffold(
        appBar: AppBar(
          title: Text(localizations.appWhitelist, style: const TextStyle(fontSize: 16)),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () async {
                //添加
                List<AppInfo> list = await Future.wait(appWhitelist);
                if (context.mounted) {
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) {
                    return InstalledAppsWidget(addedList: list);
                  })).then((value) {
                    if (value != null) {
                      if (configuration.appWhitelist.contains(value)) {
                        return;
                      }
                      setState(() {
                        configuration.appWhitelist.add(value);
                        changed = true;
                      });
                    }
                  });
                }
              },
            ),
            IconButton(
              tooltip: isCN ? '清除失效应用' : 'clear invalid apps',
              onPressed: () async {
                if (configuration.appWhitelist.isEmpty) return;
                List<AppInfo> list = await Future.wait(appWhitelist);
                for (AppInfo appInfo in list) {
                  if (appInfo.inValid == true) {
                    configuration.appWhitelist.remove(appInfo.packageName);
                  }
                }
                setState(() {
                  changed = true;
                });
              },
              icon: Icon(Icons.cleaning_services_outlined),
            ),
          ],
        ),
        body: Column(children: [
          const SizedBox(height: 5),
          SwitchWidget(
              value: configuration.appWhitelistEnabled,
              title: localizations.enable,
              subtitle: localizations.appWhitelistDescribe,
              onChanged: (val) {
                changed = true;
                configuration.appWhitelistEnabled = val;
                configuration.flushConfig();
              }),
          const SizedBox(height: 5),
          Expanded(
              child: FutureBuilder(
                  future: Future.wait(appWhitelist),
                  builder: (BuildContext context, AsyncSnapshot<List<AppInfo>> snapshot) {
                    if (snapshot.hasData) {
                      if (snapshot.data!.isEmpty) {
                        return Center(
                          child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 15),
                              child: Text(
                                  isCN
                                      ? "未设置白名单应用时会对所有应用抓包"
                                      : "When no whitelist application is set, all applications will be captured",
                                  style: const TextStyle(color: Colors.grey))),
                        );
                      }

                      return ListView.builder(
                          itemCount: snapshot.data!.length,
                          itemBuilder: (BuildContext context, int index) {
                            AppInfo appInfo = snapshot.data![index];
                            return ListTile(
                              leading:
                                  appInfo.icon == null ? const Icon(Icons.question_mark) : Image.memory(appInfo.icon!),
                              title: Text(appInfo.name ?? ""),
                              subtitle: Text(appInfo.packageName ?? ""),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () {
                                  //删除
                                  setState(() {
                                    configuration.appWhitelist.remove(appInfo.packageName);
                                    changed = true;
                                  });
                                },
                              ),
                            );
                          });
                    } else {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }
                  })),
        ]));
  }
}

class AppBlacklist extends StatefulWidget {
  final ProxyServer proxyServer;

  const AppBlacklist({super.key, required this.proxyServer});

  @override
  State<AppBlacklist> createState() => _AppBlacklistState();
}

class _AppBlacklistState extends State<AppBlacklist> {
  late Configuration configuration;

  bool changed = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    configuration = widget.proxyServer.configuration;
  }

  @override
  void dispose() {
    if (changed) {
      configuration.flushConfig();
      if (Vpn.isVpnStarted) {
        Vpn.restartVpn("127.0.0.1", widget.proxyServer.port, configuration);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');
    var appBlacklist = <Future<AppInfo>>[];
    for (var element in configuration.appBlacklist ?? []) {
      appBlacklist.add(InstalledApps.getAppInfo(element).catchError((e) {
        return AppInfo(name: isCN ? "未知应用" : "Unknown app", packageName: element, inValid: true);
      }));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.appBlacklist, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              //添加
              List<AppInfo> list = await Future.wait(appBlacklist);
              if (context.mounted) {
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (context) => InstalledAppsWidget(addedList: list)))
                    .then((value) {
                  if (value != null) {
                    if (configuration.appBlacklist?.contains(value) == true) {
                      return;
                    }
                    setState(() {
                      configuration.appBlacklist ??= [];
                      configuration.appBlacklist?.add(value);
                      changed = true;
                    });
                  }
                });
              }
            },
          ),
          IconButton(
            tooltip: isCN ? '清除失效应用' : 'clear invalid apps',
            onPressed: () async {
              if (configuration.appBlacklist?.isEmpty == true) return;
              List<AppInfo> list = await Future.wait(appBlacklist);
              for (AppInfo appInfo in list) {
                if (appInfo.inValid == true) {
                  configuration.appBlacklist?.remove(appInfo.packageName);
                }
              }
              setState(() {
                changed = true;
              });
            },
            icon: Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),
      body: FutureBuilder(
          future: Future.wait(appBlacklist),
          builder: (BuildContext context, AsyncSnapshot<List<AppInfo>> snapshot) {
            if (snapshot.hasData) {
              if (snapshot.data!.isEmpty) {
                return Center(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      child: Text(localizations.emptyData, style: const TextStyle(color: Colors.grey))),
                );
              }

              return ListView.builder(
                  itemCount: snapshot.data!.length,
                  itemBuilder: (BuildContext context, int index) {
                    AppInfo appInfo = snapshot.data![index];
                    return ListTile(
                      leading: appInfo.icon == null ? const Icon(Icons.question_mark) : Image.memory(appInfo.icon!),
                      title: Text(appInfo.name ?? ""),
                      subtitle: Text(appInfo.packageName ?? ""),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          //删除
                          setState(() {
                            configuration.appBlacklist?.remove(appInfo.packageName);
                            changed = true;
                          });
                        },
                      ),
                    );
                  });
            } else {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }
          }),
    );
  }
}

///已安装的app列表
class InstalledAppsWidget extends StatefulWidget {
  const InstalledAppsWidget({
    super.key,
    required this.addedList,
  });

  final List<AppInfo> addedList;

  @override
  State<InstalledAppsWidget> createState() => _InstalledAppsWidgetState();
}

class _InstalledAppsWidgetState extends State<InstalledAppsWidget> {
  static Future<List<AppInfo>> apps = InstalledApps.getInstalledApps(true);

  String? keyword;

  @override
  Widget build(BuildContext context) {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          decoration: InputDecoration(
            hintText: isCN ? "请输入应用名或包名" : "Please enter the application or package name",
            border: InputBorder.none,
          ),
          onChanged: (String value) {
            keyword = value.toLowerCase();
            setState(() {});
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          apps = InstalledApps.getInstalledApps(true);
          await apps;
          setState(() {});
        },
        child: FutureBuilder(
          future: apps,
          builder: (BuildContext context, AsyncSnapshot<List<AppInfo>> snapshot) {
            if (snapshot.hasData) {
              List<AppInfo> appInfoList = snapshot.data!;
              appInfoList = appInfoList.toSet().difference(widget.addedList.toSet()).toList();
              if (keyword != null && keyword!.trim().isNotEmpty) {
                appInfoList = appInfoList
                    .where((element) =>
                        element.name!.toLowerCase().contains(keyword!) ||
                        element.packageName!.toLowerCase().contains(keyword!))
                    .toList();
              }

              return ListView.builder(
                  itemCount: appInfoList.length,
                  itemBuilder: (BuildContext context, int index) {
                    AppInfo appInfo = appInfoList[index];
                    return ListTile(
                      leading: Image.memory(appInfo.icon ?? Uint8List(0)),
                      title: Text(appInfo.name ?? ""),
                      subtitle: Text(appInfo.packageName ?? ""),
                      onTap: () async {
                        Navigator.of(context).pop(appInfo.packageName);
                      },
                    );
                  });
            } else {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }
          },
        ),
      ),
    );
  }
}
