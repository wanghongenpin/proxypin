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

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/native/vpn.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/components/manager/script_manager.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/app_dialog.dart';
import 'package:proxypin/ui/component/qrcode/qr_scan_view.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/utils/ip.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

///远程设备
///Remote device
///@author Hongen Wang
class RemoteModel {
  final bool connect;
  final String? host;
  final int? port;
  final String? os;
  final String? hostname;
  final bool? ipProxy;

  RemoteModel({
    required this.connect,
    this.host,
    this.port,
    this.os,
    this.hostname,
    this.ipProxy,
  });

  factory RemoteModel.fromJson(Map<String, dynamic> json) {
    return RemoteModel(
        connect: json['connect'],
        host: json['host'],
        port: json['port'],
        os: json['os'],
        hostname: json['hostname'],
        ipProxy: json['ipProxy'] == true);
  }

  RemoteModel copyWith({
    bool? connect,
    String? host,
    int? port,
    String? os,
    String? hostname,
    bool? ipProxy,
  }) {
    return RemoteModel(
      connect: connect ?? this.connect,
      host: host ?? this.host,
      port: port ?? this.port,
      os: os ?? this.os,
      hostname: hostname ?? this.hostname,
      ipProxy: ipProxy ?? this.ipProxy,
    );
  }

  String get identification => '$host:$port';

  //host和端口是否相等
  bool equals(RemoteModel remoteModel) {
    return identification == remoteModel.identification;
  }

  Map<String, dynamic> toJson() {
    return {'connect': connect, 'host': host, 'port': port, 'os': os, 'hostname': hostname, 'ipProxy': ipProxy};
  }
}

class RemoteDevicePage extends StatefulWidget {
  final ProxyServer proxyServer;
  final ValueNotifier<RemoteModel> remoteDevice;

  const RemoteDevicePage({super.key, required this.proxyServer, required this.remoteDevice});

  @override
  State<RemoteDevicePage> createState() => _RemoteDevicePageState();
}

class _RemoteDevicePageState extends State<RemoteDevicePage> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  bool syncConfig = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(localizations.remoteDevice, style: const TextStyle(fontSize: 16)),
        actions: [
          PopupMenuButton(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 8,
            color: Theme.of(context).colorScheme.surface,
            icon: const Icon(Icons.add_outlined),
            itemBuilder: (BuildContext context) {
              return <PopupMenuEntry>[
                CustomPopupMenuItem(
                    height: 32,
                    child: ListTile(
                        leading: const Icon(Icons.qr_code_scanner_outlined),
                        dense: true,
                        title: Text(localizations.scanCode),
                        onTap: () {
                          Navigator.maybePop(context);
                          connectRemote();
                        })),
                CustomPopupMenuItem(
                    height: 32,
                    child: ListTile(
                        leading: const Icon(Icons.edit_rounded),
                        dense: true,
                        title: Text(localizations.inputAddress),
                        onTap: () async {
                          Navigator.maybePop(context);
                          inputAddress(await localIp());
                        })),
                PopupMenuItem(
                    height: 32,
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.phone_android),
                      title: Text(localizations.myQRCode),
                      onTap: () async {
                        Navigator.maybePop(context);
                        var ip = await localIp(readCache: false);
                        if (context.mounted) {
                          qrCode(context, ip, widget.proxyServer.port);
                        }
                      },
                    )),
              ];
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            remoteDeviceStatus(), //远程设备状态
            const SizedBox(height: 20),
            Text(localizations.remoteDeviceList, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            Expanded(child: futureWidget(SharedPreferences.getInstance(), rows)), //远程设备列表
          ],
        ),
      ),
    );
  }

  Widget rows(SharedPreferences prefs) {
    var remoteDeviceList = getRemoteDeviceList(prefs);

    return ListView(
      children: remoteDeviceList.map((remoteDevice) {
        return Dismissible(
            key: Key(remoteDevice.identification),
            onDismissed: (direction) async {
              remoteDeviceList.removeWhere((it) => it.equals(remoteDevice));
              await setRemoteDeviceList(prefs, remoteDeviceList);

              setState(() {});
              if (mounted) FlutterToastr.show(localizations.deleteSuccess, context);
            },
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 5),
              title: Text(remoteDevice.hostname ?? ''),
              subtitle: Text('${remoteDevice.host}:${remoteDevice.port}'),
              trailing: getIcon(remoteDevice.os!),
              onTap: () {
                doConnect(remoteDevice.host!, remoteDevice.port!, ipProxy: remoteDevice.ipProxy);
              },
            ));
      }).toList(),
    );
  }

  Icon getIcon(String os) {
    if (os.contains("windows")) {
      return const Icon(Icons.window_sharp, size: 30);
    } else if (os.contains("linux")) {
      return const Icon(Icons.desktop_windows, size: 30);
    } else if (os.contains("macos") || os.contains("ios")) {
      return const Icon(Icons.apple, size: 30);
    } else if (os == 'android') {
      return const Icon(Icons.android, size: 30);
    } else {
      return const Icon(Icons.devices, size: 30);
    }
  }

  List<RemoteModel> getRemoteDeviceList(SharedPreferences prefs) {
    var remoteDeviceList = prefs.getStringList('remoteDeviceList') ?? [];
    return remoteDeviceList.map((it) => RemoteModel.fromJson(jsonDecode(it))).toList();
  }

  Future<bool> setRemoteDeviceList(SharedPreferences prefs, Iterable<RemoteModel> remoteDeviceList) {
    var list = remoteDeviceList.map((it) => jsonEncode(it.toJson())).toList();
    return prefs.setStringList('remoteDeviceList', list);
  }

  ///远程设备状态
  Widget remoteDeviceStatus() {
    if (widget.remoteDevice.value.connect) {
      return Center(
          child: Column(
        children: [
          const Icon(Icons.check_circle_outline_outlined, size: 55, color: Colors.green),
          const SizedBox(height: 6),
          if (Platform.isIOS)
            Row(
              children: [
                Expanded(
                    child: ListTile(
                        title: Text(localizations.ipLayerProxy), subtitle: Text(localizations.ipLayerProxyDesc))),
                SwitchWidget(
                    value: widget.remoteDevice.value.ipProxy ?? false,
                    scale: 0.85,
                    onChanged: (val) async {
                      widget.remoteDevice.value = widget.remoteDevice.value.copyWith(ipProxy: val);
                      SharedPreferences.getInstance().then((prefs) {
                        var remoteDeviceList = getRemoteDeviceList(prefs);
                        remoteDeviceList.removeWhere((it) => it.equals(widget.remoteDevice.value));
                        remoteDeviceList.insert(0, widget.remoteDevice.value);

                        setRemoteDeviceList(prefs, remoteDeviceList);
                      });

                      if ((await Vpn.isRunning())) {
                        Vpn.stopVpn();
                        Future.delayed(const Duration(milliseconds: 1500), () {
                          Vpn.startVpn(widget.remoteDevice.value.host!, widget.remoteDevice.value.port!,
                              widget.proxyServer.configuration,
                              ipProxy: val);
                        });
                      }
                    }),
              ],
            ),
          const SizedBox(height: 6),
          Text('${localizations.connected}：${widget.remoteDevice.value.hostname}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            TextButton.icon(
              style: ButtonStyle(
                  shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)))),
              onPressed: pullConfig,
              icon: const Icon(Icons.sync),
              label: Text(localizations.syncConfig),
            ),
            TextButton.icon(
              label: Text(localizations.disconnect),
              style: ButtonStyle(
                shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0))),
              ),
              icon: const Icon(Icons.cancel_outlined),
              onPressed: () {
                widget.remoteDevice.value = RemoteModel(connect: false);
                setState(() {});
              },
            ),
          ])
        ],
      ));
    }

    return Center(
        child: Column(children: [
      const Icon(Icons.cancel_outlined, size: 55, color: Colors.red),
      const SizedBox(height: 6),
      Text(localizations.notConnected, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
    ]));
  }

  ///输入地址链接
  void inputAddress(String host) {
    //输入账号密码连接
    host = host.substring(0, host.contains('.') ? host.lastIndexOf('.') + 1 : host.length);
    int? port = 9099;
    if (!context.mounted) return;

    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(localizations.inputAddress),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: host,
                  decoration: const InputDecoration(hintText: 'Host'),
                  keyboardType: TextInputType.url,
                  onChanged: (value) => host = value,
                ),
                TextFormField(
                    initialValue: port.toString(),
                    decoration: const InputDecoration(hintText: 'Port'),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      port = value.isEmpty ? null : int.tryParse(value);
                    }),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text(localizations.cancel)),
              TextButton(
                  onPressed: () async {
                    if (host.isEmpty || port == null) {
                      FlutterToastr.show(localizations.cannotBeEmpty, context);
                      return;
                    }

                    if ((await doConnect(host, port!)) && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  child: Text(localizations.connectRemote)),
            ],
          );
        });
  }

  ///扫码连接
  Future<void> connectRemote() async {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    String? scanRes = await QrCodeScanner.scan(context);
    if (scanRes == null) return;

    if (scanRes == "-1") {
      if (mounted) FlutterToastr.show(localizations.invalidQRCode, context);
      return;
    }

    if (scanRes.startsWith("http")) {
      launchUrl(Uri.parse(scanRes), mode: LaunchMode.externalApplication);
      return;
    }

    if (scanRes.startsWith("proxypin://connect")) {
      Uri uri = Uri.parse(scanRes);
      var host = uri.queryParameters['host'];
      var port = uri.queryParameters['port'];

      doConnect(host!, int.parse(port!));
      return;
    }

    if (mounted) {
      FlutterToastr.show(localizations.invalidQRCode, context);
    }
  }

  ///
  bool doConnecting = false;

  ///连接远程设备
  Future<bool> doConnect(String host, int port, {bool? ipProxy}) async {
    if (doConnecting) return false;
    doConnecting = true;

    try {
      var response = await HttpClients.get("http://$host:$port/ping", timeout: const Duration(milliseconds: 3000));
      if (response.bodyAsString == "pong") {
        widget.remoteDevice.value = RemoteModel(
          connect: true,
          host: host,
          port: port,
          os: response.headers.get("os"),
          hostname: response.headers.get("hostname"),
          ipProxy: ipProxy,
        );

        //去重记录5条连接记录
        SharedPreferences prefs = await SharedPreferences.getInstance();
        var remoteDeviceList = getRemoteDeviceList(prefs);
        remoteDeviceList.removeWhere((it) => it.equals(widget.remoteDevice.value));
        remoteDeviceList.insert(0, widget.remoteDevice.value);

        var list = remoteDeviceList.take(5);
        setRemoteDeviceList(prefs, list).whenComplete(() {
          setState(() {});
        });

        if (mounted) {
          CustomToast.success(
                  "${localizations.connectSuccess}${Vpn.isVpnStarted ? '' : ', ${localizations.remoteConnectSuccessTips}'}")
              .show(context);
        }
      }
      return true;
    } catch (e) {
      logger.e(e);
      if (mounted) {
        CustomToast.error(localizations.remoteConnectFail).show(context, alignment: Alignment.topCenter);
      }
      return false;
    } finally {
      doConnecting = false;
    }
  }

  ///连接二维码
  void qrCode(BuildContext context, String host, int port) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            contentPadding: const EdgeInsets.all(15),
            actionsPadding: const EdgeInsets.only(bottom: 10, right: 10),
            title: Text(localizations.remoteConnectForward, style: const TextStyle(fontSize: 16)),
            content: SizedBox(
                height: 280,
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QrImageView(
                        backgroundColor: Colors.white,
                        data: "proxypin://connect?host=$host&port=${widget.proxyServer.port}",
                        version: QrVersions.auto,
                        size: 200.0),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${localizations.localIP}:'),
                        const SizedBox(width: 5),
                        SelectableText('$host:$port'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(localizations.mobileScan),
                  ],
                )),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(localizations.cancel)),
            ],
          );
        });
  }

  //拉取桌面配置
  void pullConfig() {
    var desktopModel = widget.remoteDevice.value;
    HttpClients.get('http://${desktopModel.host}:${desktopModel.port}/config').then((response) {
      if (response.status.isSuccessful() && mounted) {
        var config = jsonDecode(response.bodyAsString);
        syncConfig = true;
        showDialog(
            context: context,
            builder: (context) {
              return ConfigSyncWidget(configuration: widget.proxyServer.configuration, config: config);
            });
      }
    }).onError((error, stackTrace) {
      logger.e('拉取配置失败', error: error, stackTrace: stackTrace);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizations.pullConfigFail)));
    });
  }
}

class ConfigSyncWidget extends StatefulWidget {
  final Configuration configuration;
  final Map<String, dynamic> config;

  const ConfigSyncWidget({super.key, required this.configuration, required this.config});

  @override
  State<StatefulWidget> createState() {
    return ConfigSyncState();
  }
}

class ConfigSyncState extends State<ConfigSyncWidget> {
  bool syncWhiteList = true;
  bool syncBlackList = true;
  bool syncRewrite = true;
  bool syncScript = true;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(localizations.syncConfig, style: const TextStyle(fontSize: 16)),
      content: Wrap(children: [
        SwitchWidget(
            title: "${localizations.sync} ${localizations.domainWhitelist}",
            value: syncWhiteList,
            onChanged: (val) {
              setState(() {
                syncWhiteList = val;
              });
            }),
        const SizedBox(height: 5),
        SwitchWidget(
            title: "${localizations.sync} ${localizations.domainBlacklist}",
            value: syncBlackList,
            onChanged: (val) {
              setState(() {
                syncBlackList = val;
              });
            }),
        const SizedBox(height: 5),
        SwitchWidget(
            title: "${localizations.sync} ${localizations.requestRewrite}",
            value: syncRewrite,
            onChanged: (val) {
              setState(() {
                syncRewrite = val;
              });
            }),
        const SizedBox(height: 5),
        SwitchWidget(
            title: "${localizations.sync} ${localizations.script}",
            value: syncScript,
            onChanged: (val) {
              setState(() {
                syncScript = val;
              });
            }),
      ]),
      actions: [
        TextButton(
            child: Text(localizations.cancel),
            onPressed: () {
              Navigator.pop(context);
            }),
        TextButton(
            child: Text('${localizations.start} ${localizations.sync}'),
            onPressed: () async {
              if (syncWhiteList) {
                HostFilter.whitelist.load(widget.config['whitelist']);
              }
              if (syncBlackList) {
                HostFilter.blacklist.load(widget.config['blacklist']);
              }
              widget.configuration.flushConfig();

              if (syncRewrite) {
                var requestRewrites = await RequestRewriteManager.instance;
                await requestRewrites.syncConfig(widget.config['requestRewrites']);
              }

              if (syncScript) {
                var scriptManager = await ScriptManager.instance;
                await scriptManager.clean();
                scriptManager.list.clear();
                for (var item in widget.config['scripts']) {
                  await scriptManager.addScript(ScriptItem.fromJson(item), item['script']);
                }
                await scriptManager.flushConfig();
              }

              if (mounted) {
                Navigator.pop(this.context);
                ScaffoldMessenger.of(this.context)
                    .showSnackBar(SnackBar(content: Text('${localizations.sync}${localizations.success}')));
              }
            }),
      ],
    );
  }
}
