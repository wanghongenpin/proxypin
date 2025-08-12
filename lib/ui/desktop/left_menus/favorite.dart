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

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:date_format/date_format.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/storage/favorites.dart';
import 'package:proxypin/ui/component/app_dialog.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/content/panel.dart';
import 'package:proxypin/ui/desktop/request/repeat.dart';
import 'package:proxypin/utils/curl.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/python.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../common.dart';

/// @author wanghongen
/// 2023/10/8
class Favorites extends StatefulWidget {
  final NetworkTabController panel;

  const Favorites({super.key, required this.panel});

  @override
  State<StatefulWidget> createState() {
    return _FavoritesState();
  }
}

class _FavoritesState extends State<Favorites> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    FavoriteStorage.addNotifier = () {
      setState(() {});
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: FavoriteStorage.favorites,
        builder: (BuildContext context, AsyncSnapshot<Queue<Favorite>> snapshot) {
          if (snapshot.hasData) {
            var favorites = snapshot.data ?? Queue();
            if (favorites.isEmpty) {
              return Center(child: Text(localizations.emptyFavorite));
            }

            return ListView.separated(
              itemCount: favorites.length,
              itemBuilder: (_, index) {
                var request = favorites.elementAt(index);
                return _FavoriteItem(
                  request,
                  index: index,
                  panel: widget.panel,
                  onRemove: (Favorite favorite) {
                    FavoriteStorage.removeFavorite(favorite);
                    CustomToast.success(localizations.deleteFavoriteSuccess).show(context);
                    setState(() {});
                  },
                );
              },
              separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.3),
            );
          } else {
            return const SizedBox();
          }
        });
  }
}

class _FavoriteItem extends StatefulWidget {
  final int index;
  final Favorite favorite;
  final NetworkTabController panel;
  final Function(Favorite favorite)? onRemove;

  const _FavoriteItem(this.favorite, {required this.panel, required this.onRemove, required this.index});

  @override
  State<_FavoriteItem> createState() => _FavoriteItemState();
}

class _FavoriteItemState extends State<_FavoriteItem> {
  //选择的节点
  static _FavoriteItemState? selectedState;

  bool selected = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    var request = widget.favorite.request;

    var response = widget.favorite.response;
    var title = '${request.method.name} ${request.requestUrl}'.fixAutoLines();
    var time = formatDate(request.requestTime, [mm, '-', d, ' ', HH, ':', nn, ':', ss]);

    return GestureDetector(
        onSecondaryLongPressDown: (details) => menu(details, request),
        child: ListTile(
            minLeadingWidth: 25,
            leading: getIcon(response),
            title: Text(widget.favorite.name ?? title, overflow: TextOverflow.ellipsis, maxLines: 2),
            subtitle: Text.rich(
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                TextSpan(children: [
                  TextSpan(text: '#${widget.index} ', style: const TextStyle(color: Colors.teal)),
                  TextSpan(
                      text:
                          '$time - [${response?.status.code ?? ''}]  ${response?.contentType.name.toUpperCase() ?? ''} ${response?.costTime() ?? ''} '),
                ])),
            selected: selected,
            dense: true,
            onTap: () => onClick(request)));
  }

  ///右键菜单
  menu(LongPressDownDetails details, HttpRequest request) {
    showContextMenu(
      context,
      details.globalPosition,
      items: <PopupMenuEntry>[
        popupItem(localizations.copyUrl, onTap: () {
          var requestUrl = request.requestUrl;
          Clipboard.setData(ClipboardData(text: requestUrl))
              .then((value) => FlutterToastr.show(localizations.copied, context));
        }),
        popupItem(localizations.copyRequestResponse, onTap: () {
          Clipboard.setData(ClipboardData(text: copyRequest(request, request.response)))
              .then((value) => FlutterToastr.show(localizations.copied, context));
        }),
        popupItem(localizations.copyCurl, onTap: () {
          Clipboard.setData(ClipboardData(text: curlRequest(request)))
              .then((value) => FlutterToastr.show(localizations.copied, context));
        }),
        popupItem(localizations.copyAsPythonRequests, onTap: () {
          Clipboard.setData(ClipboardData(text: copyAsPythonRequests(request)))
              .then((value) => FlutterToastr.show(localizations.copied, context));
        }),
        const PopupMenuDivider(height: 0.3),
        popupItem(localizations.repeat, onTap: () => onRepeat(request)),
        popupItem(localizations.customRepeat, onTap: () => showCustomRepeat(request)),
        popupItem(localizations.editRequest, onTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            requestEdit(request);
          });
        }),
        popupItem(localizations.requestRewrite, onTap: () => showRequestRewriteDialog(context, request)),
        const PopupMenuDivider(height: 0.3),
        popupItem(localizations.rename, onTap: () => rename(widget.favorite)),
        popupItem(localizations.deleteFavorite, onTap: () {
          widget.onRemove?.call(widget.favorite);
        })
      ],
    );
  }

  //显示高级重发
  showCustomRepeat(HttpRequest request) async {
    var prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    showDialog(
        context: context,
        builder: (BuildContext context) {
          return CustomRepeatDialog(onRepeat: () => onRepeat(request), prefs: prefs);
        });
  }

  onRepeat(HttpRequest request) {
    var httpRequest = request.copy(uri: request.requestUrl);
    var proxyInfo =
        widget.panel.proxyServer.isRunning ? ProxyInfo.of("127.0.0.1", widget.panel.proxyServer.port) : null;
    HttpClients.proxyRequest(httpRequest, proxyInfo: proxyInfo);

    if (mounted) {
      CustomToast.success(localizations.reSendRequest).show(context);
    }
  }

  PopupMenuItem popupItem(String text, {VoidCallback? onTap}) {
    return CustomPopupMenuItem(height: 35, onTap: onTap, child: Text(text, style: const TextStyle(fontSize: 13)));
  }

  //重命名
  rename(Favorite item) {
    String? name = item.name;
    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            content: TextFormField(
              initialValue: name,
              decoration: InputDecoration(label: Text(localizations.name)),
              onChanged: (val) => name = val,
            ),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(context), child: Text(localizations.cancel)),
              TextButton(
                child: Text(localizations.save),
                onPressed: () {
                  Navigator.maybePop(context);
                  setState(() {
                    item.name = name?.isEmpty == true ? null : name;
                    FavoriteStorage.flushConfig();
                  });
                },
              ),
            ],
          );
        });
  }

  ///请求编辑
  requestEdit(HttpRequest request) async {
    var size = MediaQuery.of(context).size;
    var ratio = 1.0;
    if (Platform.isWindows) {
      ratio = WindowManager.instance.getDevicePixelRatio();
    }

    final window = await DesktopMultiWindow.createWindow(jsonEncode(
      {'name': 'RequestEditor', 'request': request},
    ));
    window.setTitle(localizations.requestEdit);
    window
      ..setFrame(const Offset(100, 100) & Size(960 * ratio, size.height * ratio))
      ..center()
      ..show();
  }

  //点击事件
  void onClick(HttpRequest request) {
    if (selected) {
      return;
    }
    setState(() {
      selected = true;
    });

    //切换选中的节点
    if (selectedState?.mounted == true && selectedState != this) {
      selectedState?.setState(() {
        selectedState?.selected = false;
      });
    }
    selectedState = this;
    widget.panel.change(request, request.response);
  }
}
