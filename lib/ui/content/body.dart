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
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:get/get.dart';
import 'package:image_pickers/image_pickers.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/components/manager/rewrite_rule.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/json/json_viewer.dart';
import 'package:proxypin/ui/component/json/theme.dart';
import 'package:proxypin/ui/component/multi_window.dart';
import 'package:proxypin/ui/component/svg_icon.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/desktop/setting/request_rewrite.dart';
import 'package:proxypin/ui/mobile/setting/request_rewrite.dart';
import 'package:proxypin/utils/crypto_body_decoder.dart';
import 'package:proxypin/utils/css_formatter.dart';
import 'package:proxypin/utils/html_formatter.dart';
import 'package:proxypin/utils/js_formatter.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:proxypin/utils/xml_formatter.dart';

import '../component/json/json_text.dart';
import 'hex_viewer.dart';
import '../component/search/active_viewer_scope.dart';
import '../component/search/highlight_text.dart';
import '../component/search/search_controller.dart';
import '../component/search/virtualized_highlight_text.dart';
import '../toolbox/encoder.dart';

/// body 选区菜单：整个文本即全部内容，复制全部用“全选”即可，故不提供“复制值”
Widget bodyContextMenu(BuildContext context, EditableTextState editableTextState) =>
    contextMenu(context, editableTextState, copyValue: false);

///请求响应的body部分
///@Author wanghongen
class HttpBodyWidget extends StatefulWidget {
  final HttpMessage? httpMessage;
  final bool inNewWindow; //是否在新窗口打开
  final WindowController? windowController;
  final ScrollController? scrollController;
  final bool hideRequestRewrite; //是否隐藏请求重写

  const HttpBodyWidget(
      {super.key,
      required this.httpMessage,
      this.inNewWindow = false,
      this.windowController,
      this.scrollController,
      this.hideRequestRewrite = false});

  @override
  State<StatefulWidget> createState() {
    return HttpBodyState();
  }
}

class HttpBodyState extends State<HttpBodyWidget> {
  var bodyKey = GlobalKey<_BodyState>();
  ViewType? selectedViewType;
  final searchIconKey = GlobalKey();
  final SearchTextController searchController = SearchTextController();

  AppLocalizations get localizations => AppLocalizations.of(context)!;
  bool showDecoded = false;
  CryptoDecodedResult? decoded;

  ViewType _currentViewType(Tabs tabs) => tabs.list.contains(selectedViewType) ? selectedViewType! : tabs.list.first;

  //当前请求是否命中已启用的重写规则
  final RxBool rewriteEnabled = false.obs;

  @override
  void initState() {
    super.initState();
    if (widget.windowController != null) {
      HardwareKeyboard.instance.addHandler(onKeyEvent);
    }

    _loadDecoded();
    _loadRewriteEnabled();
  }

  @override
  void didUpdateWidget(covariant HttpBodyWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.httpMessage?.requestId != widget.httpMessage?.requestId) {
      showDecoded = false;
      decoded = null;
      rewriteEnabled.value = false;
      _loadDecoded();
      _loadRewriteEnabled();
    }
  }

  ///计算当前请求是否命中已启用的重写规则
  Future<void> _loadRewriteEnabled() async {
    final message = widget.httpMessage;
    if (message == null || widget.hideRequestRewrite) return;

    HttpRequest? request = message is HttpRequest ? message : (message as HttpResponse).request;
    if (request == null) return;

    var types = message is HttpRequest
        ? [RuleType.requestReplace, RuleType.requestUpdate, RuleType.redirect]
        : [RuleType.responseReplace, RuleType.responseUpdate];

    var requestRewrites = await RequestRewriteManager.instance;
    rewriteEnabled.value = requestRewrites.getRewriteRule(request.domainPath, types) != null;
  }

  /// 按键事件
  bool onKeyEvent(KeyEvent event) {
    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      HardwareKeyboard.instance.removeHandler(onKeyEvent);
      widget.windowController?.close();
      return true;
    }

    return false;
  }

  Future<void> _loadDecoded() async {
    final message = widget.httpMessage;
    if (message == null) return;
    decoded = await CryptoBodyDecoder.maybeDecode(message);
    if (mounted && decoded != null && decoded!.hasText) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(onKeyEvent);
    searchController.dispose();
    widget.scrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.httpMessage == null) {
      return const SizedBox();
    }

    if ((widget.httpMessage?.body == null || widget.httpMessage?.body?.isEmpty == true) &&
        widget.httpMessage?.messages.isNotEmpty == false) {
      return const SizedBox();
    }

    var tabs = Tabs.of(widget.httpMessage?.contentType, isJsonText());
    final viewType = _currentViewType(tabs);

    List<Widget> list = [
      widget.inNewWindow ? const SizedBox() : titleWidget(tabs: tabs),
      const SizedBox(height: 3),
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _Body(
              key: bodyKey,
              message: widget.httpMessage,
              viewType: viewType,
              scrollController: widget.scrollController,
              searchController: searchController)) //body
    ];

    var tabController = FocusableActionDetector(
        shortcuts: {
          LogicalKeySet(
                  Platform.isMacOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
              ActivateIntent(),
          LogicalKeySet(LogicalKeyboardKey.escape): DismissIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              if (searchController.isSearchOverlayVisible) {
                hideSearchOverlay();
              } else {
                RenderBox renderBox = searchIconKey.currentContext?.findRenderObject() as RenderBox;
                Offset position = renderBox.localToGlobal(Offset.zero); // 获取搜索图标的位置

                searchController.showSearchOverlay(context,
                    top: max(position.dy + renderBox.size.height + 50, 100), right: 10);
              }
              return null;
            },
          ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (intent) {
              hideSearchOverlay();
              return null;
            },
          ),
        },
        child: widget.inNewWindow
            ? ListView(children: list)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: list));

    //在新窗口打开
    if (widget.inNewWindow) {
      return Scaffold(
          appBar: AppBar(title: titleWidget(inNewWindow: true), toolbarHeight: Platform.isWindows ? 36 : null),
          // 与详情面板一致的 14px 水平内边距（panel.dart message() 内嵌时由外层给）
          body: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: tabController));
    }
    return tabController;
  }

  void hideSearchOverlay() {
    searchController.removeSearchOverlay();
  }

  //判断是否是json格式
  bool isJsonText() {
    var bodyString = widget.httpMessage?.bodyAsString;
    return bodyString != null &&
        (bodyString.startsWith('{') && bodyString.endsWith('}') ||
            bodyString.startsWith('[') && bodyString.endsWith(']'));
  }

  /// 设计稿 .fmt 分段小胶囊：选中 primary-soft 底 + primary 字，未选中灰色
  List<Widget> _fmtChips(BuildContext context, Tabs? tabs) {
    if (tabs == null || tabs.list.length <= 1) {
      return [const SizedBox()];
    }
    var theme = Theme.of(context);
    var text3 = theme.brightness == Brightness.light ? const Color(0xFF8F959E) : DarkPalette.text3;
    final currentViewType = _currentViewType(tabs);
    return [
      for (final viewType in tabs.list)
        Padding(
            padding: const EdgeInsets.only(right: 4),
            // 选中底色由 Material 绘制，InkWell 的 hover/水波纹才能显示在底色之上
            child: Material(
                color: viewType == currentViewType ? primarySoftBg(theme, lightAlpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                child: InkWell(
                    borderRadius: BorderRadius.circular(5),
                    // 设计稿小控件 hover：浅色 #F0F1F3，暗黑 --hover
                    hoverColor: theme.brightness == Brightness.light ? const Color(0xFFF0F1F3) : DarkPalette.hover,
                    onTap: () {
                      setState(() => selectedViewType = viewType);
                    },
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        child: Text(viewType.title,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: viewType == currentViewType ? FontWeight.w500 : FontWeight.w400,
                                color: viewType == currentViewType ? theme.colorScheme.primary : text3)))))),
    ];
  }

  /// 标题
  Widget titleWidget({bool inNewWindow = false, Tabs? tabs}) {
    var type = widget.httpMessage is HttpRequest ? "Request" : "Response";

    bool isImage = widget.httpMessage?.contentType == ContentType.image;
    const visualDensity = VisualDensity.compact;

    final isMobile = Platforms.isMobile();

    // 操作图标与工具栏同色：onSurfaceVariant 淡灰（设计稿 .mini text-3）
    final iconColor = Theme.of(context).colorScheme.onSurfaceVariant;

    // Build common actions as widgets so we can either display them inline (desktop)
    // or move them into an overflow menu (mobile) to avoid hiding important buttons.
    // IconButton：获得 hover 光晕/水波纹/焦点环（原 InkWell 热区只有 19px，反馈几乎不可见）
    // 图标统一用设计稿同套 stroke SVG（与 mini 按钮一致），避免 Material 字形活区大小不一
    final searchBtn = IconButton(
      key: searchIconKey,
      visualDensity: visualDensity,
      iconSize: 15,
      splashRadius: 14,
      icon: SvgIcon('search', size: 15, color: iconColor),
      tooltip: localizations.search,
      onPressed: () {
        if (searchController.isSearchOverlayVisible) {
          searchController.removeSearchOverlay();
        } else {
          RenderBox renderBox = searchIconKey.currentContext?.findRenderObject() as RenderBox;
          Offset position = renderBox.localToGlobal(Offset.zero);
          searchController.showSearchOverlay(context, top: position.dy + renderBox.size.height + 50, right: 10);
        }
      },
    );

    final copyBtn = isImage
        ? downloadImageButton()
        : IconButton(
            visualDensity: visualDensity,
            iconSize: 15,
            icon: SvgIcon('copy', size: 15, color: iconColor),
            tooltip: localizations.copy,
            onPressed: () async {
              var body = await bodyKey.currentState?.getBody();
              if (body == null) return;
              Clipboard.setData(ClipboardData(text: body)).then((_) {
                if (mounted) FlutterToastr.show(localizations.copied, context);
              });
            },
          );

    final rewriteBtn = IconButton(
      visualDensity: visualDensity,
      iconSize: 15,
      icon: Obx(() => SvgIcon('pencil', size: 15, color: rewriteEnabled.value ? Colors.deepOrangeAccent : iconColor)),
      tooltip: localizations.requestRewrite,
      onPressed: showRequestRewrite,
    );

    final encodeBtn = IconButton(
        visualDensity: visualDensity,
        iconSize: 15,
        icon: SvgIcon('encode', size: 15, color: iconColor),
        tooltip: localizations.encode,
        onPressed: () async {
          var body = await bodyKey.currentState?.getBody();
          if (mounted) {
            encodeWindow(EncoderType.base64, context, body);
          }
        });

    final openNewBtn = IconButton(
        visualDensity: visualDensity,
        iconSize: 15,
        icon: SvgIcon('arrow_out', size: 15, color: iconColor),
        tooltip: localizations.newWindow,
        onPressed: () => openNew());

    Widget? cryptoToggle;
    if (decoded != null) {
      cryptoToggle = TextButton.icon(
        onPressed: () {
          setState(() {
            showDecoded = !showDecoded;
          });
        },
        icon: Icon(showDecoded ? Icons.lock_open : Icons.lock, size: 18),
        label: Text(showDecoded ? localizations.cryptoDecoded : localizations.cryptoDecodeToggle),
      );
    }

    // Mobile UX:
    // - If there is NO crypto result, keep the original (previous) horizontal-scroll title bar.
    // - Only when crypto is available, switch to the compact overflow-menu layout to keep
    //   the crypto toggle visible.
    if (isMobile && cryptoToggle != null) {
      final overflowItems = <PopupMenuEntry<String>>[];
      if (!widget.hideRequestRewrite) {
        overflowItems.add(PopupMenuItem(
            value: 'rewrite',
            child: Obx(() => Text(localizations.requestRewrite,
                style: rewriteEnabled.value ? TextStyle(color: Theme.of(context).colorScheme.primary) : null))));
      }
      overflowItems.add(PopupMenuItem(value: 'encode', child: Text(localizations.encode)));
      if (!inNewWindow) {
        overflowItems.add(PopupMenuItem(value: 'new_window', child: Text(localizations.newWindow)));
      }

      final row = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$type Body', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          searchBtn,
          const SizedBox(width: 4),
          copyBtn,
          const SizedBox(width: 4),
          Flexible(child: cryptoToggle),
          if (overflowItems.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (v) {
                if (v == 'rewrite') showRequestRewrite();
                if (v == 'encode') {
                  bodyKey.currentState?.getBody().then((body) {
                    if (mounted) encodeWindow(EncoderType.base64, context, body);
                  });
                }
                if (v == 'new_window') openNew();
              },
              itemBuilder: (_) => overflowItems,
            ),
        ],
      );
      // 格式分段第二行（改版把分段并入标题行后加密分支丢了切换入口，且一行放不下）
      if (tabs != null && tabs.list.length > 1) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          row,
          Row(children: _fmtChips(context, tabs)),
        ]);
      }
      return row;
    }

    // 设计稿 .d-sec + .fmt：11px 灰色分区标签（请求体/响应体）+ 格式分段胶囊 + 紧凑操作图标
    final theme = Theme.of(context);
    final text3 = theme.brightness == Brightness.light ? const Color(0xFF8F959E) : DarkPalette.text3;
    // 标签不再带「· JSON」类型后缀：格式分段已按类型默认选中
    var label = widget.httpMessage is HttpRequest ? localizations.requestBody : localizations.responseBody;

    final labelWidget = Text(label, style: TextStyle(fontSize: 14, height: 1.5, letterSpacing: 0.3, color: text3));

    final actions = <Widget>[
      searchBtn,
      const SizedBox(width: 2),
      copyBtn,
    ];
    if (!widget.hideRequestRewrite) {
      actions.add(rewriteBtn);
    }
    actions.add(encodeBtn);
    if (!inNewWindow) {
      actions.add(openNewBtn);
    }
    if (cryptoToggle != null) {
      actions.add(cryptoToggle);
    }

    // 手机端两行布局（旧版行为）：第一行 标签+操作图标，第二行 格式分段——合并一行手机上放不下
    if (isMobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [labelWidget, const SizedBox(width: 8), ...actions]),
        if (tabs != null && tabs.list.length > 1) Row(children: _fmtChips(context, tabs)),
      ]);
    }

    final list = <Widget>[
      labelWidget,
      const SizedBox(width: 12),
      ..._fmtChips(context, tabs),
      const SizedBox(width: 8),
      ...actions,
    ];

    return SingleChildScrollView(
        scrollDirection: Axis.horizontal, child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: list));
  }

  ///下载图片
  Widget downloadImageButton() {
    return IconButton(
        iconSize: 15,
        visualDensity: VisualDensity.compact,
        icon: SvgIcon('download', size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
        tooltip: localizations.saveImage,
        onPressed: () async {
          var body = bodyKey.currentState?.widget.message?.body;
          if (body == null) {
            return;
          }
          var bytes = Uint8List.fromList(body);
          var extension = _imageExtension(bytes, bodyKey.currentState?.widget.message?.headers.contentType);
          var fileName = "image_${DateTime.now().millisecondsSinceEpoch}.$extension";
          if (Platform.isIOS) {
            String? path = await ImagePickers.saveByteDataImageToGallery(bytes);
            if (path != null && mounted) {
              FlutterToastr.show(localizations.saveSuccess, context, duration: 2, rootNavigator: true);
            }
            return;
          }

          final saved = await FilePicker.saveFile(fileName: fileName, bytes: bytes, type: FileType.image);
          if (saved != null && mounted) {
            FlutterToastr.show(localizations.saveSuccess, context, duration: 2, rootNavigator: true);
          }
        });
  }

  String _imageExtension(Uint8List bytes, String? contentType) {
    var type = contentType?.toLowerCase() ?? '';
    if (type.contains('jpeg') || type.contains('jpg')) return 'jpg';
    if (type.contains('png')) return 'png';
    if (type.contains('webp')) return 'webp';
    if (type.contains('gif')) return 'gif';
    if (type.contains('bmp')) return 'bmp';
    if (type.contains('svg')) return 'svg';

    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'png';
    }
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        (bytes[4] == 0x37 || bytes[4] == 0x39) &&
        bytes[5] == 0x61) {
      return 'gif';
    }
    if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return 'bmp';
    }

    return 'png';
  }

  ///展示请求重写
  Future<void> showRequestRewrite() async {
    HttpRequest? request;
    if (widget.httpMessage == null) {
      return;
    }

    bool isRequest = widget.httpMessage is HttpRequest;
    if (widget.httpMessage is HttpRequest) {
      request = widget.httpMessage as HttpRequest;
    } else {
      request = (widget.httpMessage as HttpResponse).request;
    }
    var requestRewrites = await RequestRewriteManager.instance;

    var ruleType = isRequest ? RuleType.requestReplace : RuleType.responseReplace;
    var rule = requestRewrites.getRequestRewriteRule(request!, ruleType);

    var rewriteItems = await requestRewrites.getRewriteItems(rule);

    if (!mounted) return;

    if (Platforms.isMobile()) {
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => RewriteRule(rule: rule, items: rewriteItems, request: request)));
    } else {
      showDialog(
              context: context,
              barrierDismissible: false,
              builder: (BuildContext context) => RewriteRuleEdit(rule: rule, items: rewriteItems, request: request))
          .then((value) {
        if (value is RequestRewriteRule && mounted) {
          FlutterToastr.show(localizations.saveSuccess, context);
        }
      });
    }
  }

  ///打开新窗口
  void openNew() async {
    if (Platforms.isDesktop()) {
      var size = MediaQuery.of(context).size;
      await DesktopMultiWindow.createWindow(
        jsonEncode({'name': 'HttpBodyWidget', 'httpMessage': widget.httpMessage, 'inNewWindow': true}),
        title: widget.httpMessage is HttpRequest ? localizations.requestBody : localizations.responseBody,
        size: Size(800, size.height),
      );
      return;
    }

    Navigator.push(
        context, MaterialPageRoute(builder: (_) => HttpBodyWidget(httpMessage: widget.httpMessage, inNewWindow: true)));
  }
}

class _Body extends StatefulWidget {
  final HttpMessage? message;
  final ViewType viewType;
  final ScrollController? scrollController;
  final SearchTextController searchController; // 添加搜索设置控制器

  const _Body({
    super.key,
    this.message,
    required this.viewType,
    this.scrollController,
    required this.searchController, // 添加必需参数
  });

  @override
  State<StatefulWidget> createState() {
    return _BodyState();
  }
}

// Top-level isolate function for compute()
// Accepts a Map<String, String> with keys: 'type' and 'body'.
String _formatTextBodyIsolate(Map<String, String> args) {
  final typeName = args['type'] ?? 'text';
  final body = args['body'] ?? '';
  final type = ViewType.values.firstWhere((v) => v.name == typeName, orElse: () => ViewType.text);

  try {
    if (type == ViewType.formUrl) return Uri.decodeFull(body);
    if (type == ViewType.html) return HTML.pretty(body);
    if (type == ViewType.xml) return XML.pretty(body);
    if (type == ViewType.css) return CSS.pretty(body);
    if (type == ViewType.js) return JS.pretty(body);
    if (type == ViewType.jsonText || type == ViewType.json) {
      final jsonObject = json.decode(body);
      return const JsonEncoder.withIndent("  ").convert(jsonObject);
    }
  } catch (_) {}

  return body;
}

class _BodyState extends State<_Body> {
  static const int _virtualizedThreshold = 100000;

  // 由 HexViewer 在（重新）格式化时回传，工具栏复制/编码据此取当前消息完整 Hex 文本。
  Future<String>? _hexFormattedText;

  // 懒保活：访问过的 tab 整树保留（选区、滚动、搜索状态不丢），未访问的 tab 不构建；
  // 切换消息（或解码态变化）时整表清空，旧查看器随之 dispose，内存只保留当前消息的已看 tab。
  final Map<ViewType, Widget> _keptAliveViewers = {};
  int? _keptMessageHash;
  bool? _keptDecodedMode;

  @override
  Widget build(BuildContext context) {
    final parent = context.findAncestorStateOfType<HttpBodyState>();
    final decodedMode = parent?.showDecoded == true && parent?.decoded != null;
    final messageHash = widget.message == null ? null : identityHashCode(widget.message);

    // 解码态切换后 _DecodedHttpMessage 是新实例，旧缓存内容已失效，整体清空。
    if (_keptMessageHash != messageHash || _keptDecodedMode != decodedMode) {
      _keptAliveViewers.clear();
      _keptMessageHash = messageHash;
      _keptDecodedMode = decodedMode;
      _hexFormattedText = null;
    }

    final viewer = _buildViewer(widget.viewType);
    // WebSocket/SSE/空 body 等分支没有 tab 概念，保持原样直接渲染，不进保活容器。
    if (!_isCacheable(widget.viewType)) {
      return viewer;
    }

    // 只存裸查看器 widget：当前类型每帧用新实例覆盖（同位置 Element/State 复用，走 didUpdateWidget），
    // 其它已访问过的 tab 保留上次的实例不动，从而保住选区、滚动和搜索状态。
    _keptAliveViewers[widget.viewType] = viewer;

    // 用 Stack + Offstage 而非 IndexedStack：Offstage 子树报零尺寸，隐藏的固定高查看器
    // （如 HexViewer 的 SizedBox）不会把外层 SingleChildScrollView 撑出多余空白。
    // TickerMode 停掉隐藏子树的帧回调（code_forge 光标闪烁等），省掉隐藏期的绘制开销。
    // 每个 child 的包裹结构在帧间保持恒定，Element 才能稳定复用、不触发重新挂载。
    return Stack(
      children: [
        for (final entry in _keptAliveViewers.entries)
          Offstage(
            offstage: entry.key != widget.viewType,
            child: TickerMode(
              enabled: entry.key == widget.viewType,
              child: ActiveViewerScope(
                active: entry.key == widget.viewType,
                child: entry.value,
              ),
            ),
          ),
      ],
    );
  }

  // 只有带 tab 的常规内容类型进保活；流式消息、空 body 走即时渲染分支。
  // 判断需与 _buildViewer 开头的早返回分支保持一致。
  bool _isCacheable(ViewType type) {
    final parent = context.findAncestorStateOfType<HttpBodyState>();
    final message = _effectiveMessage(parent);
    if (message == null || message.body == null) return false;
    if (message.isWebSocket || (message.contentType == ContentType.sse && message.messages.isNotEmpty)) {
      return false;
    }
    return true;
  }

  HttpMessage? _effectiveMessage(HttpBodyState? parent) {
    final message = widget.message;
    if (parent?.showDecoded == true && parent?.decoded != null && message != null) {
      return _DecodedHttpMessage(message, parent!.decoded!);
    }
    return message;
  }

  Future<String> _formatTextBody(ViewType type, String body) async {
    try {
      if (type == ViewType.formUrl) {
        return Uri.decodeFull(body);
      }

      final heavyTypes = {
        ViewType.html,
        ViewType.xml,
        ViewType.css,
        ViewType.js,
        ViewType.json,
        ViewType.jsonText,
      };

      // For small bodies avoid isolate overhead
      if (!heavyTypes.contains(type) || body.length < 10000) {
        try {
          if (type == ViewType.html) return HTML.pretty(body);
          if (type == ViewType.xml) return XML.pretty(body);
          if (type == ViewType.css) return CSS.pretty(body);
          if (type == ViewType.js) return JS.pretty(body);
          if (type == ViewType.jsonText || type == ViewType.json) {
            final jsonObject = json.decode(body);
            return const JsonEncoder.withIndent("  ").convert(jsonObject);
          }
        } catch (_) {
          return body;
        }
        return body;
      }

      // Use compute to perform heavy formatting in an isolate
      final result = await compute(_formatTextBodyIsolate, {'type': type.name, 'body': body});
      return result;
    } catch (_) {
      return body;
    }
  }

  Future<String?> getBody() async {
    final parent = context.findAncestorStateOfType<HttpBodyState>();
    final currentMessage = _effectiveMessage(parent);

    final streamText = currentMessage?.messagesText;
    if (streamText != null) return streamText;

    if (currentMessage == null || currentMessage.body == null) {
      return null;
    }

    if (widget.viewType == ViewType.hex) {
      return await _hexFormattedText ?? '';
    }

    final body = parent?.showDecoded == true && parent?.decoded?.text != null
        ? parent!.decoded!.text!
        : await currentMessage.decodeBodyString();

    if (widget.viewType == ViewType.text) {
      return body;
    }

    return await _formatTextBody(widget.viewType, body);
  }

  Widget _buildViewer(ViewType type) {
    final parent = context.findAncestorStateOfType<HttpBodyState>();
    final message = _effectiveMessage(parent);

    if (message?.isWebSocket == true ||
        (message?.contentType == ContentType.sse && message?.messages.isNotEmpty == true)) {
      List<Widget>? list = message?.messages
          .map((e) => Container(
              margin: const EdgeInsets.only(top: 2, bottom: 2),
              child: Row(
                children: [
                  Expanded(child: Text(e.payloadDataAsString)),
                  const SizedBox(width: 5),
                  SizedBox(
                      width: 130,
                      child: SelectionContainer.disabled(
                          child: Text(e.time.format(), style: const TextStyle(fontSize: 12, color: Colors.grey))))
                ],
              )))
          .toList();
      return SelectionArea(
        child: Column(
          children: [
            const SelectionContainer.disabled(
                child: Row(children: [
              Expanded(child: Text("Data")),
              SizedBox(width: 130, child: Text("Time")),
            ])),
            Divider(height: 5, thickness: 1, color: Theme.of(context).dividerColor),
            ...list ?? []
          ],
        ),
      );
    }

    if (message == null || message.body == null) {
      return const SizedBox();
    }

    if (type == ViewType.image) {
      return Center(child: Image.memory(Uint8List.fromList(message.body ?? []), fit: BoxFit.scaleDown));
    }
    if (type == ViewType.video) {
      return const Center(child: Text("video not support preview"));
    }
    if (type == ViewType.hex) {
      return HexViewer(
        data: message.body!,
        searchController: widget.searchController,
        // 详情面板外层 SingleChildScrollView 的 controller：Hex 滚到边后把剩余滚动量
        // 级联给 header 所在的外层滚动视图；其它调用点为 null，自动不启用。
        outerScrollController: widget.scrollController,
        onFormattedText: (future) => _hexFormattedText = future,
      );
    }

    if (type == ViewType.formUrl) {
      return HighlightTextWidget(
          text: _formatTextBodyIsolate({'type': type.name, 'body': message.getBodyString()}),
          searchController: widget.searchController,
          contextMenuBuilder: bodyContextMenu);
    }

    return KeyedSubtree(
        key: ValueKey('body-${identityHashCode(message)}-${type.name}'),
        child: futureWidget(message.decodeBodyString(), initialData: message.getBodyString(), (body) {
          try {
            if (type == ViewType.jsonText) {
              var jsonObject = json.decode(body);
              return JsonText(
                  json: jsonObject,
                  indent: Platforms.isDesktop() ? '    ' : '  ',
                  colorTheme: ColorTheme.of(context),
                  searchController: widget.searchController,
                  scrollController: widget.scrollController,
                  contextMenuBuilder: bodyContextMenu);
            }

            if (type == ViewType.json) {
              return JsonViewer(json.decode(body),
                  colorTheme: ColorTheme.of(context), searchController: widget.searchController);
            }

            return _buildTextBodyViewer(type, body, message: message);
          } catch (e) {
            logger.e(e, stackTrace: StackTrace.current);
          }

          return HighlightTextWidget(
              text: body, searchController: widget.searchController, contextMenuBuilder: bodyContextMenu);
        }));
  }

  String? _languageForViewType(ViewType type, HttpMessage? message) {
    switch (type) {
      case ViewType.html:
        return 'html';
      case ViewType.xml:
        return 'xml';
      case ViewType.css:
        return 'css';
      case ViewType.js:
        return 'javascript';
      case ViewType.json:
      case ViewType.jsonText:
        return 'json';
      default:
        return null;
    }
  }

  Widget _buildTextBodyViewer(
    ViewType type,
    String text, {
    HttpMessage? message,
  }) {
    final language = _languageForViewType(type, message);
    final showVirtualized = text.length > _virtualizedThreshold;

    // Format asynchronously (may use compute)
    final futureFormatted = _formatTextBody(type, text);

    return KeyedSubtree(
      key: ValueKey('formatted-body-${identityHashCode(message)}-${type.name}'),
      child: futureWidget(
        initialData: text.substring(0, min(text.length, 10000)), // Show a preview while formatting
        futureFormatted,
        (formattedText) {
          if (showVirtualized) {
            return VirtualizedHighlightText(
              text: formattedText,
              language: language,
              searchController: widget.searchController,
              scrollController: widget.scrollController,
            );
          }

          return HighlightTextWidget(
              language: language,
              text: formattedText,
              searchController: widget.searchController,
              contextMenuBuilder: bodyContextMenu);
        },
      ),
    );
  }
}

class Tabs {
  final List<ViewType> list = [];

  static Tabs of(ContentType? contentType, bool isJsonText) {
    var tabs = Tabs();
    if (contentType == null) {
      return tabs;
    }

    if (contentType == ContentType.video) {
      tabs.list.add(ViewType.video);
      tabs.list.add(ViewType.hex);
      return tabs;
    }

    if (contentType == ContentType.json) {
      tabs.list.add(ViewType.jsonText);
    }

    if (contentType == ContentType.html ||
        contentType == ContentType.xml ||
        contentType == ContentType.js ||
        contentType == ContentType.css) {
      tabs.list.add(ViewType.text);
    }

    tabs.list.add(ViewType.of(contentType) ?? ViewType.text);

    //为json时，增加json格式化
    if (isJsonText && !tabs.list.contains(ViewType.jsonText)) {
      tabs.list.add(ViewType.jsonText);
      tabs.list.add(ViewType.json);
    }

    if (contentType == ContentType.formUrl || contentType == ContentType.json) {
      tabs.list.add(ViewType.text);
    }

    tabs.list.add(ViewType.hex);
    return tabs;
  }

  List<Tab> tabList() {
    return list.map((e) => Tab(text: e.title)).toList();
  }
}

enum ViewType {
  text("Text"),
  formUrl("URL Decode"),
  json("JSON"),
  jsonText("JSON Text"),
  html("HTML"),
  xml("XML"),
  image("Image"),
  video("Video"),
  css("CSS"),
  js("JavaScript"),
  hex("Hex"),
  ;

  final String title;

  const ViewType(this.title);

  static ViewType? of(ContentType contentType) {
    for (var value in values) {
      if (value.name == contentType.name) {
        return value;
      }
    }
    return null;
  }
}

class _DecodedHttpMessage extends HttpMessage {
  final HttpMessage original;
  final CryptoDecodedResult decoded;

  _DecodedHttpMessage(this.original, this.decoded) : super(original.protocolVersion) {
    headers.addAll(original.headers);
    body = decoded.bytes;
  }

  @override
  Map<String, dynamic> toJson() => original.toJson();

  @override
  String? get requestUrl => original.requestUrl;
}
