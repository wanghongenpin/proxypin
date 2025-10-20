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
import 'package:proxypin/ui/configuration.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:proxypin/l10n/app_localizations.dart';

import '../../app_update/app_update_repository.dart';

/// 关于
class About extends StatefulWidget {
  const About({super.key});

  @override
  State<StatefulWidget> createState() {
    return _AboutState();
  }
}

class _AboutState extends State<About> {
  bool checkUpdating = false;

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    String gitHub = "https://github.com/wanghongenpin/proxypin";
    final String sponsorUrl = "https://github.com/sponsors/wanghongenpin";

    return Scaffold(
        appBar: AppBar(title: Text(localizations.about, style: const TextStyle(fontSize: 16)), centerTitle: true),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          const SizedBox(height: 6),
          Center(child: Text("ProxyPin", style: Theme.of(context).textTheme.headlineSmall)),
          const SizedBox(height: 10),
          Center(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(localizations.proxyPinSoftware, textAlign: TextAlign.center))),
          const SizedBox(height: 8),
          Center(child: Text("${localizations.version} ${AppConfiguration.version}")),
          const SizedBox(height: 12),
          Card(
              color: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.13)),
                  borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                ListTile(
                    title: const Text("GitHub"),
                    trailing: const Icon(Icons.open_in_new, size: 22),
                    onTap: () {
                      _safeLaunch(Uri.parse(gitHub));
                    }),
                Divider(height: 0, thickness: 0.4, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                ListTile(
                    title: Text(localizations.feedback),
                    trailing: const Icon(Icons.open_in_new, size: 22),
                    onTap: () {
                      _safeLaunch(Uri.parse("$gitHub/issues"));
                    }),
                Divider(height: 0, thickness: 0.4, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                ListTile(
                    title: Text(localizations.appUpdateCheckVersion),
                    trailing: checkUpdating
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync, size: 22),
                    onTap: () async {
                      if (checkUpdating) return;
                      setState(() => checkUpdating = true);
                      await AppUpdateRepository.checkUpdate(context, canIgnore: false, showToast: true);
                      if (mounted) setState(() => checkUpdating = false);
                    }),
                Divider(height: 0, thickness: 0.4, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                ListTile(
                    title: Text(localizations.download),
                    trailing: const Icon(Icons.open_in_new, size: 22),
                    onTap: () {
                      final url = "$gitHub/releases";
                      _safeLaunch(Uri.parse(url));
                    }),
                Divider(height: 0, thickness: 0.4, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                // Sponsor / Donate entry
                ListTile(
                  title: Text(localizations.sponsorDonate),
                  subtitle: Text(localizations.sponsorSupport, style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.favorite, color: Colors.redAccent, size: 22),
                  onTap: () => _showSponsorDialog(localizations, sponsorUrl),
                ),
              ]))
        ]));
  }

  Future<void> _safeLaunch(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showSponsorDialog(AppLocalizations l10n, String sponsorUrl) {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    List<Widget> sponsors = [
      ListTile(
        onTap: () => _safeLaunch(Uri.parse("https://afdian.com/a/proxypin")),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.favorite, color: Colors.pinkAccent),
        title: Text(l10n.sponsorAfdian),
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
          title: Text(l10n.sponsorDonate),
          contentPadding: const EdgeInsets.only(left: 20, top: 10, right: 20, bottom: 10),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(l10n.sponsorThanks), const SizedBox(height: 12), ...sponsors],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.close)),
          ],
        );
      },
    );
  }
}
