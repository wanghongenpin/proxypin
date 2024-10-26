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
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

///启动按钮
///@author wanghongen
///2023/10/8
class SocketLaunch extends StatefulWidget {
  static ValueNotifier<ValueWrap<bool>> startStatus = ValueNotifier(ValueWrap());

  final ProxyServer proxyServer;
  final int size;
  final bool startup; //默认是否启动
  final Function? onStart;
  final Function? onStop;

  final bool serverLaunch; //是否启动代理服务器

  const SocketLaunch(
      {super.key,
      required this.proxyServer,
      this.size = 25,
      this.onStart,
      this.onStop,
      this.startup = true,
      this.serverLaunch = true});

  @override
  State<StatefulWidget> createState() => _SocketLaunchState();
}

class _SocketLaunchState extends State<SocketLaunch> with WindowListener, WidgetsBindingObserver {
  AppLocalizations get localizations => AppLocalizations.of(context)!;
  bool started = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    //启动代理服务器
    if (widget.startup) {
      start();
    }
    if (Platforms.isDesktop()) {
      windowManager.setPreventClose(true);
    }
    SocketLaunch.startStatus.addListener(() {
      if (SocketLaunch.startStatus.value.get() == started) {
        return;
      }
      setState(() {
        started = SocketLaunch.startStatus.value.get() ?? started;
      });
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    logger.d("onWindowClose");
    await appExit();
  }

  Future<void> appExit() async {
    await widget.proxyServer.stop();
    started = false;
    await windowManager.destroy();
    exit(0);
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await appExit();
    return super.didRequestAppExit();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      logger.d('AppLifecycleState.detached');
      widget.onStop?.call();
      widget.proxyServer.stop();
      started = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    Color primaryColor = Theme.of(context).colorScheme.primary;
    return IconButton(
        tooltip: started ? localizations.stop : localizations.start,
        icon: Icon(started ? Icons.stop : Icons.play_arrow_sharp,
            color: started ? Colors.red : primaryColor, size: widget.size.toDouble()),
        onPressed: () async {
          if (started) {
            if (!widget.serverLaunch) {
              setState(() {
                widget.onStop?.call();
                started = !started;
              });
              return;
            }

            widget.proxyServer.stop().then((value) {
              widget.onStop?.call();
              setState(() {
                started = !started;
              });
            });
          } else {
            start();
          }
        });
  }

  ///启动代理服务器
  start() async {
    if (!widget.serverLaunch) {
      await widget.onStart?.call();
      setState(() {
        started = true;
      });
      return;
    }

    widget.proxyServer.start().then((value) {
      setState(() {
        started = true;
      });
      widget.onStart?.call();
    }).catchError((e) {
      String message = localizations.proxyPortRepeat(widget.proxyServer.port);
      FlutterToastr.show(message, context, duration: 3);
    });
  }
}
