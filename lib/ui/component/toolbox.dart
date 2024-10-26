import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/ui/component/cert_hash.dart';
import 'package:proxypin/ui/component/encoder.dart';
import 'package:proxypin/ui/component/js_run.dart';
import 'package:proxypin/ui/component/multi_window.dart';
import 'package:proxypin/ui/component/qr_code_page.dart';
import 'package:proxypin/ui/component/regexp.dart';
import 'package:proxypin/ui/mobile/request/request_editor.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

class Toolbox extends StatefulWidget {
  final ProxyServer? proxyServer;

  const Toolbox({super.key, this.proxyServer});

  @override
  State<StatefulWidget> createState() {
    return _ToolboxState();
  }
}

class _ToolboxState extends State<Toolbox> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(thickness: 0.3),
          Row(children: [
            InkWell(
                onTap: httpRequest,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  child: Column(children: [
                    const Icon(Icons.http),
                    Text(localizations.httpRequest, style: const TextStyle(fontSize: 14)),
                  ]),
                )),
            const SizedBox(width: 10),
            InkWell(
                onTap: () async {
                  if (Platforms.isMobile()) {
                    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const JavaScript()));
                    return;
                  }

                  var size = MediaQuery.of(context).size;
                  var ratio = 1.0;
                  if (Platform.isWindows) {
                    ratio = WindowManager.instance.getDevicePixelRatio();
                  }

                  final window = await DesktopMultiWindow.createWindow(jsonEncode(
                    {'name': 'JavaScript'},
                  ));
                  window.setTitle('JavaScript');
                  window
                    ..setFrame(const Offset(100, 100) & Size(960 * ratio, size.height * ratio))
                    ..center()
                    ..show();
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  child: const Column(children: [Icon(Icons.javascript), SizedBox(height: 3), Text("JavaScript")]),
                )),
          ]),
          const Divider(thickness: 0.3),
          Text(localizations.encode, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          Row(
            children: [
              InkWell(
                  onTap: () => encodeWindow(EncoderType.url, context),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    child: const Column(children: [Icon(Icons.link), SizedBox(height: 3), Text(' URL')]),
                  )),
              const SizedBox(width: 10),
              InkWell(
                  onTap: () => encodeWindow(EncoderType.base64, context),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    child: const Column(children: [Icon(Icons.format_bold), SizedBox(height: 3), Text('Base64')]),
                  )),
              const SizedBox(width: 15),
              InkWell(
                  onTap: () => encodeWindow(EncoderType.unicode, context),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    child: const Column(children: [Icon(Icons.format_underline), SizedBox(height: 3), Text('Unicode')]),
                  )),
              const SizedBox(width: 15),
              InkWell(
                  onTap: () => encodeWindow(EncoderType.md5, context),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    child: const Column(children: [Icon(Icons.enhanced_encryption), SizedBox(height: 3), Text('MD5')]),
                  )),
            ],
          ),
          const Divider(thickness: 0.3),
          Text(localizations.other, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          Row(
            children: [
              IconText(
                  onTap: () async {
                    if (Platforms.isMobile()) {
                      Navigator.of(context).push(MaterialPageRoute(builder: (context) => const CertHashPage()));
                      return;
                    }
                    MultiWindow.openWindow(localizations.certHashName, 'CertHashPage');
                  },
                  icon: Icons.key,
                  text: localizations.certHashName),
              const SizedBox(width: 10),
              IconText(
                  onTap: () async {
                    if (Platforms.isMobile()) {
                      Navigator.of(context).push(MaterialPageRoute(builder: (context) => const RegExpPage()));
                      return;
                    }
                    MultiWindow.openWindow(localizations.regExp, 'RegExpPage', size: const Size(800, 720));
                  },
                  icon: Icons.code,
                  text: localizations.regExp),
              const SizedBox(width: 10),
              IconText(
                  onTap: () async {
                    if (Platforms.isMobile()) {
                      Navigator.of(context).push(MaterialPageRoute(builder: (context) => const QrCodePage()));
                      return;
                    }
                    MultiWindow.openWindow(localizations.qrCode, 'QrCodePage');
                  },
                  icon: Icons.qr_code_2,
                  text: localizations.qrCode),
            ],
          ),
        ],
      ),
    );
  }

  httpRequest() async {
    if (Platforms.isMobile()) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (context) => MobileRequestEditor(proxyServer: widget.proxyServer)));
      return;
    }

    var size = MediaQuery.of(context).size;
    var ratio = 1.0;
    if (Platform.isWindows) {
      ratio = WindowManager.instance.getDevicePixelRatio();
    }

    final window = await DesktopMultiWindow.createWindow(jsonEncode(
      {'name': 'RequestEditor'},
    ));
    window.setTitle(localizations.httpRequest);
    window
      ..setFrame(const Offset(100, 100) & Size(960 * ratio, size.height * ratio))
      ..center()
      ..show();
  }
}

class IconText extends StatelessWidget {
  final IconData icon;
  final String text;

  /// Called when the user taps this part of the material.
  final GestureTapCallback? onTap;

  const IconText({super.key, required this.icon, required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Column(children: [Icon(icon), SizedBox(height: 3), Text(text)]),
        ));
  }
}
