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
import 'package:proxypin/network/util/cache.dart';
import 'package:proxypin/storage/favorites.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';
import 'package:proxypin/ui/component/multi_window.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/content/panel.dart';
import 'package:proxypin/ui/desktop/request/repeat.dart';
import 'package:proxypin/ui/desktop/setting/request_map.dart';
import 'package:proxypin/ui/desktop/setting/script.dart';
import 'package:proxypin/ui/desktop/widgets/highlight.dart';
import 'package:proxypin/utils/curl.dart';
import 'package:proxypin/utils/keyword_highlight.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/flutter_compat.dart';
import 'package:proxypin/utils/python.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../../utils/export_request.dart';
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
  final MultiSelectController multiSelectController;
  final RequestSelectionHandlers selectionHandlers;

  RequestWidget(this.request,
      {Key? key,
      required this.proxyServer,
      this.remove,
      this.displayDomain = true,
      this.trailing,
      required this.selectionHandlers,
      required this.index,
      required this.multiSelectController})
      : super(key: key ?? GlobalKey<_RequestWidgetState>());

  @override
  State<RequestWidget> createState() => _RequestWidgetState();

  void setResponse(HttpResponse response) {
    this.response.set(response);
    var state = key as GlobalKey<_RequestWidgetState>;
    state.currentState?.changeState();
  }

  void changeState() {
    var state = key as GlobalKey<_RequestWidgetState>;
    state.currentState?.changeState();
  }

  static void removeAutoReadByIds(Iterable<String> requestIds) {
    _RequestWidgetState.removeAutoReadByIds(requestIds);
  }
}

class _RequestWidgetState extends State<RequestWidget> {
  //选择的节点
  static _RequestWidgetState? selectedState;

  static LruCacheSet<String> autoReadRequests = LruCacheSet<String>(5000);

  static bool markAutoRead(String requestId) {
    return autoReadRequests.add(requestId);
  }

  static void removeAutoReadByIds(Iterable<String> requestIds) {
    autoReadRequests.removeAll(requestIds);
  }

  bool selected = false;

  Color? highlightColor; //高亮颜色

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  bool get selectionMode => widget.multiSelectController.isSelectionMode;

  int get selectionCount => widget.multiSelectController.selectedCount;

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
    bool selectedInSelectionMode = widget.multiSelectController.contains(request.requestId);
    return GestureDetector(
        onLongPress: () {
          if (!selectionMode) {
            widget.multiSelectController.enterSelectionMode(widget.request.requestId);
          }
        },
        onSecondaryTap: contextualMenu,
        child: ListTile(
            minLeadingWidth: 5,
            textColor: requestColor,
            selectedColor: requestColor,
            selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            leading: _leading(requestColor),
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
            selected: selected || selectedInSelectionMode,
            dense: true,
            visualDensity: const VisualDensity(vertical: -4),
            contentPadding: EdgeInsets.only(left: selectedInSelectionMode ? 6 : 28),
            onTap: onClick));
  }

  Widget _leading(Color? requestColor) {
    bool selectedInSelectionMode = widget.multiSelectController.contains(widget.request.requestId);

    var icon = getIcon(widget.response.get() ?? widget.request.response, color: requestColor);
    if (!selectedInSelectionMode) {
      return icon;
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(selectedInSelectionMode ? Icons.check_box_outlined : Icons.check_box_outline_blank_outlined,
          size: 18, color: selectedInSelectionMode ? Theme.of(context).colorScheme.primary : Colors.grey),
      const SizedBox(width: 4),
      icon,
    ]);
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
    popUpContextMenu(selectionMode && selectionCount > 1 ? _batchMenu() : _requestMenu());
  }

  Menu _batchMenu() {
    return Menu(items: [
      _menuAction(localizations.repeat, _RequestMenuAction.batchRepeat),
      _menuAction(localizations.export, _RequestMenuAction.batchExport),
      MenuItem.separator(),
      _menuAction(localizations.delete, _RequestMenuAction.batchDelete),
      MenuItem.separator(),
      _menuAction(localizations.cancel, _RequestMenuAction.batchCancel),
    ]);
  }

  Menu _requestMenu() {
    return Menu(items: [
      _menuAction(localizations.copyUrl, _RequestMenuAction.copyUrl),
      MenuItem(label: localizations.copy, type: 'submenu', submenu: _copySubmenu()),
      MenuItem.separator(),
      _menuAction(localizations.openNewWindow, _RequestMenuAction.openNewWindow),
      MenuItem.separator(),
      MenuItem(label: localizations.export, type: 'submenu', submenu: _exportSubmenu()),
      MenuItem.separator(),
      _menuAction(localizations.repeat, _RequestMenuAction.repeat),
      _menuAction(localizations.customRepeat, _RequestMenuAction.customRepeat),
      _menuAction(localizations.editRequest, _RequestMenuAction.editRequest),
      MenuItem.separator(),
      _menuAction(localizations.requestRewrite, _RequestMenuAction.requestRewrite),
      _menuAction(localizations.requestMap, _RequestMenuAction.requestMap),
      _menuAction(localizations.script, _RequestMenuAction.script),
      MenuItem.separator(),
      _menuAction(localizations.favorite, _RequestMenuAction.favorite),
      MenuItem(label: localizations.highlight, type: 'submenu', submenu: highlightMenu()),
      MenuItem.separator(),
      _menuAction(localizations.select, _RequestMenuAction.select),
      MenuItem.separator(),
      _menuAction(localizations.delete, _RequestMenuAction.delete),
    ]);
  }

  Menu _copySubmenu() {
    return Menu(items: [
      _copyMenuAction(localizations.copyCurl, _RequestCopyMenuAction.curl),
      _copyMenuAction(localizations.copyRawRequest, _RequestCopyMenuAction.rawRequest),
      _copyMenuAction(localizations.copyRequestResponse, _RequestCopyMenuAction.requestResponse),
      _copyMenuAction(localizations.copyAsPythonRequests, _RequestCopyMenuAction.pythonRequests),
      _copyMenuAction(localizations.copyAsFetch, _RequestCopyMenuAction.fetch),
    ]);
  }

  Menu _exportSubmenu() {
    return Menu(items: [
      _exportMenuAction(localizations.request, _RequestExportMenuAction.request),
      _exportMenuAction(localizations.requestBody, _RequestExportMenuAction.requestBody),
      MenuItem.separator(),
      _exportMenuAction(localizations.response, _RequestExportMenuAction.response),
      _exportMenuAction(localizations.responseBody, _RequestExportMenuAction.responseBody),
      MenuItem.separator(),
      _exportMenuAction('HAR', _RequestExportMenuAction.har),
    ]);
  }

  MenuItem _menuAction(String label, _RequestMenuAction action) {
    return MenuItem(label: label, onClick: (_) => _onMenuAction(action));
  }

  MenuItem _copyMenuAction(String label, _RequestCopyMenuAction action) {
    return MenuItem(label: label, onClick: (_) => _onCopyMenuAction(action));
  }

  MenuItem _exportMenuAction(String label, _RequestExportMenuAction action) {
    return MenuItem(label: label, onClick: (_) => _onExportMenuAction(action));
  }

  Future<void> _onMenuAction(_RequestMenuAction action) async {
    switch (action) {
      case _RequestMenuAction.copyUrl:
        await _copyText(widget.request.requestUrl);
        break;
      case _RequestMenuAction.openNewWindow:
        openDetailInNewWindow();
        break;
      case _RequestMenuAction.repeat:
        onRepeat(widget.request);
        break;
      case _RequestMenuAction.customRepeat:
        await showCustomRepeat(widget.request);
        break;
      case _RequestMenuAction.editRequest:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          requestEdit();
        });
        break;
      case _RequestMenuAction.requestRewrite:
        showRequestRewriteDialog(context, widget.request);
        break;
      case _RequestMenuAction.requestMap:
        showDialog(
            context: context,
            builder: (context) =>
                RequestMapEdit(url: widget.request.domainPath, title: widget.request.hostAndPort?.host));
        break;
      case _RequestMenuAction.script:
        await _openScriptDialog();
        break;
      case _RequestMenuAction.favorite:
        FavoriteStorage.addFavorite(widget.request);
        FlutterToastr.show(localizations.operationSuccess, context, rootNavigator: true);
        break;
      case _RequestMenuAction.select:
        widget.multiSelectController.selectOnly(widget.request.requestId);
        break;
      case _RequestMenuAction.delete:
        widget.remove?.call(widget);
        break;
      case _RequestMenuAction.batchRepeat:
        widget.selectionHandlers.onRepeatSelected?.call();
        break;
      case _RequestMenuAction.batchExport:
        widget.selectionHandlers.onExportSelected?.call();
        break;
      case _RequestMenuAction.batchDelete:
        widget.selectionHandlers.onDeleteSelected?.call();
        break;
      case _RequestMenuAction.batchCancel:
        widget.multiSelectController.clear();
        break;
    }
  }

  Future<void> _onCopyMenuAction(_RequestCopyMenuAction action) async {
    switch (action) {
      case _RequestCopyMenuAction.curl:
        await _copyText(curlRequest(widget.request));
        break;
      case _RequestCopyMenuAction.rawRequest:
        await _copyText(copyRawRequest(widget.request));
        break;
      case _RequestCopyMenuAction.requestResponse:
        await _copyText(copyRequest(widget.request, widget.response.get()));
        break;
      case _RequestCopyMenuAction.pythonRequests:
        await _copyText(copyAsPythonRequests(widget.request));
        break;
      case _RequestCopyMenuAction.fetch:
        await _copyText(copyAsFetch(widget.request));
        break;
    }
  }

  void _onExportMenuAction(_RequestExportMenuAction action) {
    switch (action) {
      case _RequestExportMenuAction.request:
        exportRequest(widget.request);
        break;
      case _RequestExportMenuAction.requestBody:
        exportRequestBody(widget.request);
        break;
      case _RequestExportMenuAction.response:
        exportResponse(widget.response.get());
        break;
      case _RequestExportMenuAction.responseBody:
        exportResponseBody(widget.response.get());
        break;
      case _RequestExportMenuAction.har:
        exportHar(widget.request);
        break;
    }
  }

  Future<void> _openScriptDialog() async {
    var scriptManager = await ScriptManager.instance;
    var url = widget.request.domainPath;
    var scriptItem = scriptManager.list.firstWhereOrNull((it) => it.urls.contains(url));
    String? script = scriptItem == null ? null : await scriptManager.getScript(scriptItem);
    if (!mounted) {
      return;
    }
    showDialog(
        context: context,
        builder: (context) =>
            ScriptEdit(scriptItem: scriptItem, script: script, url: url, title: widget.request.hostAndPort?.host));
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      FlutterToastr.show(localizations.copied, rootNavigator: true, context);
    }
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
  Future<void> showCustomRepeat(HttpRequest request) async {
    var prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    showDialog(
        context: context,
        builder: (BuildContext context) {
          return CustomRepeatDialog(onRepeat: () => onRepeat(request), prefs: prefs);
        });
  }

  void onRepeat(HttpRequest httpRequest) {
    var request = httpRequest.copy(uri: httpRequest.requestUrl);
    var proxyInfo = widget.proxyServer.isRunning ? ProxyInfo.of("127.0.0.1", widget.proxyServer.port) : null;
    HttpClients.proxyRequest(request, proxyInfo: proxyInfo);
    FlutterToastr.show(localizations.reSendRequest, context, rootNavigator: true);
  }

  PopupMenuItem popupItem(String text, {VoidCallback? onTap}) {
    return CustomPopupMenuItem(height: 32, onTap: onTap, child: Text(text, style: const TextStyle(fontSize: 13)));
  }

  ///请求编辑
  Future<void> requestEdit() async {
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

  // 新窗口打开详情
  void openDetailInNewWindow() async {
    MultiWindow.openWindow(
      localizations.captureDetail,
      'RequestDetailPage',
      args: {
        'request': widget.request,
        'response': widget.request.response ?? widget.response.get(),
      },
      size: Size(850, 900),
    );
  }

  //点击事件
  void onClick() {
    final keyboard = HardwareKeyboard.instance;
    final useToggleSelection = keyboard.isMetaPressed || keyboard.isControlPressed;
    final useRangeSelection = keyboard.isShiftPressed;

    if (useRangeSelection) {
      widget.selectionHandlers.onRangeSelection?.call(widget.request);
      return;
    }

    if (selectionMode || useToggleSelection) {
      setState(() {
        widget.multiSelectController.toggle(widget.request.requestId);
      });
      return;
    }

    if (!selected) {
      setState(() {
        selected = true;
      });
    }

    if (AppConfiguration.current?.autoReadEnabled == true) {
      markAutoRead(widget.request.requestId);
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

class RequestSelectionHandlers {
  final Function(HttpRequest request)? onRangeSelection;
  final VoidCallback? onDeleteSelected;
  final VoidCallback? onRepeatSelected;
  final VoidCallback? onExportSelected;

  const RequestSelectionHandlers({
    this.onRangeSelection,
    this.onDeleteSelected,
    this.onRepeatSelected,
    this.onExportSelected,
  });
}

enum _RequestMenuAction {
  copyUrl,
  openNewWindow,
  repeat,
  customRepeat,
  editRequest,
  requestRewrite,
  requestMap,
  script,
  favorite,
  select,
  delete,
  batchRepeat,
  batchExport,
  batchDelete,
  batchCancel,
}

enum _RequestCopyMenuAction { curl, rawRequest, requestResponse, pythonRequests, fetch }

enum _RequestExportMenuAction { request, requestBody, response, responseBody, har }
