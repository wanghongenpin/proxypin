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
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/components/manager/hosts_manager.dart';
import 'package:proxypin/network/components/manager/request_block_manager.dart';
import 'package:proxypin/network/util/system_proxy.dart';
import 'package:proxypin/ui/component/multi_window.dart';
import 'package:proxypin/ui/desktop/toolbar/setting/external_proxy.dart';
import 'package:proxypin/ui/desktop/toolbar/setting/hosts.dart';
import 'package:proxypin/ui/desktop/toolbar/setting/request_block.dart';
import 'package:url_launcher/url_launcher.dart';

import 'filter.dart';

///设置菜单
/// @author wanghongen
/// 2023/10/8
class Setting extends StatefulWidget {
  final ProxyServer proxyServer;

  const Setting({super.key, required this.proxyServer});

  @override
  State<Setting> createState() => _SettingState();
}

class _SettingState extends State<Setting> {
  late Configuration configuration;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    configuration = widget.proxyServer.configuration;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {

    return MenuAnchor(
      builder: (context, controller, child) {
        return IconButton(
            icon: const Icon(Icons.settings, size: 22),
            tooltip: localizations.setting,
            onPressed: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            });
      },
      menuChildren: [
        _ProxyMenu(proxyServer: widget.proxyServer),
        item(localizations.domainFilter, onPressed: hostFilter),
        item(localizations.hosts, onPressed: hosts),
        item(localizations.requestBlock, onPressed: showRequestBlock),
        item(localizations.requestRewrite, onPressed: requestRewrite),
        item(localizations.script,
            onPressed: () => MultiWindow.openWindow(localizations.script, 'ScriptWidget', size: const Size(800, 700))),
        item(localizations.externalProxy, onPressed: setExternalProxy),
        item("Github", onPressed: () => launchUrl(Uri.parse("https://github.com/wanghongenpin/proxypin"))),
      ],
    );
  }

  Widget item(String text, {VoidCallback? onPressed}) {
    return MenuItemButton(
        trailingIcon: const Icon(Icons.arrow_right),
        onPressed: onPressed,
        child: Padding(
            padding: const EdgeInsets.only(left: 10, right: 5),
            child: Text(text, style: const TextStyle(fontSize: 14))));
  }

  ///设置外部代理地址
  setExternalProxy() {
    showDialog(
        barrierDismissible: false,
        context: context,
        builder: (context) {
          return ExternalProxyDialog(configuration: widget.proxyServer.configuration);
        });
  }

  ///请求重写Dialog
  void requestRewrite() async {
    if (!mounted) return;
    MultiWindow.openWindow(localizations.requestRewrite, 'RequestRewriteWidget', size: const Size(800, 750));
  }

  ///show域名过滤Dialog
  void hostFilter() {
    showDialog(
        barrierDismissible: false, context: context, builder: (context) => FilterDialog(configuration: configuration));
  }

  ///show域名过滤Dialog
  void hosts() async {
    var hosts = await HostsManager.instance;
    if (!mounted) return;
    showDialog(barrierDismissible: false, context: context, builder: (context) => HostsDialog(hostsManager: hosts));
  }

  //请求屏蔽
  void showRequestBlock() async {
    var requestBlockManager = await RequestBlockManager.instance;
    if (!mounted) return;
    showDialog(
        barrierDismissible: false,
        context: context,
        builder: (context) => RequestBlock(requestBlockManager: requestBlockManager));
  }
}

///代理菜单
class _ProxyMenu extends StatefulWidget {
  final ProxyServer proxyServer;

  const _ProxyMenu({required this.proxyServer});

  @override
  State<StatefulWidget> createState() => _ProxyMenuState();
}

class _ProxyMenuState extends State<_ProxyMenu> {
  var textEditingController = TextEditingController();

  late Configuration configuration;
  bool changed = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    configuration = widget.proxyServer.configuration;
    textEditingController.text = configuration.proxyPassDomains;
    super.initState();
  }

  @override
  void dispose() {
    if (configuration.proxyPassDomains != textEditingController.text) {
      changed = true;
      configuration.proxyPassDomains = textEditingController.text;
      SystemProxy.setProxyPassDomains(configuration.proxyPassDomains);
    }

    if (changed) {
      configuration.flushConfig();
    }
    textEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SubmenuButton(
      menuChildren: [
        PortWidget(proxyServer: widget.proxyServer, textStyle: const TextStyle(fontSize: 13)),
        const Divider(thickness: 0.3, height: 8),
        setSystemProxy(),
        const Divider(thickness: 0.3, height: 8),
        const SizedBox(height: 3),
        Padding(
            padding: const EdgeInsets.only(left: 15),
            child: Row(children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(localizations.proxyIgnoreDomain, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 3),
                  Text("多个使用;分割", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
              Padding(
                  padding: const EdgeInsets.only(left: 35),
                  child: TextButton(
                    child: Text(localizations.reset),
                    onPressed: () {
                      textEditingController.text = SystemProxy.proxyPassDomains;
                    },
                  ))
            ])),
        const SizedBox(height: 5),
        Padding(
            padding: const EdgeInsets.only(left: 15, right: 5),
            child: TextField(
                textInputAction: TextInputAction.done,
                style: const TextStyle(fontSize: 13),
                controller: textEditingController,
                decoration: const InputDecoration(
                    contentPadding: EdgeInsets.all(10),
                    border: OutlineInputBorder(),
                    constraints: BoxConstraints(minWidth: 190, maxWidth: 190)),
                maxLines: 5,
                minLines: 1)),
        const SizedBox(height: 10),
      ],
      child: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Text(localizations.proxy, style: const TextStyle(fontSize: 14))),
    );
  }

  ///设置系统代理
  Widget setSystemProxy() {
    return Row(children: [
      Padding(
          padding: const EdgeInsets.only(left: 15),
          child: Text(localizations.systemProxy, style: const TextStyle(fontSize: 14))),
      Expanded(
          child: Transform.scale(
              scale: 0.8,
              child: Switch(
                  hoverColor: Colors.transparent,
                  value: configuration.enableSystemProxy,
                  onChanged: (val) {
                    widget.proxyServer.setSystemProxyEnable(val);
                    configuration.enableSystemProxy = val;
                    setState(() {
                      changed = true;
                    });
                  })))
    ]);
  }
}

class PortWidget extends StatefulWidget {
  final ProxyServer proxyServer;
  final TextStyle? textStyle;
  final String? title;

  const PortWidget({super.key, required this.proxyServer, this.textStyle, this.title});

  @override
  State<StatefulWidget> createState() {
    return _PortState();
  }
}

class _PortState extends State<PortWidget> {
  final textController = TextEditingController();
  final FocusNode portFocus = FocusNode();

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    textController.text = widget.proxyServer.port.toString();
    portFocus.addListener(() async {
      //失去焦点
      if (!portFocus.hasFocus && textController.text != widget.proxyServer.port.toString()) {
        widget.proxyServer.configuration.port = int.parse(textController.text);

        if (widget.proxyServer.isRunning) {
          String message = localizations.proxyPortRepeat(widget.proxyServer.port);
          widget.proxyServer.restart().catchError((e) => FlutterToastr.show(message, context, duration: 3));
        }
        widget.proxyServer.configuration.flushConfig();
      }
    });
  }

  @override
  void dispose() {
    portFocus.dispose();
    textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Padding(padding: EdgeInsets.only(left: 15)),
      Text(widget.title ?? localizations.port, style: widget.textStyle),
      SizedBox(
          width: 80,
          child: TextFormField(
            focusNode: portFocus,
            controller: textController,
            textAlign: TextAlign.center,
            onTapOutside: (event) => portFocus.unfocus(),
            keyboardType: TextInputType.datetime,
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(5),
              FilteringTextInputFormatter.allow(RegExp("[0-9]"))
            ],
            decoration: const InputDecoration(),
          ))
    ]);
  }
}
