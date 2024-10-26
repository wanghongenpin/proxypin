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
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/util/crts.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:url_launcher/url_launcher.dart';

class MobileSslWidget extends StatefulWidget {
  final ProxyServer proxyServer;
  final Function(bool val)? onEnableChange;

  const MobileSslWidget({super.key, required this.proxyServer, this.onEnableChange});

  @override
  State<MobileSslWidget> createState() => _MobileSslState();
}

class _MobileSslState extends State<MobileSslWidget> {
  bool changed = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void dispose() {
    if (changed) {
      widget.proxyServer.configuration.flushConfig();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(localizations.httpsProxy, style: const TextStyle(fontSize: 16)),
          centerTitle: true,
        ),
        body: ListView(children: [
          SwitchListTile(
              hoverColor: Colors.transparent,
              title: Text(localizations.enabledHttps),
              value: widget.proxyServer.enableSsl,
              onChanged: (val) {
                widget.proxyServer.enableSsl = val;
                if (widget.onEnableChange != null) widget.onEnableChange!(val);
                changed = true;
                CertificateManager.cleanCache();
                setState(() {});
              }),
          ListTile(
              title: Text(localizations.installRootCa),
              trailing: const Icon(Icons.keyboard_arrow_right),
              onTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => Platform.isIOS ? ios() : const AndroidCaInstall()));
              }),
          const Divider(indent: 0.2, height: 1),
          ListTile(
              title: Text(localizations.exportCA),
              onTap: () async {
                var caFile = await CertificateManager.certificateFile();
                _exportFile("ProxyPinCA.crt", file: caFile);
              }),
          ListTile(title: Text(localizations.exportCaP12), onTap: exportP12),
          ListTile(
              title: Text(localizations.exportPrivateKey),
              onTap: () async {
                var keyFile = await CertificateManager.privateKeyFile();
                _exportFile("ProxyPinKey.pem", file: keyFile);
              }),
          const Divider(indent: 0.2, height: 1),
          ListTile(title: Text(localizations.importCaP12), onTap: importPk12),
          const Divider(indent: 0.2, height: 1),
          ListTile(
              title: Text(localizations.generateCA),
              onTap: () async {
                showConfirmDialog(context, title: localizations.generateCA, content: localizations.generateCADescribe,
                    onConfirm: () async {
                  await CertificateManager.generateNewRootCA();
                  if (context.mounted) FlutterToastr.show(localizations.success, context);
                });
              }),
          const Divider(indent: 0.2, height: 1),
          ListTile(
              title: Text(localizations.resetDefaultCA),
              onTap: () async {
                showConfirmDialog(context,
                    title: localizations.resetDefaultCA,
                    content: localizations.resetDefaultCADescribe, onConfirm: () async {
                  await CertificateManager.resetDefaultRootCA();
                  if (context.mounted) FlutterToastr.show(localizations.success, context);
                });
              }),
        ]));
  }

  void importPk12() async {
    FilePickerResult? result =
        await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['p12', 'pfx']);
    if (result == null || !mounted) return;
    //entry password
    showDialog(
        context: context,
        builder: (BuildContext context) {
          String? password;
          return SimpleDialog(title: Text(localizations.importCaP12, style: const TextStyle(fontSize: 16)), children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: "Enter the password of the p12 file",
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) => password = val,
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(localizations.cancel)),
              TextButton(
                onPressed: () async {
                  var bytes = await result.files.single.xFile.readAsBytes();
                  try {
                    await CertificateManager.importPkcs12(bytes, password);
                    if (context.mounted) {
                      FlutterToastr.show(localizations.success, context);
                      Navigator.pop(context);
                    }
                  } catch (e, stackTrace) {
                    logger.e('import p12 error [$password]', error: e, stackTrace: stackTrace);
                    if (context.mounted) FlutterToastr.show(localizations.importFailed, context);
                    return;
                  }
                },
                child: Text(localizations.import),
              )
            ])
          ]);
        });
  }

  void exportP12() async {
    showDialog(
        context: context,
        builder: (BuildContext context) {
          String? password;
          return SimpleDialog(title: Text(localizations.exportCaP12, style: const TextStyle(fontSize: 16)), children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                decoration: const InputDecoration(
                  hintStyle: TextStyle(color: Colors.grey),
                  hintText: "Enter a password to protect p12 file",
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) => password = val,
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(localizations.cancel)),
              TextButton(
                onPressed: () async {
                  var p12Bytes =
                      await CertificateManager.generatePkcs12(password?.isNotEmpty == true ? password : null);
                  _exportFile("ProxyPinPkcs12.p12", bytes: p12Bytes);

                  if (context.mounted) Navigator.pop(context);
                },
                child: Text(localizations.export),
              )
            ])
          ]);
        });
  }

  Widget ios() {
    return Scaffold(
        appBar: AppBar(title: Text(localizations.installRootCa, style: const TextStyle(fontSize: 16))),
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextButton(onPressed: () => _downloadCert(), child: Text("1. ${localizations.downloadRootCa}")),
              TextButton(
                  onPressed: () {}, child: Text("2. ${localizations.installRootCa} -> ${localizations.trustCa}")),
              TextButton(onPressed: () {}, child: Text("2.1 ${localizations.installCaDescribe}")),
              Padding(
                  padding: const EdgeInsets.only(left: 15),
                  child: Image.network("https://foruda.gitee.com/images/1689346516243774963/c56bc546_1073801.png",
                      height: 400)),
              TextButton(onPressed: () {}, child: Text("2.2 ${localizations.trustCaDescribe}")),
              Padding(
                  padding: const EdgeInsets.only(left: 15),
                  child: Image.network("https://foruda.gitee.com/images/1689346614916658100/fd9b9e41_1073801.png",
                      height: 270)),
            ])));
  }

  void _downloadCert() async {
    CertificateManager.cleanCache();
    await widget.proxyServer.retryBind();
    launchUrl(Uri.parse("http://127.0.0.1:${widget.proxyServer.port}/ssl"), mode: LaunchMode.externalApplication);
  }

  void _exportFile(String name, {File? file, Uint8List? bytes}) async {
    bytes ??= await file!.readAsBytes();

    String? outputFile = await FilePicker.platform
        .saveFile(dialogTitle: 'Please select the path to save:', fileName: name, bytes: bytes);

    if (outputFile != null && mounted) {
      AppLocalizations localizations = AppLocalizations.of(context)!;
      FlutterToastr.show(localizations.success, context);
    }
  }
}

class AndroidCaInstall extends StatefulWidget {
  const AndroidCaInstall({super.key});

  @override
  State<StatefulWidget> createState() => _AndroidCaInstallState();
}

class _AndroidCaInstallState extends State<AndroidCaInstall> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            centerTitle: true,
            title: Text(localizations.installRootCa, style: const TextStyle(fontSize: 16)),
            bottom: TabBar(
                controller: _tabController,
                labelPadding: const EdgeInsets.symmetric(horizontal: 5),
                tabs: <Widget>[
                  Tab(text: localizations.androidRoot),
                  Tab(text: localizations.androidUserCA),
                ])),
        body: TabBarView(controller: _tabController, children: [rootCA(), userCA()]));
  }

  rootCA() {
    bool isCN = localizations.localeName == 'zh';
    return ListView(padding: const EdgeInsets.all(10), children: [
      Text(localizations.androidRootMagisk),
      TextButton(
          child: Text("https://${isCN ? 'gitee' : 'github'}.com/wanghongenpin/Magisk-ProxyPinCA/releases"),
          onPressed: () {
            launchUrl(Uri.parse("https://${isCN ? 'gitee' : 'github'}.com/wanghongenpin/Magisk-ProxyPinCA/releases"));
          }),
      const SizedBox(height: 15),
      futureWidget(
          CertificateManager.systemCertificateName(),
          (name) => SelectableText(localizations.androidRootRename(name),
              style: const TextStyle(fontWeight: FontWeight.w500))),
      const SizedBox(height: 10),
      FilledButton(
          onPressed: () async => _downloadCert(await CertificateManager.systemCertificateName()),
          child: Text(localizations.androidRootCADownload)),
      const SizedBox(height: 10),
      Text(
          "Android 13: ${isCN ? "将证书挂载到" : "Mount the certificate to"} '/system/etc/security/cacerts' ${isCN ? "目录" : "Directory"}"
              .fixAutoLines()),
      const SizedBox(height: 5),
      Text(
          "Android 14: ${isCN ? "将证书挂载到" : "Mount the certificate to"} '/apex/com.android.conscrypt/cacerts' ${isCN ? "目录" : "Directory"}"
              .fixAutoLines()),
      const SizedBox(height: 5),
      ClipRRect(
          child: Align(
              alignment: Alignment.topCenter,
              child: Image.network(
                scale: 0.5,
                "https://foruda.gitee.com/images/1710181660282752846/cb520c0b_1073801.png",
                height: 460,
              )))
    ]);
  }

  userCA() {
    bool isCN = localizations.localeName == 'zh';

    return ListView(padding: const EdgeInsets.all(10), children: [
      Text(localizations.androidUserCATips, style: const TextStyle(fontWeight: FontWeight.w500)),
      const SizedBox(height: 5),
      TextButton(
        style: const ButtonStyle(alignment: Alignment.centerLeft),
        onPressed: () {},
        child: Text("1. ${localizations.downloadRootCa} ", textAlign: TextAlign.left),
      ),
      FilledButton(onPressed: () => _downloadCert('ProxyPinCA.crt'), child: Text(localizations.downloadRootCa)),
      const SizedBox(height: 5),
      TextButton(onPressed: () {}, child: Text("2. ${localizations.androidUserCAInstall}")),
      TextButton(
          onPressed: () {
            launchUrl(Uri.parse(isCN
                ? "https://gitee.com/wanghongenpin/proxypin/wikis/%E5%AE%89%E5%8D%93%E6%97%A0ROOT%E4%BD%BF%E7%94%A8Xposed%E6%A8%A1%E5%9D%97%E6%8A%93%E5%8C%85"
                : "https://github.com/wanghongenpin/proxypin/wiki/Android-without-ROOT-uses-Xposed-module-to-capture-packets"));
          },
          child: Text(localizations.androidUserXposed)),
      ClipRRect(
          child: Align(
              alignment: Alignment.topCenter,
              heightFactor: .7,
              child: Image.network(
                "https://foruda.gitee.com/images/1689352695624941051/74e3bed6_1073801.png",
                height: 680,
              )))
    ]);
  }

  void _downloadCert(String name) async {
    var caFile = await CertificateManager.certificateFile();
    String? outputFile = await FilePicker.platform
        .saveFile(dialogTitle: 'Please select the path to save:', fileName: name, bytes: await caFile.readAsBytes());

    if (outputFile != null && mounted) {
      AppLocalizations localizations = AppLocalizations.of(context)!;
      FlutterToastr.show(localizations.success, context);
    }
  }
}
