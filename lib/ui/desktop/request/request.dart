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
import 'dart:convert';
import 'dart:io';

import 'package:date_format/date_format.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_desktop_context_menu/flutter_desktop_context_menu.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/components/manager/script_manager.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/storage/favorites.dart';
import 'package:proxypin/ui/component/app_dialog.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/content/panel.dart';
import 'package:proxypin/ui/desktop/request/repeat.dart';
import 'package:proxypin/ui/desktop/toolbar/setting/request_map.dart';
import 'package:proxypin/ui/desktop/toolbar/setting/script.dart';
import 'package:proxypin/ui/desktop/widgets/highlight.dart';
import 'package:proxypin/utils/curl.dart';
import 'package:proxypin/utils/keyword_highlight.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/python.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../common.dart';

/// 请求 URI
/// @author wanghongen
/// 2023/10/8
class RequestWidget extends StatefulWidget {
  final int index;
  final HttpRequest request;
  final ValueWrap<HttpResponse> response = ValueWrap();
  final bool displayDomain;

  final ProxyServer proxyServer;
  final Function(RequestWidget)? remove;
  final Widget? trailing;

  RequestWidget(this.request,
      {Key? key, required this.proxyServer, this.remove, this.displayDomain = true, this.trailing, required this.index})
      : super(key: GlobalKey<_RequestWidgetState>());

  @override
  State<RequestWidget> createState() => _RequestWidgetState();

  void setResponse(HttpResponse response) {
    this.response.set(response);
    var state = key as GlobalKey<_RequestWidgetState>;
    state.currentState?.changeState();
  }
}

class _RequestWidgetState extends State<RequestWidget> {
  //选择的节点
  static _RequestWidgetState? selectedState;

  static Set<String> autoReadRequests = <String>{};

  bool selected = false;

  Color? highlightColor; //高亮颜色

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var request = widget.request;
    var response = widget.response.get() ?? request.response;
    String path = widget.displayDomain ? request.domainPath : request.path;
    String title = '${request.method.name} $path';

    var time = formatDate(request.requestTime, [HH, ':', nn, ':', ss]);
    String contentType = response?.contentType.name.toUpperCase() ?? '';
    var packagesSize = getPackagesSize(request, response);

    var requestColor = color(path);

    return GestureDetector(
        onSecondaryTap: contextualMenu,
        child: ListTile(
            minLeadingWidth: 5,
            textColor: requestColor,
            selectedColor: requestColor,
            selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            leading: getIcon(widget.response.get() ?? widget.request.response, color: requestColor),
            trailing: widget.trailing,
            title: Text(title.fixAutoLines(), overflow: TextOverflow.ellipsis, maxLines: 2),
            subtitle: Container(
                padding: const EdgeInsets.only(top: 3),
                child: Text.rich(
                    maxLines: 1,
                    TextSpan(
                      children: [
                        TextSpan(text: '#${widget.index} ', style: const TextStyle(fontSize: 11, color: Colors.teal)),
                        TextSpan(
                            text:
                                '$time - [${response?.status.code ?? ''}]  $contentType $packagesSize ${response?.costTime() ?? ''}',
                            style: const TextStyle(fontSize: 11, color: Colors.grey))
                      ],
                    ))),
            selected: selected,
            dense: true,
            visualDensity: const VisualDensity(vertical: -4),
            contentPadding: const EdgeInsets.only(left: 28),
            onTap: onClick));
  }

  Color? color(String url) {
    if (highlightColor != null) {
      return highlightColor;
    }

    highlightColor = KeywordHighlights.getHighlightColor(url);
    if (highlightColor != null) {
      return highlightColor;
    }

    return autoReadRequests.contains(widget.request.requestId) ? Colors.grey : null;
  }

  void changeState() {
    setState(() {});
  }

  void contextualMenu() {
    Menu menu = Menu(items: [
      MenuItem(
          label: localizations.copyUrl,
          onClick: (_) {
            var requestUrl = widget.request.requestUrl;
            Clipboard.setData(ClipboardData(text: requestUrl))
                .then((value) => FlutterToastr.show(localizations.copied, rootNavigator: true, context));
          }),
      MenuItem(
          label: localizations.copy,
          type: 'submenu',
          submenu: Menu(items: [
            MenuItem(
                label: localizations.copyCurl,
                onClick: (_) {
                  Clipboard.setData(ClipboardData(text: curlRequest(widget.request)))
                      .then((value) => FlutterToastr.show(localizations.copied, rootNavigator: true, context));
                }),
            MenuItem(
                label: localizations.copyRawRequest,
                onClick: (_) {
                  Clipboard.setData(ClipboardData(text: copyRawRequest(widget.request)))
                      .then((value) => FlutterToastr.show(localizations.copied, rootNavigator: true, context));
                }),
            MenuItem(
                label: localizations.copyRequestResponse,
                onClick: (_) {
                  Clipboard.setData(ClipboardData(text: copyRequest(widget.request, widget.response.get())))
                      .then((value) => FlutterToastr.show(localizations.copied, rootNavigator: true, context));
                }),
            MenuItem(
              label: localizations.copyAsPythonRequests,
              onClick: (_) {
                Clipboard.setData(ClipboardData(text: copyAsPythonRequests(widget.request)))
                    .then((value) => FlutterToastr.show(localizations.copied, rootNavigator: true, context));
              },
            ),
          ])),
      MenuItem.separator(),
      MenuItem(label: localizations.repeat, onClick: (_) => onRepeat(widget.request)),
      MenuItem(label: localizations.customRepeat, onClick: (_) => showCustomRepeat(widget.request)),
      MenuItem(
          label: localizations.editRequest,
          onClick: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              requestEdit();
            });
          }),
      MenuItem.separator(),
      MenuItem(label: localizations.requestRewrite, onClick: (_) => showRequestRewriteDialog(context, widget.request)),
      MenuItem(
          label: localizations.requestMap,
          onClick: (_) async {
            showDialog(
                context: context,
                builder: (context) =>
                    RequestMapEdit(url: widget.request.domainPath, title: widget.request.hostAndPort?.host));
          }),
      MenuItem(
          label: localizations.script,
          onClick: (_) async {
            var scriptManager = await ScriptManager.instance;
            var url = widget.request.domainPath;
            var scriptItem = (scriptManager).list.firstWhereOrNull((it) => it.url == url);

            String? script = scriptItem == null ? null : await scriptManager.getScript(scriptItem);
            if (!mounted) return;
            showDialog(
                context: context,
                builder: (context) => ScriptEdit(
                    scriptItem: scriptItem, script: script, url: url, title: widget.request.hostAndPort?.host));
          }),
      MenuItem.separator(),
      MenuItem(
          label: localizations.favorite,
          onClick: (_) {
            FavoriteStorage.addFavorite(widget.request);
            FlutterToastr.show(localizations.operationSuccess, context, rootNavigator: true);
          }),
      MenuItem(
          label: localizations.highlight,
          type: 'submenu',
          submenu: highlightMenu(),
          onClick: (_) {
            setState(() {
              highlightColor = Colors.red;
            });
          }),
      MenuItem.separator(),
      MenuItem(
          label: localizations.delete,
          onClick: (_) {
            widget.remove?.call(widget);
          }),
    ]);

    popUpContextMenu(menu);
  }

  ///高亮
  Menu highlightMenu() {
    return Menu(
      items: [
        MenuItem(
            label: localizations.red,
            onClick: (_) {
              setState(() {
                highlightColor = Colors.red;
              });
            }),
        MenuItem(
            label: localizations.yellow,
            onClick: (_) {
              setState(() {
                highlightColor = Colors.yellow.shade600;
              });
            }),
        MenuItem(
            label: localizations.blue,
            onClick: (_) {
              setState(() {
                highlightColor = Colors.blue;
              });
            }),
        MenuItem(
            label: localizations.green,
            onClick: (_) {
              setState(() {
                highlightColor = Colors.green;
              });
            }),
        MenuItem(
            label: localizations.gray,
            onClick: (_) {
              setState(() {
                highlightColor = Colors.grey;
              });
            }),
        MenuItem.separator(),
        MenuItem.checkbox(
            label: localizations.autoRead,
            checked: AppConfiguration.current?.autoReadEnabled,
            onClick: (_) {
              setState(() {
                AppConfiguration.current?.autoReadEnabled = !AppConfiguration.current!.autoReadEnabled;
              });
            }),
        MenuItem.separator(),
        MenuItem(
            label: localizations.reset,
            onClick: (_) {
              setState(() {
                highlightColor = null;
                autoReadRequests.clear();
              });
            }),
        MenuItem(
            label: localizations.keyword,
            onClick: (_) {
              showDialog(context: context, builder: (BuildContext context) => const DesktopKeywordHighlight());
            }),
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

  onRepeat(HttpRequest httpRequest) {
    var request = httpRequest.copy(uri: httpRequest.requestUrl);
    var proxyInfo = widget.proxyServer.isRunning ? ProxyInfo.of("127.0.0.1", widget.proxyServer.port) : null;
    HttpClients.proxyRequest(request, proxyInfo: proxyInfo);

    CustomToast.success(localizations.reSendRequest).show(context);
  }

  PopupMenuItem popupItem(String text, {VoidCallback? onTap}) {
    return CustomPopupMenuItem(height: 32, onTap: onTap, child: Text(text, style: const TextStyle(fontSize: 13)));
  }

  ///请求编辑
  requestEdit() async {
    var size = MediaQuery.of(context).size;
    var ratio = 1.0;
    if (Platform.isWindows) {
      ratio = WindowManager.instance.getDevicePixelRatio();
    }

    final window = await DesktopMultiWindow.createWindow(jsonEncode(
      {'name': 'RequestEditor', 'request': widget.request, 'proxyPort': widget.proxyServer.port},
    ));

    window.setTitle(localizations.requestEdit);
    window
      ..setFrame(const Offset(100, 100) & Size(960 * ratio, size.height * ratio))
      ..center()
      ..show();
  }

  //点击事件
  void onClick() {
    if (!selected) {
      setState(() {
        selected = true;
      });
    }

    if (AppConfiguration.current?.autoReadEnabled == true) {
      autoReadRequests.add(widget.request.requestId);
    }

    //切换选中的节点
    if (selectedState?.mounted == true && selectedState != this) {
      selectedState?.setState(() {
        selectedState?.selected = false;
      });
    }

    selectedState = this;
    NetworkTabController.current?.change(widget.request, widget.response.get() ?? widget.request.response);
  }
}
