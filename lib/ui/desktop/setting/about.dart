import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/app_update/app_update_repository.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:url_launcher/url_launcher.dart';

class DesktopAbout extends StatefulWidget {
  const DesktopAbout({super.key});

  @override
  State<StatefulWidget> createState() {
    return _AppUpdateStateChecking();
  }
}

class _AppUpdateStateChecking extends State<DesktopAbout> {
  bool checkUpdating = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');
    String gitHub = "https://github.com/wanghongenpin/proxypin";

    return AlertDialog(
      titlePadding: const EdgeInsets.only(left: 20, top: 10, right: 15),
      title: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Expanded(child: SizedBox()),
        Text(localizations.about, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        const Expanded(child: SizedBox()),
        const Align(alignment: Alignment.topRight, child: CloseButton())
      ]),
      content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("ProxyPin", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: .5)),
              const SizedBox(height: 10),
              Padding(
                  padding: const EdgeInsets.only(left: 10, right: 10),
                  child: Text(isCN ? "全平台开源免费抓包软件" : "Full platform open source free capture HTTP(S) traffic software",
                      textAlign: TextAlign.center, style: const TextStyle(height: 1.3))),
              const SizedBox(height: 10),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text("Version ${AppConfiguration.version}",
                      style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.primary,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
              ListTile(
                  dense: true,
                  title: const Text('GitHub'),
                  trailing: const Icon(Icons.open_in_new, size: 21),
                  onTap: () => _safeLaunch(Uri.parse(gitHub))),
              ListTile(
                  dense: true,
                  title: Text(localizations.feedback),
                  trailing: const Icon(Icons.open_in_new, size: 21),
                  onTap: () => _safeLaunch(Uri.parse("$gitHub/issues"))),
              ListTile(
                  dense: true,
                  title: Text(localizations.appUpdateCheckVersion),
                  trailing: checkUpdating
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync, size: 21),
                  onTap: () async {
                    if (checkUpdating) return;
                    setState(() => checkUpdating = true);
                    await AppUpdateRepository.checkUpdate(context, canIgnore: false, showToast: true);
                    if (mounted) setState(() => checkUpdating = false);
                  }),
              ListTile(
                  dense: true,
                  title: Text(isCN ? "下载地址" : "Download"),
                  trailing: const Icon(Icons.open_in_new, size: 21),
                  onTap: () => _safeLaunch(
                      Uri.parse(isCN ? "https://gitee.com/wanghongenpin/proxypin/releases" : "$gitHub/releases"))),
              ListTile(
                dense: true,
                title: Text(localizations.sponsorDonate),
                subtitle: Text(localizations.sponsorSupport, style: const TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.favorite, color: Colors.redAccent, size: 21),
                onTap: () => _showSponsorDialog(),
              ),
            ],
          )),
    );
  }

  Future<void> _safeLaunch(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showSponsorDialog() {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');
    List<Widget> sponsors = [
      ListTile(
        onTap: () => _safeLaunch(Uri.parse("https://afdian.com/a/proxypin")),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.favorite, color: Colors.pinkAccent),
        title: Text(localizations.sponsorAfdian),
      )
    ];

    final coffee = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.coffee, color: Colors.brown),
      title: Text('Buy Me a Coffee'),
      onTap: () => _safeLaunch(Uri.parse("https://buymeacoffee.com/proxypin")),
    );
    if (isCN) {
      sponsors.add(coffee);
    } else {
      sponsors.insert(0, coffee);
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(localizations.sponsorDonate),
          contentPadding: const EdgeInsets.only(left: 20, top: 10, right: 20, bottom: 10),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(localizations.sponsorThanks, style: const TextStyle(height: 1.4)),
                const SizedBox(height: 16),
                ...sponsors
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(localizations.close)),
          ],
        );
      },
    );
  }
}
