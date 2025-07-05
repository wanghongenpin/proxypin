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
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/configuration.dart';

/// @author wanghongen
/// 2024/1/2
class Preference extends StatefulWidget {
  final Configuration configuration;
  final AppConfiguration appConfiguration;

  const Preference(this.appConfiguration, this.configuration, {super.key});

  @override
  State<StatefulWidget> createState() => _PreferenceState();
}

class _PreferenceState extends State<Preference> {
  late Configuration configuration;
  late AppConfiguration appConfiguration;

  final memoryCleanupController = TextEditingController();
  final memoryCleanupList = [null, 512, 1024, 2048, 4096];

  @override
  void initState() {
    super.initState();
    configuration = widget.configuration;
    appConfiguration = widget.appConfiguration;
    if (!memoryCleanupList.contains(appConfiguration.memoryCleanupThreshold)) {
      memoryCleanupController.text = appConfiguration.memoryCleanupThreshold.toString();
    }
  }

  @override
  void dispose() {
    memoryCleanupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    var titleStyle = Theme.of(context).textTheme.titleSmall;
    var subtitleStyle = TextStyle(fontSize: 12, color: Colors.grey);

    return AlertDialog(
        scrollable: true,
        title: Row(children: [
          const Icon(Icons.settings, size: 20),
          const SizedBox(width: 10),
          Text(localizations.preference, style: Theme.of(context).textTheme.titleMedium),
          const Expanded(child: Align(alignment: Alignment.topRight, child: CloseButton()))
        ]),
        content: SizedBox(
            width: 400,
            child: Column(children: [
              Row(children: [
                SizedBox(width: 100, child: Text("${localizations.language}: ", style: titleStyle)),
                DropdownButton<Locale>(
                    value: appConfiguration.language,
                    onChanged: (Locale? value) => appConfiguration.language = value,
                    focusColor: Colors.transparent,
                    items: [
                      DropdownMenuItem(value: null, child: Text(localizations.followSystem)),
                      const DropdownMenuItem(value: Locale.fromSubtags(languageCode: "zh"), child: Text("简体中文")),
                      const DropdownMenuItem(value: Locale.fromSubtags(languageCode: "zh", scriptCode: "Hant"), child: Text("繁體中文")),
                      const DropdownMenuItem(value: Locale.fromSubtags(languageCode: "en"), child: Text("English")),
                    ]),
              ]),
              //主题
              Row(children: [
                SizedBox(width: 100, child: Text("${localizations.theme}: ", style: titleStyle)),
                DropdownButton<ThemeMode>(
                    value: appConfiguration.themeMode,
                    onChanged: (ThemeMode? value) => appConfiguration.themeMode = value!,
                    focusColor: Colors.transparent,
                    items: [
                      DropdownMenuItem(value: ThemeMode.system, child: Text(localizations.followSystem)),
                      DropdownMenuItem(value: ThemeMode.light, child: Text(localizations.themeLight)),
                      DropdownMenuItem(value: ThemeMode.dark, child: Text(localizations.themeDark)),
                    ]),
              ]),
              Tooltip(
                  message: localizations.material3,
                  child: Row(
                    children: [
                      SizedBox(width: 100, child: Text("Material3: ", style: titleStyle)),
                      Transform.scale(
                          scale: 0.75,
                          child: Switch(
                            value: appConfiguration.useMaterial3,
                            onChanged: (bool value) => appConfiguration.useMaterial3 = value,
                          ))
                    ],
                  )),
              //主题颜色
              Row(children: [
                SizedBox(
                    width: 120,
                    child: Text("${localizations.themeColor}: ", style: titleStyle, textAlign: TextAlign.start)),
              ]),
              themeColor(context),
              const Divider(),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(localizations.autoStartup), //默认是否启动
                  subtitle: Text(localizations.autoStartupDescribe, style: subtitleStyle),
                  trailing: SwitchWidget(
                      scale: 0.75,
                      value: configuration.startup,
                      onChanged: (value) {
                        configuration.startup = value;
                        configuration.flushConfig();
                      })),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(localizations.headerExpanded),
                  subtitle: Text(localizations.headerExpandedSubtitle, style: subtitleStyle),
                  trailing: SwitchWidget(
                      scale: 0.75,
                      value: appConfiguration.headerExpanded,
                      onChanged: (value) {
                        appConfiguration.headerExpanded = value;
                        appConfiguration.flushConfig();
                      })),
              SizedBox(height: 5),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(localizations.memoryCleanup),
                  subtitle: Text(localizations.memoryCleanupSubtitle, style: subtitleStyle),
                  trailing: memoryCleanup(context, localizations)),

              SizedBox(height: 5),
            ])));
  }

  ///主题颜色
  Widget themeColor(BuildContext context) {
    return Wrap(
      children: ColorMapping.colors.entries.map((pair) {
        var dividerColor = Theme.of(context).focusColor;
        var background = appConfiguration.themeColor == pair.value ? dividerColor : Colors.transparent;

        return GestureDetector(
            onTap: () => appConfiguration.setThemeColor = pair.key,
            child: Tooltip(
              message: pair.key,
              child: Container(
                margin: const EdgeInsets.all(4.0),
                decoration: BoxDecoration(
                  color: background,
                  border: Border.all(color: Colors.transparent, width: 8),
                ),
                child: Dot(color: pair.value, size: 15),
              ),
            ));
      }).toList(),
    );
  }

  bool memoryCleanupOpened = false;

  ///内存清理
  Widget memoryCleanup(BuildContext context, AppLocalizations localizations) {
    try {
      return DropdownButton<int>(
          value: appConfiguration.memoryCleanupThreshold,
          onTap: () {
            memoryCleanupOpened = true;
          },
          onChanged: (val) {
            memoryCleanupOpened = false;
            setState(() {
              appConfiguration.memoryCleanupThreshold = val;
            });
            appConfiguration.flushConfig();
          },
          underline: Container(),
          items: [
            DropdownMenuItem(value: null, child: Text(localizations.unlimited)),
            const DropdownMenuItem(value: 512, child: Text("512M")),
            const DropdownMenuItem(value: 1024, child: Text("1024M")),
            const DropdownMenuItem(value: 2048, child: Text("2048M")),
            const DropdownMenuItem(value: 4096, child: Text("4096M")),
            DropdownMenuInputItem(
                controller: memoryCleanupController,
                child: Container(
                    constraints: BoxConstraints(maxWidth: 65, minWidth: 35),
                    child: TextField(
                        controller: memoryCleanupController,
                        onSubmitted: (value) {
                          setState(() {});
                          appConfiguration.memoryCleanupThreshold = int.tryParse(value);
                          appConfiguration.flushConfig();

                          if (memoryCleanupOpened) {
                            memoryCleanupOpened = false;
                            Navigator.pop(context);
                            return;
                          }
                        },
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(5),
                          FilteringTextInputFormatter.allow(RegExp("[0-9]"))
                        ],
                        decoration: InputDecoration(hintText: localizations.custom, suffixText: "M")))),
          ]);
    } catch (e) {
      appConfiguration.memoryCleanupThreshold = null;
      logger.e('memory button build error', error: e, stackTrace: StackTrace.current);
      return const SizedBox();
    }
  }
}

class DropdownMenuInputItem extends DropdownMenuItem<int> {
  final TextEditingController controller;

  @override
  int? get value => int.tryParse(controller.text) ?? 0;

  const DropdownMenuInputItem({super.key, required this.controller, required super.child});
}
