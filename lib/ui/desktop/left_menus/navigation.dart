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
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/ui/component/svg_icon.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/desktop/preference.dart';
import 'package:url_launcher/url_launcher.dart';

///左侧导航栏（设计稿 .rail / .ritem：宽 64，项 52x48 圆角 9，图标 19 + 标签 10）
/// @author wanghongen
/// 2024/8/6
class LeftNavigationBar extends StatefulWidget {
  final AppConfiguration appConfiguration;
  final ProxyServer proxyServer;
  final ValueNotifier<int> selectIndex;

  const LeftNavigationBar(
      {super.key, required this.appConfiguration, required this.proxyServer, required this.selectIndex});

  @override
  State<StatefulWidget> createState() => _LeftNavigationBarState();
}

class _LeftNavigationBarState extends State<LeftNavigationBar> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
        valueListenable: widget.selectIndex,
        builder: (_, index, __) {
          if (index == -1) {
            return const SizedBox();
          }

          var items = [
            (icon: 'list', label: localizations.navRequests),
            (icon: 'star', label: localizations.favorites),
            (icon: 'clock', label: localizations.history),
            (icon: 'wrench', label: localizations.toolbox),
          ];

          return Container(
            // 设计稿 64，实际观感偏宽收窄到 60；非中文标签长，76 → 72
            width: (localizations.localeName == 'zh' || localizations.localeName == 'zh_Hant') ? 60 : 72,
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(right: BorderSide(color: chromeBorderColor(Theme.of(context)), width: 1))),
            child: Column(children: <Widget>[
              const SizedBox(height: 10),
              for (var i = 0; i < items.length; i++)
                Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _RailItem(
                        icon: items[i].icon,
                        label: items[i].label,
                        active: index == i,
                        onTap: () => widget.selectIndex.value = i)),
              const Spacer(),
              _RailItem(
                  icon: 'gear',
                  label: localizations.preferenceShort,
                  compact: true,
                  onTap: () {
                    showDialog(
                        context: context,
                        builder: (_) => Preference(widget.appConfiguration, widget.proxyServer.configuration));
                  }),
              const SizedBox(height: 2),
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _RailItem(
                      icon: 'chat',
                      label: localizations.feedback,
                      compact: true,
                      onTap: () => launchUrl(Uri.parse("https://github.com/wanghongenpin/proxypin/issues")))),
            ]),
          );
        });
  }
}

/// 设计稿 .ritem（52x48 / 图标 19 / 标签 10）基础上略放大：56x52 圆角 9，图标 20px + 标签 10.5px，选中 primary-soft 底 + primary 字
class _RailItem extends StatelessWidget {
  final String icon;
  final String label;
  final bool active;

  /// 次级入口（底部 偏好/反馈）：纯图标无文案，弱化视觉层级（文案靠 tooltip）
  final bool compact;
  final VoidCallback onTap;

  const _RailItem(
      {required this.icon, required this.label, this.active = false, this.compact = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    // 设计稿 .ritem：未选中用 --text-3（暗黑 #6F747D），选中主色
    var color = active
        ? theme.colorScheme.primary
        : (theme.brightness == Brightness.light ? theme.colorScheme.onSurfaceVariant : DarkPalette.text3);
    return Tooltip(
        message: label,
        preferBelow: false,
        child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: onTap,
            child: Container(
                width: compact ? 36 : 56,
                height: compact ? 36 : 52,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    color: active ? primarySoftBg(theme) : null),
                child: compact
                    ? Center(child: SvgIcon(icon, size: 18, color: color))
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        SvgIcon(icon, size: 20, color: color),
                        const SizedBox(height: 4),
                        Text(label,
                            maxLines: 1,
                            style: TextStyle(
                                fontSize: 10.5,
                                height: 1.1,
                                color: color,
                                fontWeight: active ? FontWeight.w500 : FontWeight.w400)),
                      ]))));
  }
}
