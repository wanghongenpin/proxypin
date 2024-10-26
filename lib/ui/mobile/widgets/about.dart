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
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// 关于
class About extends StatelessWidget {
  const About({super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    String gitHub = "https://github.com/wanghongenpin/proxypin";
    return Scaffold(
        appBar: AppBar(title: Text(localizations.about, style: const TextStyle(fontSize: 16)), centerTitle: true),
        body: Column(
          children: [
            const SizedBox(height: 10),
            const Text("ProxyPin", style: TextStyle(fontSize: 20)),
            const SizedBox(height: 20),
            Padding(
                padding: const EdgeInsets.only(left: 10, right: 10),
                child: Text(isCN ? "全平台开源免费抓包软件" : "Full platform open source free capture HTTP(S) traffic software")),
            const SizedBox(height: 10),
            const Text("V1.1.5"),
            ListTile(
                title: const Text("Github"),
                trailing: const Icon(Icons.arrow_right),
                onTap: () {
                  launchUrl(Uri.parse(gitHub), mode: LaunchMode.externalApplication);
                }),
            ListTile(
                title: Text(localizations.feedback),
                trailing: const Icon(Icons.arrow_right),
                onTap: () {
                  launchUrl(Uri.parse("{$gitHub}/issues"), mode: LaunchMode.externalApplication);
                }),
            ListTile(
                title: Text(isCN ? "下载地址" : "Download"),
                trailing: const Icon(Icons.arrow_right),
                onTap: () {
                  launchUrl(
                      Uri.parse(
                          isCN ? "https://gitee.com/wanghongenpin/proxypin/releases" : "$gitHub/releases"),
                      mode: LaunchMode.externalApplication);
                })
          ],
        ));
  }
}
