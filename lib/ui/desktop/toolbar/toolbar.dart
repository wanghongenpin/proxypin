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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/ui/component/svg_icon.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/desktop/toolbar/phone_connect.dart';
import 'package:proxypin/ui/desktop/toolbar/environment_switcher.dart';
import 'package:proxypin/ui/desktop/toolbar/quick_tools.dart';
import 'package:proxypin/ui/desktop/toolbar/weak_network_indicator.dart';
import 'package:proxypin/ui/desktop/setting/setting.dart';
import 'package:proxypin/ui/desktop/ssl/ssl.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/launch/launch.dart';
import 'package:proxypin/utils/ip.dart';
import 'package:window_manager/window_manager.dart';
import 'package:proxypin/l10n/app_localizations.dart';

import '../request/list.dart';

/// @author wanghongen
/// 2023/10/8
class Toolbar extends StatefulWidget {
  final ProxyServer proxyServer;
  final GlobalKey<DesktopRequestListState> requestListStateKey;

  const Toolbar(this.proxyServer, this.requestListStateKey, {super.key});

  @override
  State<StatefulWidget> createState() {
    return _ToolbarState();
  }
}

class _ToolbarState extends State<Toolbar> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  Future<void> _onClear() async {
    if (AppConfiguration.current?.clearConfirm != true) {
      widget.requestListStateKey.currentState?.clean();
      return;
    }

    showConfirmDialog(context, title: localizations.clearConfirm, onConfirm: () {
      widget.requestListStateKey.currentState?.clean();
    });
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(onKeyEvent);
  }

  bool onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }

    if (HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.escape)) {
      if (ModalRoute.of(context)?.isCurrent == false) {
        Navigator.maybePop(context);
        return true;
      }
    }

    if (HardwareKeyboard.instance.isMetaPressed && event.logicalKey == LogicalKeyboardKey.keyW) {
      windowManager.blur();
      return true;
    }

    if (HardwareKeyboard.instance.isMetaPressed && event.logicalKey == LogicalKeyboardKey.keyQ) {
      windowManager.close();
      windowManager.destroy();
      return true;
    }

    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(onKeyEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 设计稿 .toolbar：间距 6，图标 17px；顺序 代理/清空 | HTTPS | 快捷区 ⋯ / 手机 / 设置，右侧 弱网徽章 + 环境切换
    var iconColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(children: [
      Padding(padding: EdgeInsets.only(left: Platform.isMacOS ? 90 : 20)),
      SocketLaunch(proxyServer: widget.proxyServer, startup: widget.proxyServer.configuration.startup),
      const SizedBox(width: 6),
      // 设计稿 .tbtn：32x32 点击盒（IconButton 默认 48 会把图标撑得太散）
      IconButton(
          tooltip: localizations.clear,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
          icon: SvgIcon('trash', size: 17, color: iconColor),
          onPressed: _onClear),
      _sep(),
      SslWidget(proxyServer: widget.proxyServer), // SSL配置
      const SizedBox(width: 6),
      _sep(),
      QuickToolbar(proxyServer: widget.proxyServer), // 快捷工具栏
      const SizedBox(width: 6),
      IconButton(
          tooltip: localizations.mobileConnect,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
          icon: SvgIcon('phone', size: 17, color: iconColor),
          onPressed: () async {
            final ips = await localIps(readCache: false);
            phoneConnect(ips, widget.proxyServer.port);
          }),
      const SizedBox(width: 6),
      Setting(proxyServer: widget.proxyServer), // 设置
      const Spacer(),
      const WeakNetworkIndicator(), // 网络限制启用时显示徽章，未启用时隐藏
      const SizedBox(width: 6),
      const EnvironmentSwitcher(), // 环境变量切换器
      const Padding(padding: EdgeInsets.only(left: 10)),
    ]);
  }

  /// 设计稿 .tsep / .qt-div：1x20 分隔线
  Widget _sep() {
    return Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: chromeBorderColor(Theme.of(context)));
  }

  void phoneConnect(List<String> hosts, int port) {
    showDialog(
        context: context,
        builder: (context) {
          return PhoneConnect(proxyServer: widget.proxyServer, hosts: hosts);
        });
  }
}
