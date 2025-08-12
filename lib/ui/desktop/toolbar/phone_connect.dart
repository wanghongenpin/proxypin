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
import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// @author wanghongen
/// 2023/10/8
class PhoneConnect extends StatefulWidget {
  final ProxyServer proxyServer;
  final List<String> hosts;

  const PhoneConnect({super.key, required this.proxyServer, required this.hosts});

  @override
  State<StatefulWidget> createState() {
    return _PhoneConnectState();
  }
}

class _PhoneConnectState extends State<PhoneConnect> {
  late String host;
  late int port;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    host = widget.hosts.first;
    port = widget.proxyServer.port;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        title: Row(children: [
          Text(localizations.mobileConnect, style: const TextStyle(fontSize: 18)),
          const Expanded(child: Align(alignment: Alignment.topRight, child: CloseButton()))
        ]),
        contentPadding: const EdgeInsets.all(10),
        content: SizedBox(
            height: 300,
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.proxyServer.isRunning)
                  QrImageView(
                      backgroundColor: Colors.white,
                      data: "proxypin://connect?host=$host&port=${widget.proxyServer.port}",
                      size: 200.0)
                else
                  SizedBox(
                      height: 200,
                      child: Center(child: Text(localizations.serverNotStart, style: const TextStyle(fontSize: 16)))),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(localizations.localIP),
                  DropdownButton(
                      value: host,
                      isDense: true,
                      borderRadius: BorderRadius.circular(8),
                      padding: const EdgeInsets.only(right: 10),
                      items: widget.hosts
                          .map((it) => DropdownMenuItem(
                                value: it,
                                child: SelectableText('$it:$port'),
                              ))
                          .toList(),
                      onChanged: (String? value) {
                        setState(() {
                          host = value!;
                        });
                      })
                ]),
                const SizedBox(height: 10),
                Text(localizations.mobileScan, style: const TextStyle(fontSize: 16)),
              ],
            )));
  }
}
