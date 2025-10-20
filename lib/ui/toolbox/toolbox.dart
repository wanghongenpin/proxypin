import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/ui/component/multi_window.dart';
import 'package:proxypin/ui/mobile/request/request_editor.dart';
import 'package:proxypin/ui/toolbox/qr_code_page.dart';
import 'package:proxypin/ui/toolbox/regexp.dart';
import 'package:proxypin/ui/toolbox/timestamp.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

import 'aes_page.dart';
import 'cert_hash.dart';
import 'encoder.dart';
import 'js_run.dart';

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
    return IconTheme(
        data: IconTheme.of(context).copyWith(color: IconTheme.of(context).color?.withValues(alpha: 0.65), size: 22),
        child: SingleChildScrollView(
            child: Container(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top quick actions
              Wrap(
                spacing: 6,
                children: [
                  IconText(
                    icon: Icons.http,
                    text: "HTTP",
                    onTap: httpRequest,
                    tooltip: localizations.httpRequest,
                  ),
                  IconText(
                    icon: Icons.javascript,
                    text: 'JavaScript',
                    tooltip: 'JavaScript',
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
                  ),
                ],
              ),
              const Divider(thickness: 0.3),
              Text(localizations.encode, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Wrap(
                spacing: 6,
                children: [
                  IconText(
                    onTap: () => encodeWindow(EncoderType.url, context),
                    icon: Icons.link,
                    text: 'URL',
                    tooltip: 'URL Encode/Decode',
                  ),
                  IconText(
                    onTap: () => encodeWindow(EncoderType.base64, context),
                    icon: Icons.format_bold_outlined,
                    text: 'Base64',
                    tooltip: 'Base64 Encode/Decode',
                  ),
                  IconText(
                    onTap: () => encodeWindow(EncoderType.unicode, context),
                    icon: Icons.format_underline_outlined,
                    text: 'Unicode',
                    tooltip: 'Unicode Encode/Decode',
                  ),
                  IconText(
                    onTap: () => encodeWindow(EncoderType.md5, context),
                    icon: Icons.tag_outlined,
                    text: 'MD5',
                    tooltip: 'MD5 Hash',
                  ),
                ],
              ),
              const Divider(thickness: 0.3),
              Text(localizations.cipher, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Wrap(
                spacing: 6,
                children: [
                  IconText(
                    onTap: () {
                      if (Platforms.isMobile()) {
                        Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AesPage()));
                        return;
                      }
                      MultiWindow.openWindow("AES", "AesPage", size: const Size(700, 672));
                    },
                    icon: Icons.enhanced_encryption_outlined,
                    text: 'AES',
                    tooltip: 'AES Encrypt/Decrypt',
                  ),
                ],
              ),
              const Divider(thickness: 0.3),
              Text(localizations.other, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Wrap(
                spacing: 6,
                children: [
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TimestampPage()));
                          return;
                        }

                        MultiWindow.openWindow(localizations.timestamp, 'TimestampPage', size: const Size(700, 350));
                      },
                      icon: Icons.av_timer,
                      text: localizations.timestamp,
                      tooltip: localizations.timestamp),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const CertHashPage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.certHashName, 'CertHashPage');
                      },
                      icon: Icons.key_outlined,
                      text: localizations.certHashName,
                      tooltip: localizations.certHashName),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const RegExpPage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.regExp, 'RegExpPage', size: const Size(800, 720));
                      },
                      icon: Icons.code,
                      text: localizations.regExp,
                      tooltip: localizations.regExp),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const QrCodePage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.qrCode, 'QrCodePage');
                      },
                      icon: Icons.qr_code_2,
                      text: localizations.qrCode,
                      tooltip: localizations.qrCode),
                ],
              ),
            ],
          ),
        )));
  }

  Future<void> httpRequest() async {
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
  final String? tooltip;

  /// Called when the user taps this part of the material.
  final GestureTapCallback? onTap;

  const IconText({super.key, required this.icon, required this.text, this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = text;
    return Tooltip(
      message: tooltip ?? label,
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: theme.colorScheme.primary.withValues(alpha: 0.06),
          splashColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            constraints: const BoxConstraints(minWidth: 92),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
