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
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/native/pip.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/utils/ip.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/listenable_list.dart';

/// Picture in Picture Window
class PictureInPictureWindow extends StatefulWidget {
  final ListenableList<HttpRequest> container;

  const PictureInPictureWindow(this.container, {super.key});

  @override
  State<PictureInPictureWindow> createState() => _PictureInPictureWindowState();
}

class _PictureInPictureWindowState extends State<PictureInPictureWindow> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  OnchangeListEvent<HttpRequest>? changeEvent;

  @override
  void initState() {
    super.initState();
    changeEvent = OnchangeListEvent(() {
      setState(() {});
    });
    widget.container.addListener(changeEvent!);
  }

  @override
  void dispose() {
    widget.container.removeListener(changeEvent!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.container.isEmpty) {
      return Material(child: Center(child: Text(localizations.emptyData, style: const TextStyle(color: Colors.grey))));
    }

    return Material(
        child: ListView.separated(
            padding: const EdgeInsets.only(left: 2),
            itemCount: widget.container.length,
            separatorBuilder: (context, index) => const Divider(thickness: 0.3, height: 0.5),
            itemBuilder: (context, index) {
              return Text.rich(
                  overflow: TextOverflow.ellipsis,
                  TextSpan(
                      text: widget.container.elementAt(widget.container.length - index - 1).requestUrl.fixAutoLines(),
                      style: const TextStyle(fontSize: 9)),
                  maxLines: 2);
            }));
  }
}

/// pip Icon
class PictureInPictureIcon extends StatefulWidget {
  final ProxyServer proxyServer;

  const PictureInPictureIcon(
    this.proxyServer, {
    super.key,
  });

  @override
  State<PictureInPictureIcon> createState() => _PictureInPictureState();
}

class _PictureInPictureState extends State<PictureInPictureIcon> {
  static double xPosition = -1;
  static double yPosition = -1;
  static Size? size;
  late final double _top;
  late final double _bottom;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();

    AppConfiguration.current?.pipIcon.addListener(() {
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (AppConfiguration.current?.pipIcon.value != true) return const SizedBox();

    size ??= MediaQuery.sizeOf(context);
    if (size == null || size!.isEmpty) {
      size = null;
      return const SizedBox();
    }

    if (xPosition == -1) {
      xPosition = size!.width - 48;
      yPosition = size!.height * 0.35;
      _top = MediaQuery.of(context).padding.top;
      _bottom = size!.height - 48 - (AppConfiguration.current?.bottomNavigation == false ? 0 : 56);
    }

    return Positioned(
      top: yPosition,
      left: xPosition,
      child: GestureDetector(
          onPanUpdate: (tapInfo) {
            // if (xPosition + tapInfo.delta.dx < 0) return;
            // if (yPosition + tapInfo.delta.dy < 0) return;

            setState(() {
              xPosition = (xPosition + tapInfo.delta.dx).clamp(0, size!.width);
              yPosition = (yPosition + tapInfo.delta.dy).clamp(_top, _bottom);
            });
          },
          child: IconButton(
              tooltip: localizations.windowMode,
              onPressed: () async {
                var configuration = widget.proxyServer.configuration;
                List<String>? appList = configuration.appWhitelistEnabled ? configuration.appWhitelist : [];
                List<String>? disallowApps;
                if (appList.isEmpty) {
                  disallowApps = configuration.appBlacklist ?? [];
                }

                PictureInPicture.enterPictureInPictureMode(
                    Platform.isAndroid ? await localIp() : "127.0.0.1", widget.proxyServer.port,
                    appList: appList, disallowApps: disallowApps);
              },
              icon: const Icon(Icons.picture_in_picture_alt))),
    );
  }
}
