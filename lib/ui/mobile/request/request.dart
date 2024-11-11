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
import 'dart:io';

import 'package:date_format/date_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/components/manager/rewrite_rule.dart';
import 'package:proxypin/network/components/manager/script_manager.dart';
import 'package:proxypin/network/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http_client.dart';
import 'package:proxypin/network/util/cache.dart';
import 'package:proxypin/storage/favorites.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/content/panel.dart';
import 'package:proxypin/ui/mobile/request/repeat.dart';
import 'package:proxypin/ui/mobile/request/request_editor.dart';
import 'package:proxypin/ui/mobile/setting/request_rewrite.dart';
import 'package:proxypin/ui/mobile/setting/script.dart';
import 'package:proxypin/ui/mobile/widgets/highlight.dart';
import 'package:proxypin/utils/curl.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/navigator.dart';
import 'package:shared_preferences/shared_preferences.dart';

///请求行
class RequestRow extends StatefulWidget {
  final int index;
  final HttpRequest request;
  final ProxyServer proxyServer;
  final bool displayDomain;
  final Function(HttpRequest)? onRemove;

  const RequestRow(
      {super.key,
      required this.request,
      required this.proxyServer,
      this.displayDomain = true,
      this.onRemove,
      required this.index});

  @override
  State<StatefulWidget> createState() {
    return RequestRowState();
  }
}

class RequestRowState extends State<RequestRow> {
  static ExpiringCache<String, Image> imageCache = ExpiringCache<String, Image>(const Duration(minutes: 5));

  late HttpRequest request;
  HttpResponse? response;
  bool selected = false;
  Color? highlightColor; //高亮颜色

  AppLocalizations get localizations => AppLocalizations.of(availableContext)!;

  change(HttpResponse response) {
    setState(() {
      this.response = response;
    });
  }

  @override
  void initState() {
    request = widget.request;
    response = request.response;
    super.initState();
  }

  Color? color(String url) {
    if (highlightColor != null) {
      return highlightColor;
    }

    return KeywordHighlight.getHighlightColor(url);
  }

  BuildContext getContext() => mounted ? super.context : NavigatorHelper().context;

  BuildContext get availableContext => getContext();

  @override
  Widget build(BuildContext context) {
    String url = widget.displayDomain ? request.requestUrl : request.path;

    var title = Strings.autoLineString('${request.method.name} $url');

    var time = formatDate(request.requestTime, [HH, ':', nn, ':', ss]);
    var contentType = response?.contentType.name.toUpperCase() ?? '';
    var packagesSize = getPackagesSize(request, response);

    var subTitle = '$time - [${response?.status.code ?? ''}] $contentType $packagesSize ${response?.costTime() ?? ''}';

    var highlightColor = color(url);

    return GestureDetector(
        onLongPressStart: menu,
        child: ListTile(
          visualDensity: const VisualDensity(vertical: -4),
          minLeadingWidth: 5,
          selected: selected,
          textColor: highlightColor,
          selectedColor: highlightColor,
          leading: appIcon(),
          title: Text(title, overflow: TextOverflow.ellipsis, maxLines: 2, style: const TextStyle(fontSize: 14)),
          subtitle: Text.rich(
              maxLines: 1,
              TextSpan(children: [
                TextSpan(text: '#${widget.index} ', style: const TextStyle(fontSize: 11, color: Colors.teal)),
                TextSpan(text: subTitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ])),
          trailing: getIcon(response),
          contentPadding:
              Platform.isIOS ? const EdgeInsets.symmetric(horizontal: 8) : const EdgeInsets.only(left: 3, right: 5),
          onTap: () {
            Navigator.of(getContext()).push(MaterialPageRoute(builder: (context) {
              return NetworkTabController(
                  proxyServer: widget.proxyServer,
                  httpRequest: request,
                  httpResponse: response,
                  title: Text(localizations.captureDetail, style: const TextStyle(fontSize: 16)));
            }));
          },
        ));
  }

  Widget? appIcon() {
    if (Platform.isIOS) {
      return null;
    }
    if (request.processInfo == null) {
      return const Icon(Icons.question_mark, size: 38);
    }

    //如果有缓存图标直接返回图标
    if (request.processInfo!.hasCacheIcon) {
      return imageCache.putIfAbsent(request.processInfo!.id, () {
        return Image.memory(request.processInfo!.cacheIcon!, width: 40, gaplessPlayback: true);
      });
    }

    return FutureBuilder(
        future: request.processInfo!.getIcon(),
        builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
          if (snapshot.hasData) {
            return Image.memory(snapshot.data!, width: 40);
          }
          return const SizedBox(width: 40);
        });
  }

  ///菜单
  menu(details) {
    setState(() {
      selected = true;
    });

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
                        FlutterToastr.show(localizations.copied, getContext());
                        Navigator.maybePop(getContext());
                      });
                    },
                    label: localizations.copyUrl,
                    icon: Icons.link,
                    iconSize: 22),
                right: itemButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: curlRequest(request))).then((value) {
                        FlutterToastr.show(localizations.copied, getContext());
                        Navigator.maybePop(getContext());
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
                      Navigator.maybePop(getContext());
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
                      FavoriteStorage.addFavorite(widget.request);
                      FlutterToastr.show(localizations.addSuccess, availableContext);
                      Navigator.maybePop(availableContext);
                    },
                    label: localizations.favorite,
                    icon: Icons.favorite_outline),
                right: itemButton(
                    onPressed: () async {
                      await Navigator.maybePop(availableContext);

                      var pageRoute = MaterialPageRoute(
                          builder: (context) =>
                              MobileRequestEditor(request: widget.request, proxyServer: widget.proxyServer));
                      Navigator.push(getContext(), pageRoute);
                    },
                    label: localizations.editRequest,
                    icon: Icons.replay_outlined),
              ),
              //script and rewrite
              menuItem(
                left: itemButton(
                    onPressed: () async {
                      Navigator.maybePop(availableContext);

                      var scriptManager = await ScriptManager.instance;
                      var url = request.domainPath;
                      var scriptItem = scriptManager.list.firstWhereOrNull((it) => it.url == url);
                      String? script = scriptItem == null ? null : await scriptManager.getScript(scriptItem);

                      var pageRoute = MaterialPageRoute(
                          builder: (context) =>
                              ScriptEdit(scriptItem: scriptItem, script: script, url: scriptItem?.url ?? url));

                      Navigator.push(getContext(), pageRoute);
                    },
                    label: localizations.script,
                    icon: Icons.javascript_outlined),
                right: itemButton(
                    onPressed: () async {
                      Navigator.maybePop(availableContext);
                      bool isRequest = response == null;
                      var requestRewrites = await RequestRewriteManager.instance;

                      var ruleType = isRequest ? RuleType.requestReplace : RuleType.responseReplace;
                      var rule = requestRewrites.getRequestRewriteRule(request, ruleType);

                      var rewriteItems = await requestRewrites.getRewriteItems(rule);

                      var pageRoute = MaterialPageRoute(
                          builder: (_) => RewriteRule(rule: rule, items: rewriteItems, request: request));
                      var context = availableContext;
                      if (context.mounted) Navigator.push(context, pageRoute);
                    },
                    label: localizations.requestRewrite,
                    icon: Icons.edit_outlined),
              ),
              menuItem(
                left: itemButton(
                    onPressed: () {
                      highlightColor = Theme.of(availableContext).colorScheme.primary;
                      Navigator.maybePop(availableContext);
                    },
                    label: localizations.highlight,
                    icon: Icons.highlight_outlined),
                right: itemButton(
                    onPressed: () {
                      highlightColor = Colors.grey;
                      Navigator.maybePop(availableContext);
                    },
                    label: localizations.markRead,
                    icon: Icons.mark_chat_read_outlined),
              ),
              SizedBox(height: 2),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                itemButton(
                    onPressed: () {
                      widget.onRemove?.call(request);
                      FlutterToastr.show(localizations.deleteSuccess, availableContext);
                      Navigator.maybePop(availableContext);
                    },
                    label: localizations.delete,
                    icon: Icons.delete_outline),
                SizedBox(width: 15),
              ]),
            ],
          )),
        ]).then((value) {
      selected = false;
      if (mounted) setState(() {});
    });
  }

  //显示高级重发
  showCustomRepeat(HttpRequest request) async {
    await Navigator.maybePop(availableContext);
    var pageRoute = MaterialPageRoute(
        builder: (context) => futureWidget(SharedPreferences.getInstance(),
            (prefs) => MobileCustomRepeat(onRepeat: () => onRepeat(request), prefs: prefs)));

    Navigator.push(getContext(), pageRoute);
  }

  onRepeat(HttpRequest request) {
    var httpRequest = request.copy(uri: request.requestUrl);
    var proxyInfo = widget.proxyServer.isRunning ? ProxyInfo.of("127.0.0.1", widget.proxyServer.port) : null;
    HttpClients.proxyRequest(httpRequest, proxyInfo: proxyInfo);

    if (mounted) {
      FlutterToastr.show(localizations.reSendRequest, context);
    }
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
