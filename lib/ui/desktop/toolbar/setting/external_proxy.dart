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
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/host_port.dart';
import 'package:proxypin/ui/component/widgets.dart';

/// @author wanghongen
/// 2023/10/8
class ExternalProxyDialog extends StatefulWidget {
  final Configuration configuration;

  const ExternalProxyDialog({super.key, required this.configuration});

  @override
  State<StatefulWidget> createState() {
    return _ExternalProxyDialogState();
  }
}

class _ExternalProxyDialogState extends State<ExternalProxyDialog> {
  final formKey = GlobalKey<FormState>();
  late ProxyInfo externalProxy;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    externalProxy = ProxyInfo();
    if (widget.configuration.externalProxy != null) {
      externalProxy = ProxyInfo.fromJson(widget.configuration.externalProxy!.toJson());
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    return AlertDialog(
        scrollable: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        title: Text(localizations.externalProxy, style: const TextStyle(fontSize: 15)),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(localizations.cancel)),
          TextButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) {
                  return;
                }
                submit();
              },
              child: Text(localizations.confirm))
        ],
        content: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Text("${localizations.enable}：")),
                Expanded(
                    child: SwitchWidget(
                  value: externalProxy.enabled,
                  scale: 0.85,
                  onChanged: (val) {
                    externalProxy.enabled = val;
                  },
                ))
              ]),

              const SizedBox(height: 3),
              Text(localizations.externalProxyServer, style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 10),
              SizedBox(
                  height: 36,
                  child: Row(children: [
                    Expanded(
                        child: TextFormField(
                      initialValue: externalProxy.host,
                      validator: (val) => val == null || val.isEmpty ? localizations.cannotBeEmpty : null,
                      onChanged: (val) => externalProxy.host = val,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 8),
                        hintText: 'Host',
                        hintStyle: TextStyle(color: Colors.grey),
                        border: OutlineInputBorder(),
                      ),
                    )),
                    const SizedBox(child: Text(' : ', style: TextStyle(fontSize: 22))),
                    SizedBox(
                        width: 65,
                        child: TextFormField(
                          initialValue: externalProxy.port?.toString() ?? '',
                          inputFormatters: <TextInputFormatter>[
                            LengthLimitingTextInputFormatter(5),
                            FilteringTextInputFormatter.allow(RegExp("[0-9]"))
                          ],
                          onChanged: (val) => externalProxy.port = int.parse(val),
                          validator: (val) => val == null || val.isEmpty ? localizations.cannotBeEmpty : null,
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: 8),
                            hintText: 'Port',
                            hintStyle: TextStyle(color: Colors.grey),
                            border: OutlineInputBorder(),
                          ),
                        ))
                  ])),

              //认证
              const SizedBox(height: 15),
              Text(localizations.externalProxyAuth, style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 10),
              SizedBox(
                  height: 36,
                  child: Row(children: [
                    SizedBox(
                        width: isCN ? 65 : 85,
                        child: Text('${localizations.username}：', style: const TextStyle(fontWeight: FontWeight.w300))),
                    Expanded(
                        child: TextFormField(
                      initialValue: externalProxy.username,
                      onChanged: (val) => externalProxy.username = val,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 8),
                        border: OutlineInputBorder(),
                      ),
                    ))
                  ])),
              const SizedBox(height: 10),

              SizedBox(
                  height: 36,
                  child: Row(children: [
                    SizedBox(
                        width: isCN ? 65 : 85,
                        child: Text('${localizations.password}：', style: const TextStyle(fontWeight: FontWeight.w300))),
                    Expanded(
                        child: TextFormField(
                      initialValue: externalProxy.password,
                      onChanged: (val) => externalProxy.password = val,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 8),
                        border: OutlineInputBorder(),
                      ),
                    ))
                  ])),
            ])));
  }

  submit() async {
    bool setting = true;
    if (externalProxy.enabled) {
      try {
        var socket = await Socket.connect(externalProxy.host, externalProxy.port!, timeout: const Duration(seconds: 1));
        socket.destroy();
      } on SocketException catch (_) {
        setting = false;
        if (mounted) {
          await showDialog(
              context: context,
              builder: (_) => AlertDialog(
                    title: Text(localizations.externalProxyConnectFailure),
                    content: SizedBox(
                        width: 230,
                        child: Text(localizations.externalProxyFailureConfirm,
                            style: const TextStyle(fontSize: 12), maxLines: 3)),
                    actions: [
                      TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: Text(localizations.cancel)),
                      TextButton(
                          onPressed: () {
                            setting = true;
                            Navigator.of(context).pop();
                          },
                          child: Text(localizations.confirm))
                    ],
                  ));
        }
      }
    }

    if (setting) {
      widget.configuration.externalProxy = externalProxy;
      widget.configuration.flushConfig();
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
