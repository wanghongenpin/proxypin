import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/util/cert/cert_data.dart';
import 'package:proxypin/network/util/crts.dart';
import 'package:proxypin/storage/local_storage.dart';
import 'package:proxypin/ui/component/app_dialog.dart';
import 'package:proxypin/ui/desktop/ssl/cert_installer.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../storage/shared_preference_keys.dart';

class PCCertChecker {
  static bool checked = false;

  static void check(BuildContext context) async {
    if (checked || !Platforms.isDesktop()) {
      return;
    }

    checked = true;

    if (ProxyServer.current?.enableSsl != true || ProxyServer.current?.configuration.enableSystemProxy != true) {
      return;
    }

    if (_AutomaticInstallState.isCertInstalled.value == true) {
      return;
    }
    if ((await LocalStorage.getBool(SharedPreferenceKeys.CERT_INSTALL_SKIP)) == true) {
      return;
    }

    final cert = await CertificateManager.getCertificateDetails();
    final caFile = await CertificateManager.certificateFile();
    final installed = await CertInstaller.isCertInstalled(caFile, cert);
    if (!installed && context.mounted) {
      showDialog(
          barrierDismissible: false,
          context: context,
          builder: (context) {
            final localizations = AppLocalizations.of(context)!;
            return AlertDialog(
              content: _AutomaticInstall(),
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

class PCCert extends StatefulWidget {
  const PCCert({super.key});

  @override
  State<PCCert> createState() => _PCCertState();
}

class _PCCertState extends State<PCCert> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    return SimpleDialog(
      titlePadding: const EdgeInsets.symmetric(),
      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 15),
      title: Row(children: [
        const Expanded(child: SizedBox()),
        Text(isCN ? "安装证书" : "Install Certificate", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const Expanded(child: SizedBox()),
        Align(alignment: Alignment.topRight, child: CloseButton())
      ]),
      children: [
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: localizations.automatic),
            Tab(text: localizations.manual),
          ],
        ),
        SizedBox(
          width: 700,
          height: 470,
          child: TabBarView(
            controller: _tabController,
            children: [
              _AutomaticInstall(),
              _buildManualTab(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildManualTab(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildChildren(context),
          )),
    );
  }

  List<Widget> _buildChildren(BuildContext context) {
    if (Platform.isMacOS || Platform.isWindows) {
      return _buildWindowsAndMacContent(context);
    }
    return _buildLinuxContent(context);
  }

  List<Widget> _buildWindowsAndMacContent(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    return [
      isCN
          ? Text(" 安装证书到本系统，${Platform.isMacOS ? "安装完双击选择“始终信任此证书”。 如安装打开失败，请导出证书拖拽到系统证书里" : "选择“受信任的根证书颁发机构”"}")
          : Text(
              " Install certificate to this system，${Platform.isMacOS ? "After installation, double-click to select “Always Trust”。\n If installation and opening fail，Please export the certificate and drag it to the system certificate" : "choice“Trusted Root Certificate Authority”"}"),
      const SizedBox(height: 10),
      SizedBox(
          width: double.maxFinite,
          child: FilledButton(
              onPressed: () => _manualInstallCert(),
              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: Text(localizations.installRootCa))),
      const SizedBox(height: 10),
      Platform.isMacOS
          ? Image.network("https://foruda.gitee.com/images/1689323260158189316/c2d881a4_1073801.png",
              width: 800, height: 500)
          : Row(children: [
              Image.network("https://foruda.gitee.com/images/1689335589122168223/c904a543_1073801.png",
                  width: 370, height: 380),
              const SizedBox(width: 10),
              Image.network("https://foruda.gitee.com/images/1689335334688878324/f6aa3a3a_1073801.png",
                  width: 370, height: 380)
            ])
    ];
  }

  List<Widget> _buildLinuxContent(BuildContext context) {
    final isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    return [
      Text(isCN
          ? "安装证书到本系统，以Ubuntu为例 下载证书：\n"
              "先把证书复制到 /usr/local/share/ca-certificates/，然后执行 update-ca-certificates 即可。\n"
              "其他系统请网上搜索安装根证书"
          : "Install the certificate to this system), take Ubuntu as an example to download the certificate:\n"
              "First copy the certificate to /usr/local/share/ca-certificates/, and then execute update-ca-certificates.\n"
              "For other systems, please search online for installing root certificates."),
      const SizedBox(height: 5),
      Text(
          isCN
              ? "提示：FireFox有自己的信任证书库，所以要手动在设置中导入需要导入的证书。"
              : "Note: FireFox has its own trusted certificate library, so you need to manually import the required certificates in the settings.",
          style: TextStyle(fontSize: 12)),
      const SizedBox(height: 10),
      const SelectableText.rich(
          textAlign: TextAlign.justify,
          TextSpan(style: TextStyle(color: Color(0xff6a8759)), children: [
            TextSpan(text: "  sudo cp ProxyPinCA.crt /usr/local/share/ca-certificates/ \n"),
            TextSpan(text: "  sudo update-ca-certificates")
          ])),
      const SizedBox(height: 10)
    ];
  }

  void _manualInstallCert() async {
    var caFile = await CertificateManager.certificateFile();
    launchUrl(Uri.file(caFile.path)).then((_) {
      CertificateManager.cleanCache();
    });
  }
}

class _AutomaticInstall extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _AutomaticInstallState();
}

class _AutomaticInstallState extends State<_AutomaticInstall> {
  static final RxnBool isCertInstalled = RxnBool(null);
  X509CertificateData? certDetails;

  @override
  void initState() {
    super.initState();
    certDetails = CertificateManager.caCert;
    _checkCertStatus();

    if (certDetails == null) {
      CertificateManager.getCertificateDetails().then((value) => setState(() {
            certDetails = value;
          }));
    }
  }

  void _checkCertStatus() async {
    final details = certDetails ?? await CertificateManager.getCertificateDetails();
    final caFile = await CertificateManager.certificateFile();
    isCertInstalled.value = await CertInstaller.isCertInstalled(caFile, details);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16.0),
      child: Obx(() => Column(mainAxisSize: MainAxisSize.min, children: buildAutomaticChildren())),
    );
  }

  List<Widget> buildAutomaticChildren() {
    final localizations = AppLocalizations.of(context)!;
    final isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    final subtitleStyle = Theme.of(context).textTheme.bodyMedium;
    final infoLabelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]);
    final infoValueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500);
    List<Widget> children = [
      const SizedBox(height: 8),
      Text(isCN ? "通过安装并信任 ProxyPin CA" : "Install and Trust ProxyPin CA Certificate",
          style: subtitleStyle, textAlign: TextAlign.center),
      const SizedBox(height: 3),
      Text(
          isCN
              ? "ProxyPin 可以动态解密 HTTPS 流量以展示原始请求/响应。"
              : "ProxyPin can decrypt encrypted traffic on the fly and enable to see raw HTTPS requests and responses.",
          style: subtitleStyle,
          textAlign: TextAlign.center),
      const SizedBox(height: 45),
    ];

    if (isCertInstalled.value == false) {
      children.add(const SizedBox(height: 20));
      children.add(Icon(Icons.error_outline, color: Colors.red, size: 56));
      children.add(const SizedBox(height: 12));
      children.add(Text(localizations.certNotInstalled,
          textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)));
      children.add(const SizedBox(height: 20));
      children.add(
        FilledButton(
            onPressed: () => _installCert(context),
            style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 19)),
            child: Text(localizations.install)),
      );
    } else if (isCertInstalled.value == true) {
      children.add(Card(
        elevation: 2,
        color: Theme.brightnessOf(context) == Brightness.light ? Colors.grey[50] : Colors.grey[800],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 18.0),
          child: Column(children: [
            Icon(Icons.verified_rounded, color: Colors.green, size: 56),
            const SizedBox(height: 12),
            Text(isCN ? "证书已安装" : "Certificate Installed", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (certDetails != null) ...[
              const Divider(),
              const SizedBox(height: 8),
              // certificate details
              Row(children: [
                Text('Name', style: infoLabelStyle),
                Expanded(
                    child: SelectableText(certDetails!.subject['2.5.4.3'] ?? 'ProxyPin CA',
                        style: infoValueStyle, textAlign: TextAlign.right)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Text('Expires', style: infoLabelStyle),
                Expanded(
                    child: SelectableText(certDetails!.validity.notAfter.toLocal().toString().split(' ').first,
                        style: infoValueStyle, textAlign: TextAlign.right)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Text('Fingerprint', style: infoLabelStyle),
                Expanded(
                  child: SelectableText(certDetails!.sha1Thumbprint ?? '-',
                      style: infoValueStyle, textAlign: TextAlign.right),
                ),
              ])
            ]
          ]),
        ),
      ));
    }

    return children;
  }

  void _installCert(BuildContext context) async {
    final isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');
    var caFile = await CertificateManager.certificateFile();
    bool success = await CertInstaller.installCertificate(caFile);
    CertificateManager.cleanCache();

    if (!context.mounted) {
      return;
    }

    if (success) {
      isCertInstalled.value = true;
      CustomToast.success(isCN ? "证书安装成功" : "Certificate installed successfully").show(context);
    } else {
      isCertInstalled.value = false;
      final isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');
      CustomToast.error(isCN ? "证书安装失败，请尝试手动安装" : "Certificate installation failed, please try manual installation")
          .show(context);
    }
  }
}
