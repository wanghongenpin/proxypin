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
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/native/native_method.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/util/cert/cert_data.dart';
import 'package:proxypin/network/util/crts.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/local_storage.dart';
import 'package:proxypin/storage/shared_preference_keys.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/mobile/menu/drawer.dart';
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

  // iOS CA status
  bool _loading = false;
  static bool _installed = false;
  static bool _trusted = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    if (Platform.isIOS && _trusted != true) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    setState(() => _loading = true);
    try {
      final caPem = await CertificateManager.certificatePem();
      if (Platform.isIOS) {
        final installedByKeychain = await NativeMethod.isCaInstalled(caPem);
        _trusted = await evaluateChainTrusted(caPem);
        _installed = installedByKeychain || _trusted;

        logger.d('[HTTPS] iOS CA status: installed=$_installed keychain=$installedByKeychain trusted=$_trusted');
      }
    } catch (e, st) {
      logger.e('[HTTPS] iOS CA status check error', error: e, stackTrace: st);
      _installed = false;
      _trusted = false;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    if (changed) {
      widget.proxyServer.configuration.flushConfig();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final borderColor = Theme.of(context).dividerColor.withValues(alpha: 0.13);
    final dividerColor = Theme.of(context).dividerColor.withValues(alpha: 0.22);

    Widget section(List<Widget> tiles) => Card(
          color: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(side: BorderSide(color: borderColor), borderRadius: BorderRadius.circular(10)),
          child: Column(children: tiles),
        );

    return Scaffold(
        appBar: AppBar(
          title: Text(localizations.httpsProxy, style: const TextStyle(fontSize: 16)),
          centerTitle: true,
        ),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          if (Platform.isIOS)
            (_loading)
                ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                : CertStatusCard(installed: _installed, trusted: _trusted, proxyServer: widget.proxyServer),
          // SSL toggle and install
          section([
            SwitchListTile(
                hoverColor: Colors.transparent,
                title: Text(localizations.enabledHttps),
                value: widget.proxyServer.enableSsl,
                onChanged: (val) {
                  widget.proxyServer.enableSsl = val;
                  widget.onEnableChange?.call(val);
                  CertificateManager.cleanCache();
                  setState(() {
                    changed = true;
                  });
                }),
            Divider(height: 0, thickness: 0.3, color: dividerColor),
            ListTile(
                title: Text(localizations.installRootCa),
                trailing: const Icon(Icons.keyboard_arrow_right),
                onTap: () async {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => Platform.isIOS
                              ? IosCaInstall(proxyServer: widget.proxyServer)
                              : const AndroidCaInstall())).whenComplete(() {
                    if (Platform.isIOS && !_trusted) _refreshStatus();
                  });
                }),
          ]),
          const SizedBox(height: 12),
          // Export options
          section([
            ListTile(
                title: Text(localizations.exportCA),
                onTap: () async {
                  final file = await CertificateManager.certificateFile();
                  _exportFile("ProxyPinCA.crt", file: file);
                }),
            Divider(height: 0, thickness: 0.3, color: dividerColor),
            ListTile(title: Text(localizations.exportCaP12), onTap: exportP12),
            Divider(height: 0, thickness: 0.3, color: dividerColor),
            ListTile(
                title: Text(localizations.exportPrivateKey),
                onTap: () async {
                  final file = await CertificateManager.privateKeyFile();
                  _exportFile("ProxyPinKey.pem", file: file);
                }),
          ]),
          const SizedBox(height: 12),
          // Import and generate/reset
          section([
            ListTile(title: Text(localizations.importCaP12), onTap: importPk12),
            Divider(height: 0, thickness: 0.3, color: dividerColor),
            ListTile(
                title: Text(localizations.generateCA),
                onTap: () async {
                  showConfirmDialog(context, title: localizations.generateCA, content: localizations.generateCADescribe,
                      onConfirm: () async {
                    await CertificateManager.generateNewRootCA();
                    if (mounted) FlutterToastr.show(localizations.success, context);
                    if (Platform.isIOS) _refreshStatus();
                  });
                }),
            Divider(height: 0, thickness: 0.3, color: dividerColor),
            ListTile(
                title: Text(localizations.resetDefaultCA),
                onTap: () async {
                  showConfirmDialog(context,
                      title: localizations.resetDefaultCA,
                      content: localizations.resetDefaultCADescribe, onConfirm: () async {
                    await CertificateManager.resetDefaultRootCA();
                    if (mounted) FlutterToastr.show(localizations.success, context);
                    if (Platform.isIOS) _refreshStatus();
                  });
                }),
          ]),
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

  ListView rootCA() {
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
        isCN ? "自动安装（需Root和system写权限，重启生效）" : "Auto install (Root & /system write, reboot required)",
        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
      ),
      FilledButton(
        onPressed: _autoInstallCert,
        child: Text(isCN ? "一键自动安装到系统" : "Auto install to system"),
      ),
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

  ListView userCA() {
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

  Future<void> _autoInstallCert() async {
    bool isEN = localizations.localeName == 'en';

    try {
      final caFile = await CertificateManager.certificateFile();
      final hash = await CertificateManager.systemCertificateName();
      String? destPath;
      final androidVersion = int.tryParse((await _getAndroidVersion()) ?? "");
      if (androidVersion != null && androidVersion >= 14) {
        destPath = '/apex/com.android.conscrypt/cacerts/$hash';
      } else {
        destPath = '/system/etc/security/cacerts/$hash';
      }
      final caPath = caFile.path;
      final shellCmd = 'cp $caPath $destPath && chmod 644 $destPath && chown root:root $destPath';
      final result = await Process.run('su', ['-c', shellCmd]);
      logger.d('Auto install cert result: ${result.stdout}, ${result.stderr}');
      if (!mounted) return;
      if (result.exitCode != 0) {
        FlutterToastr.show(
            isEN
                ? 'Certificate install failed. Please check root and /system write permission, or use Magisk module.'
                : '证书安装失败，请确认Root权限和system写权限，或参考Magisk模块安装。',
            context,
            rootNavigator: true,
            duration: 5);
        return;
      }
      FlutterToastr.show(
        isEN ? 'Certificate installed, reboot required' : '证书已安装，重启手机后生效',
        context,
        rootNavigator: true,
        duration: 5,
      );
    } catch (e) {
      logger.d('auto install cert error：$e');
      FlutterToastr.show(
          isEN
              ? 'Auto install failed: $e. Please check root and /system write permission, or use Magisk module.'
              : '自动安装失败：$e，请确认Root和system写权限，或参考Magisk模块安装。',
          context,
          rootNavigator: true,
          duration: 5);
    }
  }

  Future<String?> _getAndroidVersion() async {
    try {
      final result = await Process.run('getprop', ['ro.build.version.release']);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim().split(".")[0];
      }
    } catch (e) {
      logger.d('获取Android版本失败：$e');
    }
    return null;
  }
}

Future<bool> evaluateChainTrusted(String caPem) async {
  const host = 'example.com';
  final leafPem = await CertificateManager.generateLeafCertificatePem(host);
  return await NativeMethod.evaluateChainTrusted(leafPem, caPem, host: host);
}

class IOSCertChecker {
  static bool checked = false;

  static void check(BuildContext context) async {
    if (checked || !Platform.isIOS) {
      return;
    }
    logger.d("[IosCertChecker] checking iOS CA status");
    checked = true;

    if (ProxyServer.current?.enableSsl != true) {
      return;
    }
    if ((await LocalStorage.getBool(SharedPreferenceKeys.CERT_INSTALL_SKIP)) == true) {
      return;
    }
    final caPem = await CertificateManager.certificatePem();
    bool installed = await NativeMethod.isCaInstalled(caPem);
    bool trusted = false;
    if (installed) {
      trusted = await evaluateChainTrusted(caPem);
    }

    if ((!installed || !trusted) && context.mounted) {
      showDialog(
          context: context,
          builder: (context) {
            final localizations = AppLocalizations.of(context)!;
            return AlertDialog(
              titlePadding: EdgeInsets.zero,
              contentPadding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: Container(
                  constraints: const BoxConstraints(maxHeight: 185),
                  child: CertStatusCard(
                      installed: installed,
                      trusted: trusted,
                      margin: EdgeInsets.zero,
                      proxyServer: ProxyServer.current!)),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    LocalStorage.setBool(SharedPreferenceKeys.CERT_INSTALL_SKIP, true);
                    Navigator.pop(context);
                  },
                  child: Text(localizations.appUpdateIgnoreBtnTxt),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(localizations.cancel),
                ),
              ],
            );
          });
    }
  }
}

class CertStatusCard extends StatelessWidget {
  final bool installed;
  final bool trusted;
  final ProxyServer proxyServer;
  final EdgeInsetsGeometry? margin;

  const CertStatusCard({
    super.key,
    required this.installed,
    required this.trusted,
    required this.proxyServer,
    this.margin = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    final isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');
    Color color;
    IconData icon;
    String title;
    String subtitle;

    if (!installed) {
      color = Colors.red;
      icon = Icons.error_outline;
      title = isCN ? '证书未安装' : 'Certificate Not Installed';
      subtitle = isCN ? '点击“安装根证书”进行安装' : 'Tap "Install Root CA" to proceed';
    } else if (!trusted) {
      color = Colors.orange;
      icon = Icons.warning_amber_rounded;
      title = isCN ? '证书未信任' : 'Certificate Not Trusted';
      subtitle = AppLocalizations.of(context)!.trustCaDescribe;
    } else {
      return SizedBox();
    }

    return Card(
      margin: margin,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color))),
          ]),
          TextButton(
              onPressed: () {
                navigator(context, IosCaInstall(proxyServer: proxyServer));
              },
              child: Text(subtitle)),
        ]),
      ),
    );
  }
}

class IosCaInstall extends StatefulWidget {
  final ProxyServer proxyServer;

  const IosCaInstall({super.key, required this.proxyServer});

  @override
  State<IosCaInstall> createState() => _IosCaInstallState();
}

class _IosCaInstallState extends State<IosCaInstall> {
  bool loading = true;
  bool installed = false;
  bool trusted = false;
  X509CertificateData? certDetails;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    setState(() => loading = true);
    try {
      certDetails = CertificateManager.caCert ?? await CertificateManager.getCertificateDetails();
      final caPem = await CertificateManager.certificatePem();
      if (Platform.isIOS) {
        trusted = await evaluateChainTrusted(caPem);
        // Installation check: best-effort keychain lookup; if chain trusted, consider installed
        final installedByKeychain = await NativeMethod.isCaInstalled(caPem);
        installed = installedByKeychain || trusted;
      } else {
        installed = false;
        trusted = false;
      }
    } catch (e, st) {
      logger.e('iOS CA status check error', error: e, stackTrace: st);
      installed = false;
      trusted = false;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _downloadCert() async {
    logger.d('[IosCaInstall] user tapped download cert');
    CertificateManager.cleanCache();
    await widget.proxyServer.retryBind();
    final url = Uri.parse("http://127.0.0.1:${widget.proxyServer.port}/ssl");
    launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void _copyProxyLink() async {
    CertificateManager.cleanCache();
    await widget.proxyServer.retryBind();
    var urlStr = Uri.parse("http://127.0.0.1:${widget.proxyServer.port}/ssl").toString();
    Clipboard.setData(ClipboardData(text: urlStr)).then((_) {
      if (!mounted) {
        return;
      }
      FlutterToastr.show(localizations.copied, context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.installRootCa, style: const TextStyle(fontSize: 16)),
        actions: [IconButton(onPressed: _refreshStatus, icon: const Icon(Icons.refresh))],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(12), children: [
              _statusCard(isCN),
              // const SizedBox(height: 12),
              // _actionSection(isCN),
              const SizedBox(height: 24),
              _guideSection(isCN),
            ]),
    );
  }

  Widget _statusCard(bool isCN) {
    Color color;
    IconData icon;
    String title;
    String? subtitle;

    if (!installed) {
      color = Colors.red;
      icon = Icons.error_outline;
      title = isCN ? '证书未安装' : 'Certificate Not Installed';
      subtitle = '${localizations.download} & ${localizations.installCaDescribe}';
    } else if (!trusted) {
      color = Colors.orange;
      icon = Icons.warning_amber_rounded;
      title = isCN ? '证书未信任' : 'Certificate Not Trusted';
      subtitle = localizations.trustCaDescribe;
    } else {
      color = Colors.green;
      icon = Icons.verified_rounded;
      title = isCN ? '证书已安装并信任' : 'Certificate Installed & Trusted';
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color))),
          ]),
          const SizedBox(height: 8),
          if (subtitle != null) Text(subtitle),
          const SizedBox(height: 12),
          if (!installed) ...[
            Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(40), // Make button full width
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    onPressed: _downloadCert,
                    icon: const Icon(Icons.download),
                    label: Text(localizations.downloadRootCa))),
            TextButton.icon(
                onPressed: _copyProxyLink, icon: const Icon(Icons.link), label: Text(localizations.downloadRootCaNote))
          ],
          if (trusted && certDetails != null) ...[const Divider(height: 12), _certDetails(certDetails!)]
        ]),
      ),
    );
  }

  Widget _certDetails(X509CertificateData details) {
    final infoLabelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]);
    final infoValueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500);

    return Column(children: [
      const SizedBox(height: 6),
      _kv('Name', details.subject['2.5.4.3'] ?? 'ProxyPin CA', infoLabelStyle, infoValueStyle),
      const SizedBox(height: 6),
      _kv('Expires', details.validity.notAfter.toLocal().toString().split(' ').first, infoLabelStyle, infoValueStyle),
      // const SizedBox(height: 6),
      // _kv('Fingerprint', details.sha1Thumbprint ?? '-', infoLabelStyle, infoValueStyle),
    ]);
  }

  Widget _kv(String k, String v, TextStyle? ks, TextStyle? vs) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(k, style: ks),
      const Spacer(),
      Expanded(
          child: SelectableText(
        v,
        style: vs,
        textAlign: TextAlign.right,
        maxLines: 2,
        minLines: 1,
      ))
    ]);
  }

  Widget _guideSection(bool isCN) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(isCN ? '指引' : 'Guide', style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      TextButton(onPressed: () => _downloadCert(), child: Text("1. ${localizations.downloadRootCa}")),
      TextButton(onPressed: _copyProxyLink, child: Text(localizations.downloadRootCaNote)),
      TextButton(onPressed: () {}, child: Text("2. ${localizations.installRootCa} -> ${localizations.trustCa}")),
      TextButton(onPressed: () {}, child: Text("2.1 ${localizations.installCaDescribe}")),
      Padding(
          padding: const EdgeInsets.only(left: 15),
          child:
              Image.network("https://foruda.gitee.com/images/1689346516243774963/c56bc546_1073801.png", height: 400)),
      TextButton(onPressed: () {}, child: Text("2.2 ${localizations.trustCaDescribe}")),
      Padding(
          padding: const EdgeInsets.only(left: 15),
          child:
              Image.network("https://foruda.gitee.com/images/1689346614916658100/fd9b9e41_1073801.png", height: 270)),
    ]);
  }
}
