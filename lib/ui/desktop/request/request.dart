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
import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/ui/component/context_menu.dart';
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
import 'package:proxypin/ui/component/request_tree.dart';
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
import 'package:proxypin/utils/python.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../../utils/export_request.dart';
import '../common.dart';

/// 请求 URI
/// @author wanghongen
/// 2023/10/8
// ignore: must_be_immutable
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
  final Function(VoidCallback refresh)? onMount;

  /// Tree presentation of this row, applied by the domain list while it renders
  /// as a tree. Null means the row keeps the flat layout.
  RequestTreeStyle? treeStyle;

  VoidCallback? _refresh;
  VoidCallback? _select;

  RequestWidget(this.request,
      {super.key,
      required this.proxyServer,
      this.remove,
      this.displayDomain = true,
      this.trailing,
      required this.selectionHandlers,
      required this.index,
      required this.multiSelectController,
      this.onMount});

  @override
  State<RequestWidget> createState() => _RequestWidgetState();

  void setResponse(HttpResponse response) {
    this.response.set(response);
    _refresh?.call();
  }

  void changeState() {
    _refresh?.call();
  }

  /// Opens this request in the detail panel, exactly as a click would. Used by
  /// the keyboard navigation of the tree.
  void select() {
    _select?.call();
  }

  /// Moves the row to [style] inside the tree, refreshing it on the next frame
  /// when the position actually changed. Called from the parent build, so the
  /// refresh cannot happen inline.
  void applyTreeStyle(RequestTreeStyle? style) {
    if (style == null ? treeStyle == null : style.sameAs(treeStyle)) {
      return;
    }
    treeStyle = style;
    WidgetsBinding.instance.addPostFrameCallback((_) => changeState());
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
    widget._refresh = () => setState(() {});
    widget._select = selectRow;
    widget.onMount?.call(widget.changeState);
  }

  @override
  void dispose() {
    widget._refresh = null;
    widget._select = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var request = widget.request;
    var response = widget.response.get() ?? request.response;
    var operationName = request.graphqlOperationName;
    String path = widget.displayDomain ? request.domainPath : request.path;
    //树形模式只显示最后一段路径，颜色匹配仍然使用完整路径
    var treeStyle = widget.treeStyle;
    String title = '${request.method.name} ${treeStyle?.label ?? path}';

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
        onSecondaryTapDown: (details) => contextualMenu(details),
        child: ListTile(
            minLeadingWidth: 5,
            textColor: requestColor,
            selectedColor: requestColor,
            selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            leading: _leading(requestColor),
            trailing: widget.trailing,
            title: Text.rich(
                //树形模式一行一个请求，详情点开右侧面板看，避免列表太乱
                maxLines: treeStyle == null ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                TextSpan(children: [
                  TextSpan(text: treeStyle == null ? title.fixAutoLines() : title),
                  if (operationName != null) graphqlOperationSpan(request, fixAutoLines: treeStyle == null)!,
                ])),
            subtitle: treeStyle != null
                ? null
                : Container(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text.rich(
                        maxLines: 1,
                        TextSpan(
                          children: [
                            TextSpan(
                                text: '#${widget.index} ', style: const TextStyle(fontSize: 11, color: Colors.teal)),
                            TextSpan(
                                text:
                                    '$time - [${response?.status.code ?? ''}]  $contentType $packagesSize ${response?.costTime() ?? ''}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey))
                          ],
                        ))),
            selected: selected || selectedInSelectionMode,
            dense: true,
            visualDensity: const VisualDensity(vertical: -4),
            //树形模式一行一个请求，和目录行排一样紧
            minTileHeight: treeStyle == null ? null : RequestTreeStyle.rowHeight,
            minVerticalPadding: treeStyle == null ? 4 : 0,
            contentPadding: EdgeInsets.only(
                left: (selectedInSelectionMode ? 6 : 28) + (treeStyle?.depth ?? 0) * RequestTreeStyle.indentStep),
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

  void contextualMenu(TapDownDetails details) {
    var menu = selectionMode && selectionCount > 1 ? _batchMenu() : _requestMenu();
    showCustomContextMenu(context, details.globalPosition, menu);
  }

  List<ContextMenuItem> _batchMenu() {
    return [
      _menuAction(localizations.repeat, _RequestMenuAction.batchRepeat),
      _menuAction(localizations.export, _RequestMenuAction.batchExport),
      ContextMenuItem.separator(),
      _menuAction(localizations.delete, _RequestMenuAction.batchDelete),
      ContextMenuItem.separator(),
      _menuAction(localizations.cancel, _RequestMenuAction.batchCancel),
    ];
  }

  List<ContextMenuItem> _requestMenu() {
    return [
      _menuAction(localizations.copyCurl, _RequestMenuAction.copyCurl),
      ContextMenuItem.submenu(label: localizations.copy, submenu: _copySubmenu()),
      ContextMenuItem.separator(),
      _menuAction(localizations.openNewWindow, _RequestMenuAction.openNewWindow),
      ContextMenuItem.separator(),
      ContextMenuItem.submenu(label: localizations.export, submenu: _exportSubmenu()),
      ContextMenuItem.separator(),
      _menuAction(localizations.repeat, _RequestMenuAction.repeat),
      _menuAction(localizations.customRepeat, _RequestMenuAction.customRepeat),
      _menuAction(localizations.editRequest, _RequestMenuAction.editRequest),
      ContextMenuItem.separator(),
      _menuAction(localizations.requestRewrite, _RequestMenuAction.requestRewrite),
      _menuAction(localizations.requestMap, _RequestMenuAction.requestMap),
      _menuAction(localizations.script, _RequestMenuAction.script),
      ContextMenuItem.separator(),
      _menuAction(localizations.favorite, _RequestMenuAction.favorite),
      ContextMenuItem.submenu(label: localizations.highlight, submenu: highlightMenu()),
      ContextMenuItem.separator(),
      _menuAction(localizations.select, _RequestMenuAction.select),
      ContextMenuItem.separator(),
      _menuAction(localizations.delete, _RequestMenuAction.delete),
    ];
  }

  List<ContextMenuItem> _copySubmenu() {
    return [
      _copyMenuAction(localizations.copyUrl, _RequestCopyMenuAction.copyUrl),
      _copyMenuAction(localizations.copyRawRequest, _RequestCopyMenuAction.rawRequest),
      _copyMenuAction(localizations.copyRequestResponse, _RequestCopyMenuAction.requestResponse),
      _copyMenuAction(localizations.copyAsPythonRequests, _RequestCopyMenuAction.pythonRequests),
      _copyMenuAction(localizations.copyAsFetch, _RequestCopyMenuAction.fetch),
    ];
  }

  List<ContextMenuItem> _exportSubmenu() {
    return [
      _exportMenuAction(localizations.request, _RequestExportMenuAction.request),
      _exportMenuAction(localizations.requestBody, _RequestExportMenuAction.requestBody),
      ContextMenuItem.separator(),
      _exportMenuAction(localizations.response, _RequestExportMenuAction.response),
      _exportMenuAction(localizations.responseBody, _RequestExportMenuAction.responseBody),
      ContextMenuItem.separator(),
      _exportMenuAction('HAR', _RequestExportMenuAction.har),
    ];
  }

  ContextMenuItem _menuAction(String label, _RequestMenuAction action) {
    return ContextMenuItem.normal(label: label, onClick: () => _onMenuAction(action));
  }

  ContextMenuItem _copyMenuAction(String label, _RequestCopyMenuAction action) {
    return ContextMenuItem.normal(label: label, onClick: () => _onCopyMenuAction(action));
  }

  ContextMenuItem _exportMenuAction(String label, _RequestExportMenuAction action) {
    return ContextMenuItem.normal(label: label, onClick: () => _onExportMenuAction(action));
  }

  Future<void> _onMenuAction(_RequestMenuAction action) async {
    switch (action) {
      case _RequestMenuAction.copyCurl:
        await _copyText(curlRequest(widget.request));
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
      case _RequestCopyMenuAction.copyUrl:
        await _copyText(widget.request.requestUrl);
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
        exportResponse(widget.response.get() ?? widget.request.response);
        break;
      case _RequestExportMenuAction.responseBody:
        exportResponseBody(widget.response.get() ?? widget.request.response);
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
  List<ContextMenuItem> highlightMenu() {
    return [
      ContextMenuItem.normal(
          label: localizations.red,
          onClick: () {
            setState(() {
              highlightColor = Colors.red;
            });
          }),
      ContextMenuItem.normal(
          label: localizations.yellow,
          onClick: () {
            setState(() {
              highlightColor = Colors.yellow.shade600;
            });
          }),
      ContextMenuItem.normal(
          label: localizations.blue,
          onClick: () {
            setState(() {
              highlightColor = Colors.blue;
            });
          }),
      ContextMenuItem.normal(
          label: localizations.green,
          onClick: () {
            setState(() {
              highlightColor = Colors.green;
            });
          }),
      ContextMenuItem.normal(
          label: localizations.gray,
          onClick: () {
            setState(() {
              highlightColor = Colors.grey;
            });
          }),
      ContextMenuItem.separator(),
      ContextMenuItem.checkbox(
          label: localizations.autoRead,
          checked: AppConfiguration.current?.autoReadEnabled ?? false,
          onClick: () {
            setState(() {
              AppConfiguration.current?.autoReadEnabled = !AppConfiguration.current!.autoReadEnabled;
            });
          }),
      ContextMenuItem.separator(),
      ContextMenuItem.normal(
          label: localizations.reset,
          onClick: () {
            setState(() {
              highlightColor = null;
              autoReadRequests.clear();
            });
          }),
      ContextMenuItem.normal(
          label: localizations.keyword,
          onClick: () {
            showDialog(context: context, builder: (BuildContext context) => const DesktopKeywordHighlight());
          }),
    ];
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
      ..setSize(Size(960 * ratio, size.height * ratio))
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

    selectRow();
  }

  ///选中当前行并在右侧面板打开，键盘上下移动时也走这里
  void selectRow() {
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
  copyCurl,
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

enum _RequestCopyMenuAction { copyUrl, rawRequest, requestResponse, pythonRequests, fetch }

enum _RequestExportMenuAction { request, requestBody, response, responseBody, har }
