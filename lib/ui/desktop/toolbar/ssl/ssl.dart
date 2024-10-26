import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/util/crts.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/utils/ip.dart';
import 'package:url_launcher/url_launcher.dart';

class SslWidget extends StatefulWidget {
  final ProxyServer proxyServer;

  const SslWidget({super.key, required this.proxyServer});

  @override
  State<SslWidget> createState() => _SslState();
}

class _SslState extends State<SslWidget> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
        builder: (context, controller, child) {
          return IconButton(
              icon: widget.proxyServer.enableSsl
                  ? Icon(Icons.lock_open, size: 22)
                  : Icon(Icons.https_outlined, color: Colors.red, size: 22),
              tooltip: localizations.httpsProxy,
              onPressed: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              });
        },
        menuChildren: [
          _Switch(proxyServer: widget.proxyServer, onEnableChange: (val) => setState(() {})),
          item(localizations.installCaLocal, onPressed: pcCer),
          item("${localizations.installRootCa} iOS", onPressed: () async => iosCer(await localIp())),
          item("${localizations.installRootCa} Android", onPressed: () async => androidCer(await localIp())),
          const Divider(thickness: 0.3, height: 3),
          exportMenu(),
          const Divider(thickness: 0.3, height: 3),
          importMenu(),
          const Divider(thickness: 0.3, height: 3),
          item(localizations.generateCA, onPressed: () async {
            showConfirmDialog(context, title: localizations.generateCA, content: localizations.generateCADescribe,
                onConfirm: () async {
              await CertificateManager.generateNewRootCA();
              if (context.mounted) FlutterToastr.show(localizations.success, context);
            });
          }),
          const Divider(thickness: 0.3, height: 3),
          item(localizations.resetDefaultCA, onPressed: () async {
            showConfirmDialog(context,
                title: localizations.resetDefaultCA,
                content: localizations.resetDefaultCADescribe, onConfirm: () async {
              await CertificateManager.resetDefaultRootCA();
              if (context.mounted) FlutterToastr.show(localizations.success, context);
            });
          }),
        ]);
  }

  //import method
  Widget importMenu() {
    return item(localizations.importCaP12, onPressed: () async {
      FilePickerResult? result =
          await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['p12', 'pfx']);
      if (result == null || !mounted) return;

      //entry password
      showDialog(
          context: context,
          builder: (BuildContext context) {
            String? password;
            return SimpleDialog(
                title: Text(localizations.importCaP12, style: const TextStyle(fontSize: 16)),
                children: [
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
                        var file = File(result.files.single.path!);
                        var bytes = await file.readAsBytes();
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
    });
  }

  Widget exportMenu() {
    return SubmenuButton(
        menuChildren: [
          MenuItemButton(
              child: Padding(
                  padding: const EdgeInsets.only(left: 10, right: 10),
                  child: Text(localizations.exportCA, style: const TextStyle(fontSize: 14))),
              onPressed: () async {
                String? path = (await FilePicker.platform.saveFile(fileName: "ProxyPinCA.crt"));
                if (path == null) return;

                var caFile = await CertificateManager.certificateFile();
                await caFile.copy(path);
              }),
          const Divider(thickness: 0.3, height: 8),
          MenuItemButton(
              child: Padding(
                  padding: const EdgeInsets.only(left: 10, right: 10),
                  child: Text(localizations.exportCaP12, style: const TextStyle(fontSize: 14))),
              onPressed: () async {
                //show p12 password
                String? password;
                showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return SimpleDialog(
                          title: Text(localizations.exportCaP12, style: const TextStyle(fontSize: 16)),
                          children: [
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
                                  String? path = (await FilePicker.platform.saveFile(fileName: "ProxyPinPkcs12.p12"));
                                  if (path == null) return;

                                  var p12Bytes = await CertificateManager.generatePkcs12(
                                      password?.isNotEmpty == true ? password : null);
                                  await File(path).writeAsBytes(p12Bytes);
                                  if (context.mounted) Navigator.pop(context);
                                },
                                child: Text(localizations.export),
                              )
                            ])
                          ]);
                    });
              }),
          MenuItemButton(
              child: Padding(
                  padding: const EdgeInsets.only(left: 10, right: 10),
                  child: Text(localizations.exportPrivateKey, style: const TextStyle(fontSize: 14))),
              onPressed: () async {
                String? path = (await FilePicker.platform.saveFile(fileName: "ProxyPinKey.pem"));
                if (path == null) return;

                var keyFile = await CertificateManager.privateKeyFile();
                await keyFile.copy(path);
              }),
        ],
        child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(localizations.export, style: const TextStyle(fontSize: 14))));
  }

  Widget item(String text, {VoidCallback? onPressed}) {
    return MenuItemButton(
        onPressed: onPressed,
        child: Padding(
            padding: const EdgeInsets.only(left: 10, right: 5),
            child: Text(text, style: const TextStyle(fontSize: 14))));
  }

  void pcCer() async {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    List<Widget> list = [];
    if (Platform.isMacOS || Platform.isWindows) {
      list = [
        isCN
            ? Text(" 安装证书到本系统，${Platform.isMacOS ? "安装完双击选择“始终信任此证书”。 如安装打开失败，请导出证书拖拽到系统证书里" : "选择“受信任的根证书颁发机构”"}")
            : Text(" Install certificate to this system，${Platform.isMacOS ? "After installation, double-click to select “Always Trust”。\n"
                " If installation and opening fail，Please export the certificate and drag it to the system certificate" : "choice“Trusted Root Certificate Authority”"}"),
        const SizedBox(height: 10),
        FilledButton(onPressed: _installCert, child: Text(localizations.installRootCa)),
        const SizedBox(height: 10),
        Platform.isMacOS
            ? Image.network("https://foruda.gitee.com/images/1689323260158189316/c2d881a4_1073801.png",
                width: 800, height: 500)
            : Row(children: [
                Image.network("https://foruda.gitee.com/images/1689335589122168223/c904a543_1073801.png",
                    width: 400, height: 400),
                const SizedBox(width: 10),
                Image.network("https://foruda.gitee.com/images/1689335334688878324/f6aa3a3a_1073801.png",
                    width: 400, height: 400)
              ])
      ];
    } else {
      list.add(const Text("安装证书到本系统，以Ubuntu为例 下载证书：\n"
          "先把证书复制到 /usr/local/share/ca-certificates/，然后执行 update-ca-certificates 即可。\n"
          "其他系统请网上搜索安装根证书"));
      list.add(const SizedBox(height: 5));
      list.add(const Text("提示：FireFox有自己的信任证书库，所以要手动在设置中导入需要导入的证书。", style: TextStyle(fontSize: 12)));
      list.add(const SizedBox(height: 10));
      list.add(const SelectableText.rich(
          textAlign: TextAlign.justify,
          TextSpan(style: TextStyle(color: Color(0xff6a8759)), children: [
            TextSpan(text: "  sudo cp ProxyPinCA.crt /usr/local/share/ca-certificates/ \n"),
            TextSpan(text: "  sudo update-ca-certificates")
          ])));
      list.add(const SizedBox(height: 10));
    }

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return SimpleDialog(
              contentPadding: const EdgeInsets.all(16),
              title: Row(children: [
                Text(isCN ? "电脑HTTPS抓包配置" : "Computer HTTPS Packet Capture Configuration",
                    style: const TextStyle(fontSize: 16)),
                const Expanded(child: Align(alignment: Alignment.topRight, child: CloseButton()))
              ]),
              alignment: Alignment.center,
              children: list);
        });
  }

  void iosCer(String host) {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return SimpleDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
              contentPadding: const EdgeInsets.all(16),
              title: Row(children: [
                Text("iOS ${localizations.caInstallGuide}", style: const TextStyle(fontSize: 16)),
                const Expanded(child: Align(alignment: Alignment.topRight, child: CloseButton()))
              ]),
              alignment: Alignment.center,
              children: [
                SelectableText.rich(
                    TextSpan(text: "1. ${localizations.configWifiProxy} Host：$host  Port：${widget.proxyServer.port}")),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text("2. ${localizations.caIosBrowser}\t"),
                    const SelectableText.rich(
                        TextSpan(text: "http://proxy.pin/ssl", style: TextStyle(decoration: TextDecoration.underline)))
                  ],
                ),
                const SizedBox(height: 10),
                Text("3. ${localizations.installRootCa} -> ${localizations.trustCa}"),
                const SizedBox(height: 10),
                Row(children: [
                  Column(children: [
                    Text("3.1 ${localizations.installCaDescribe}", style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 10),
                    Image.network("https://foruda.gitee.com/images/1689346516243774963/c56bc546_1073801.png",
                        height: 270, width: 300)
                  ]),
                  const SizedBox(width: 10),
                  Column(children: [
                    Text("3.2 ${localizations.trustCaDescribe}", style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 10),
                    Image.network("https://foruda.gitee.com/images/1689346614916658100/fd9b9e41_1073801.png",
                        height: 270, width: 300)
                  ])
                ])
              ]);
        });
  }

  void androidCer(String host) {
    bool isCN = localizations.localeName == 'zh';

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
              contentPadding: const EdgeInsets.all(5),
              title: Row(children: [
                Text("Android ${localizations.caInstallGuide}", style: const TextStyle(fontSize: 16)),
                const Expanded(child: Align(alignment: Alignment.topRight, child: CloseButton()))
              ]),
              content: SizedBox(
                  width: 600,
                  child: DefaultTabController(
                      length: 2,
                      child: Scaffold(
                        appBar: TabBar(tabs: <Widget>[
                          Tab(text: localizations.androidRoot),
                          Tab(text: localizations.androidUserCA),
                        ]),
                        body: Padding(
                            padding: const EdgeInsets.all(10),
                            child: TabBarView(children: [
                              ListView(children: [
                                Text(localizations.androidRootMagisk),
                                TextButton(
                                    child: Text(
                                        "https://${isCN ? 'gitee' : 'github'}.com/wanghongenpin/Magisk-ProxyPinCA/releases"),
                                    onPressed: () {
                                      launchUrl(Uri.parse(
                                          "https://${isCN ? 'gitee' : 'github'}.com/wanghongenpin/Magisk-ProxyPinCA/releases"));
                                    }),
                                const SizedBox(height: 10),
                                futureWidget(CertificateManager.systemCertificateName(),
                                    (name) => SelectableText(localizations.androidRootRename(name))),
                                const SizedBox(height: 10),
                                ClipRRect(
                                    child: Align(
                                        alignment: Alignment.topCenter,
                                        child: Image.network(
                                          scale: 0.5,
                                          "https://foruda.gitee.com/images/1710181660282752846/cb520c0b_1073801.png",
                                          height: 460,
                                        )))
                              ]),
                              ListView(
                                children: [
                                  Text(localizations.androidUserCATips,
                                      style: const TextStyle(fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 10),
                                  SelectableText.rich(TextSpan(
                                      text:
                                          "1. ${localizations.configWifiProxy} Host：$host  Port：${widget.proxyServer.port}")),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Text("2. ${localizations.caAndroidBrowser}\t"),
                                      const SelectableText.rich(TextSpan(
                                          text: "http://proxy.pin/ssl",
                                          style: TextStyle(decoration: TextDecoration.underline)))
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text("3. ${localizations.androidUserCAInstall}"),
                                  const SizedBox(height: 10),
                                  TextButton(
                                      onPressed: () {
                                        launchUrl(Uri.parse(isCN
                                            ? "https://gitee.com/wanghongenpin/proxypin/wikis/%E5%AE%89%E5%8D%93%E6%97%A0ROOT%E4%BD%BF%E7%94%A8Xposed%E6%A8%A1%E5%9D%97%E6%8A%93%E5%8C%85"
                                            : "https://github.com/wanghongenpin/proxypin/wiki/Android-without-ROOT-uses-Xposed-module-to-capture-packets"));
                                      },
                                      child: Text(" ${localizations.androidUserXposed}")),
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                      child: Align(
                                          alignment: Alignment.topCenter,
                                          heightFactor: .7,
                                          child: Image.network(
                                            "https://foruda.gitee.com/images/1689352695624941051/74e3bed6_1073801.png",
                                            height: 530,
                                          )))
                                ],
                              ),
                            ])),
                      ))));
        });
  }

  void _installCert() async {
    var caFile = await CertificateManager.certificateFile();
    launchUrl(Uri.file(caFile.path)).then((value) => CertificateManager.cleanCache());
  }
}

class _Switch extends StatefulWidget {
  final ProxyServer proxyServer;
  final Function(bool val) onEnableChange;

  const _Switch({required this.proxyServer, required this.onEnableChange});

  @override
  State<_Switch> createState() => _SwitchState();
}

class _SwitchState extends State<_Switch> {
  bool changed = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return MenuItemButton(
        onPressed: () {},
        child: Row(children: [
          Padding(
              padding: const EdgeInsets.only(left: 10, right: 5),
              child: Text(localizations.enabledHttps, style: const TextStyle(fontSize: 14))),
          Transform.scale(
              scale: 0.8,
              child: Switch(
                  hoverColor: Colors.transparent,
                  value: widget.proxyServer.enableSsl,
                  onChanged: (val) {
                    widget.proxyServer.enableSsl = val;
                    changed = true;
                    widget.onEnableChange(val);
                    CertificateManager.cleanCache();
                    setState(() {});
                  }))
        ]));
  }

  @override
  void dispose() {
    super.dispose();
    if (changed) {
      widget.proxyServer.configuration.flushConfig();
    }
  }
}
