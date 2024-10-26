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
import 'dart:io';

import 'package:date_format/date_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/components/rewrite/request_rewrite_manager.dart';
import 'package:proxypin/network/components/rewrite/rewrite_rule.dart';
import 'package:proxypin/network/components/script_manager.dart';
import 'package:proxypin/network/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http_client.dart';
import 'package:proxypin/storage/favorites.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/content/panel.dart';
import 'package:proxypin/ui/mobile/request/repeat.dart';
import 'package:proxypin/ui/mobile/request/request_editor.dart';
import 'package:proxypin/ui/mobile/setting/request_rewrite.dart';
import 'package:proxypin/ui/mobile/setting/script.dart';
import 'package:proxypin/utils/curl.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 收藏列表页面
/// @author WangHongEn
class MobileFavorites extends StatefulWidget {
  final ProxyServer proxyServer;

  const MobileFavorites({super.key, required this.proxyServer});

  @override
  State<StatefulWidget> createState() {
    return _FavoritesState();
  }
}

class _FavoritesState extends State<MobileFavorites> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text(localizations.favorites, style: const TextStyle(fontSize: 16)), centerTitle: true),
        body: FutureBuilder(
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
                    var favorite = favorites.elementAt(index);
                    return _FavoriteItem(
                      favorite,
                      index: index,
                      onRemove: (Favorite favorite) async {
                        await FavoriteStorage.removeFavorite(favorite);
                        setState(() {});
                      },
                      proxyServer: widget.proxyServer,
                    );
                  },
                  separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.3),
                );
              } else {
                return const SizedBox();
              }
            }));
  }
}

class _FavoriteItem extends StatefulWidget {
  final int index;
  final Favorite favorite;
  final ProxyServer proxyServer;
  final Function(Favorite favorite)? onRemove;

  const _FavoriteItem(this.favorite, {required this.onRemove, required this.proxyServer, required this.index});

  @override
  State<_FavoriteItem> createState() => _FavoriteItemState();
}

class _FavoriteItemState extends State<_FavoriteItem> {
  late HttpRequest request;
  bool selected = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    request = widget.favorite.request;
  }

  @override
  Widget build(BuildContext context) {
    request = widget.favorite.request;

    var response = request.response;
    Widget? title = widget.favorite.name?.isNotEmpty == true
        ? Text(widget.favorite.name!,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(fontSize: 14, color: Colors.blueAccent.shade200))
        : Text.rich(
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            TextSpan(children: [
              TextSpan(text: '${request.method.name} ', style: const TextStyle(fontSize: 14, color: Colors.teal)),
              TextSpan(
                text: request.remoteDomain(),
                style: TextStyle(fontSize: 14, color: Colors.blue),
              ),
              TextSpan(
                text: request.path,
                style: TextStyle(fontSize: 14, color: Colors.green),
              ),
              if (request.requestUri?.query.isNotEmpty == true)
                TextSpan(
                    text: '?${request.requestUri?.query}',
                    style: TextStyle(fontSize: 14, color: Colors.pinkAccent.shade200))
            ]));

    var time = formatDate(request.requestTime, [mm, '-', d, ' ', HH, ':', nn, ':', ss]);
    String subtitle =
        '$time - [${response?.status.code ?? ''}]  ${response?.contentType.name.toUpperCase() ?? ''} ${response?.costTime() ?? ''} ';

    return GestureDetector(
        onLongPressStart: menu,
        child: ListTile(
            selected: selected,
            minLeadingWidth: 25,
            leading: getIcon(response),
            title: title,
            subtitle: Text.rich(
                maxLines: 1,
                TextSpan(children: [
                  TextSpan(text: '#${widget.index} ', style: const TextStyle(fontSize: 12, color: Colors.teal)),
                  TextSpan(text: subtitle, style: const TextStyle(fontSize: 12)),
                ])),
            dense: true,
            onTap: onClick));
  }

  ///右键菜单
  menu(details) {
    // setState(() {
    //   selected = true;
    // });

    var globalPosition = details.globalPosition;
    MediaQueryData mediaQuery = MediaQuery.of(context);
    var position = RelativeRect.fromLTRB(globalPosition.dx, globalPosition.dy, globalPosition.dx, globalPosition.dy);
    // Trigger haptic feedback
    if (Platform.isAndroid) HapticFeedback.mediumImpact();

    showMenu(
        context: context,
        constraints: BoxConstraints(maxWidth: mediaQuery.size.width * 0.88),
        position: position,
        items: [
          //复制url
          PopupMenuContainer(
              child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                    padding: EdgeInsets.only(left: 20, top: 5),
                    child: Text(localizations.selectAction, style: Theme.of(context).textTheme.bodyLarge)),
              ),
              //copy
              menuItem(
                left: itemButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: request.requestUrl)).then((value) {
                        if (mounted) {
                          FlutterToastr.show(localizations.copied, context);
                          Navigator.maybePop(context);
                        }
                      });
                    },
                    label: localizations.copyUrl,
                    icon: Icons.link,
                    iconSize: 22),
                right: itemButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: curlRequest(request))).then((value) {
                        if (mounted) {
                          FlutterToastr.show(localizations.copied, context);
                          Navigator.maybePop(context);
                        }
                      });
                    },
                    label: localizations.copyCurl,
                    icon: Icons.code),
              ),
              //repeat
              menuItem(
                left: itemButton(
                    onPressed: () {
                      onRepeat(request);
                      Navigator.maybePop(context);
                    },
                    label: localizations.repeat,
                    icon: Icons.repeat_one),
                right: itemButton(
                    onPressed: () => showCustomRepeat(request), label: localizations.customRepeat, icon: Icons.repeat),
              ),
              //favorite and edit
              menuItem(
                left: itemButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      rename(widget.favorite);
                    },
                    label: localizations.rename,
                    icon: Icons.drive_file_rename_outline),
                right: itemButton(
                    onPressed: () async {
                      Navigator.pop(context);

                      var pageRoute = MaterialPageRoute(
                          builder: (context) => MobileRequestEditor(request: request, proxyServer: widget.proxyServer));
                      Navigator.push(context, pageRoute);
                    },
                    label: localizations.editRequest,
                    icon: Icons.replay_outlined),
              ),

              //script and rewrite
              menuItem(
                left: itemButton(
                    onPressed: () async {
                      Navigator.maybePop(context);
                      var scriptManager = await ScriptManager.instance;
                      var url = request.domainPath;
                      var scriptItem = (scriptManager).list.firstWhereOrNull((it) => it.url == url);
                      String? script = scriptItem == null ? null : await scriptManager.getScript(scriptItem);

                      var pageRoute = MaterialPageRoute(
                          builder: (context) =>
                              ScriptEdit(scriptItem: scriptItem, script: script, url: scriptItem?.url ?? url));
                      if (mounted) Navigator.push(context, pageRoute);
                    },
                    label: localizations.script,
                    icon: Icons.javascript_outlined),
                right: itemButton(
                    onPressed: () async {
                      Navigator.maybePop(context);
                      bool isRequest = request.response == null;
                      var requestRewrites = await RequestRewriteManager.instance;

                      var ruleType = isRequest ? RuleType.requestReplace : RuleType.responseReplace;
                      var rule = requestRewrites.getRequestRewriteRule(request, ruleType);

                      var rewriteItems = await requestRewrites.getRewriteItems(rule);

                      var pageRoute = MaterialPageRoute(
                          builder: (_) => RewriteRule(rule: rule, items: rewriteItems, request: request));
                      if (mounted) Navigator.push(context, pageRoute);
                    },
                    label: localizations.requestRewrite,
                    icon: Icons.edit_outlined),
              ),
              SizedBox(height: 2),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                itemButton(
                    onPressed: () {
                      widget.onRemove?.call(widget.favorite);
                      FlutterToastr.show(localizations.deleteSuccess, context);
                      Navigator.maybePop(context);
                    },
                    label: localizations.deleteFavorite,
                    icon: Icons.delete_outline),
                SizedBox(width: 10),
              ]),
            ],
          )),
        ]).then((value) {
      selected = false;
      // if (mounted) setState(() {});
    });
  }

  //显示高级重发
  showCustomRepeat(HttpRequest request) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => futureWidget(SharedPreferences.getInstance(),
            (prefs) => MobileCustomRepeat(onRepeat: () => onRepeat(request), prefs: prefs))));
  }

  onRepeat(HttpRequest request) {
    var httpRequest = request.copy(uri: request.requestUrl);
    var proxyInfo = widget.proxyServer.isRunning ? ProxyInfo.of("127.0.0.1", widget.proxyServer.port) : null;
    HttpClients.proxyRequest(httpRequest, proxyInfo: proxyInfo);

    if (mounted) {
      FlutterToastr.show(localizations.reSendRequest, context);
    }
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

  //点击事件
  void onClick() {
    Navigator.push(context, MaterialPageRoute(builder: (context) {
      return NetworkTabController(
          proxyServer: widget.proxyServer,
          httpRequest: request,
          httpResponse: request.response,
          title: Text(localizations.captureDetail, style: const TextStyle(fontSize: 16)));
    }));
  }

  Widget itemButton(
      {required String label, required IconData icon, required Function() onPressed, double iconSize = 20}) {
    var theme = Theme.of(context);
    var style = theme.textTheme.bodyMedium;
    return TextButton.icon(
        onPressed: onPressed,
        label: Text(label, style: style),
        icon: Icon(icon, size: iconSize, color: theme.colorScheme.primary.withOpacity(0.65)));
  }

  Widget menuItem({required Widget left, required Widget right}) {
    return Row(
      children: [
        SizedBox(width: 130, child: Align(alignment: Alignment.centerLeft, child: left)),
        Expanded(child: Align(alignment: Alignment.centerLeft, child: right))
      ],
    );
  }
}
