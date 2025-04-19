import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
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
        Align(alignment: Alignment.topRight, child: CloseButton())
      ]),
      content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("ProxyPin", style: TextStyle(fontSize: 20)),
              const SizedBox(height: 10),
              Padding(
                  padding: const EdgeInsets.only(left: 10, right: 10),
                  child:
                      Text(isCN ? "全平台开源免费抓包软件" : "Full platform open source free capture HTTP(S) traffic software")),
              const SizedBox(height: 10),
              Text("v${AppConfiguration.version}"),
              const SizedBox(height: 10),
              ListTile(
                  title: Text('GitHub'),
                  trailing: const Icon(Icons.open_in_new, size: 22),
                  onTap: () => launchUrl(Uri.parse(gitHub))),
              ListTile(
                  title: Text(localizations.feedback),
                  trailing: const Icon(Icons.open_in_new, size: 22),
                  onTap: () => launchUrl(Uri.parse("$gitHub/issues"))),
              ListTile(
                  title: Text(localizations.appUpdateCheckVersion),
                  trailing: checkUpdating
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator())
                      : const Icon(Icons.sync, size: 22),
                  onTap: () async {
                    if (checkUpdating) {
                      return;
                    }
                    setState(() {
                      checkUpdating = true;
                    });
                    await AppUpdateRepository.checkUpdate(context, canIgnore: false, showToast: true);
                    setState(() {
                      checkUpdating = false;
                    });
                  }),
              ListTile(
                  title: Text(isCN ? "下载地址" : "Download"),
                  trailing: const Icon(Icons.open_in_new, size: 22),
                  onTap: () => launchUrl(
                      Uri.parse(isCN ? "https://gitee.com/wanghongenpin/proxypin/releases" : "$gitHub/releases")))
            ],
          )),
    );
  }
}
