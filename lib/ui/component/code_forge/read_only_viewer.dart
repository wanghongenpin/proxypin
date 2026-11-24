/*
 * Copyright 2026 Hongen Wang All rights reserved.
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
import 'dart:async';
import 'dart:math';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import '../search/active_viewer_scope.dart';
import '../search/search_controller.dart';

// 可视行窗口外预留的行数，滚动到窗口边缘前就提前纳入高亮。
const int _highlightWindowMargin = 20;

// 匹配数不超过该值时原生路径足够便宜，直接把全量高亮交给渲染层。
const int _highlightWindowThreshold = 80;

// 交给渲染层的高亮硬上限。code_forge 绘制时每帧对每条高亮做两次 getLineAtOffset FFI
// 判可见性（见 code_area.dart _drawSearchHighlights），单次 FFI 实测约 4.6 微秒，
// 绘制帧耗时随高亮数线性增长：2000 条约 125ms、500 条约 33ms、200 条约 14ms。
// 大文档高密度匹配（如 1.5MB 文本搜单字符产生约 150 万匹配）不封顶时每帧数百万次 FFI，
// 实测搜索稳定 321 秒、滚动 29 秒/帧；按行窗口化也救不回来——单个可见长行本身就有上万匹配。
// 这里在窗口化之后再均匀抽稀到 200 条（约 14ms 帧，贴近单帧预算）：正常搜索匹配数低于该值
// 时全量显示，只有病态高密度才抽稀，而高密度匹配在屏幕上本就是连成一片的色带，亚像素重叠项
// 裁掉无视觉差异，当前匹配单独保留。
const int _maxRenderedHighlights = 200;

// 内容很少时查看器仍保留的最小高度：留出可点击、可滚动的基本视口，避免缩成一两行难以交互。
const double _defaultMinViewerHeight = 240.0;

// 大内容/加载态的视口高度：屏高减去头部工具栏等占用，沿用历史值。
const double _defaultViewportTopOffset = 210.0;

const double _defaultFontSize = 14.5;

// code_forge 内置垂直滚动条默认 thickness 是 15，偏宽；只改细宽度，其它行为保持默认。
const double _scrollbarThickness = 8.0;

// Hex 文档行数多，thumb 自然长度很小，基本贴着默认 minThumbLength 18 画，显得太短。
// 调大下限让它更长、更容易点按；minOverscrollLength 不传时会自动取这个值，无需单独设置。
const double _scrollbarMinThumbLength = 48.0;

/// 字符偏移到行号的索引。code_forge 渲染对象每帧会对全部搜索高亮各做两次 charToLine FFI
/// 来判断可见性，匹配数很大时每帧上万次 FFI，导致查找导航明显卡顿。
/// 查看器只把可视窗口内的高亮交给渲染层，行号判断在 Dart 侧完成：
/// 定长文本（如 Hex）整除即可，普通文本按换行符位置二分。
class LineIndexer {
  final List<int> lineStarts;

  LineIndexer._(this.lineStarts);

  /// 扫描文本中所有换行符，记录每行首字符的偏移。
  factory LineIndexer.of(String text) {
    final starts = <int>[0];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        starts.add(i + 1);
      }
    }
    return LineIndexer._(starts);
  }

  /// 返回字符偏移所在的零基行号（偏移落在行内任意位置都返回该行）。
  int lineOfOffset(int offset) {
    // lower bound：最大的满足 lineStarts[i] <= offset 的 i。
    var lo = 0;
    var hi = lineStarts.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (lineStarts[mid] <= offset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return max(0, lo - 1);
  }
}

/// 基于 code_forge 的只读文档查看器，承载 Hex 之外的纯文本类 body（CSS/XML/JS/HTML/Text 等）。
///
/// 通用机制全部沉淀在这里，各调用方只提供文本（可同步字符串或格式化 Future）、高亮语言和行高：
/// 控制器生命周期与防竞态、共享搜索控制器对接、IME 只读连接重连、搜索高亮窗口化、
/// 内外滚动级联、小内容高度收缩、右键菜单不透明配色。
class CodeForgeReadOnlyViewer extends StatefulWidget {
  /// 文档内容。传 [String] 时同帧同步挂载（无 loading 闪烁）；传 [Future<String>] 时
  /// 完成前显示加载指示，适合 isolate 格式化的大 body。
  final FutureOr<String> text;

  final SearchTextController searchController;

  /// re_highlight 语法模式；null 表示纯文本不做语法高亮（Hex 场景）。
  final Mode? language;

  /// 是否按视口宽度自动换行。默认 false（长行横向滚动，Hex/CSS 等场景）；
  /// 纯文本/表单等延续旧 SelectableText 软换行习惯的视图传 true。
  /// 换行后行几何由 code_forge 内部持有，滚动到匹配行改用其内置的换行感知回调，
  /// 高度收缩仍按逻辑行数估算（实际不换行的短内容估算精确，长行在固定视口内滚动）。
  final bool lineWrap;

  final double fontSize;

  /// 行高（像素）。滚动定位和高度收缩都依赖它，调用方需与 CodeForge 实际行高保持一致；
  /// code_forge 未显式设置 height 时行高倍率为 1.2。
  final double lineHeight;

  final String fontFamily;

  /// 自定义语法配色；默认按明暗主题使用 atom-one 系列，root 背景固定为 surface
  /// （code_forge 右键菜单直接取 root.backgroundColor，透明色会导致菜单半透明）。
  final Map<String, TextStyle>? editorTheme;

  /// 行号槽（gutter）内容构建器。null（默认）时不显示 gutter；非 null 时启用 gutter，
  /// 回调拿到 1 基行号与该行文本，返回值替换 code_forge 默认的自增序号（如 Hex 视图
  /// 用它显示每行首字节偏移）。始终返回非 null 文本可让渲染层把 gutter 宽度扩到完整宽度。
  final GutterBuilder? gutterBuilder;

  /// gutter 样式，仅在 [gutterBuilder] 非 null 时生效；null 时由 code_forge 按编辑器配色推导。
  final GutterStyle? gutterStyle;

  /// 行号槽与正文之间的额外间距（像素）。映射到 CodeForge 的 innerPadding.left：
  /// gutter 背景宽度不变，只把正文整体右移，从而拉开行号与内容的距离；null/0 时无额外间距。
  final double? gutterSpacing;

  /// 外层（header 所在）滚动视图的 controller。内部滚到边后，剩余滚动量交给它，
  /// 实现 header ↔ body 级联；为 null 时不启用级联。
  final ScrollController? outerScrollController;

  /// 每次（重新）加载都会把当前文档对应的 Future 回传，供父级获取完整文本（如工具栏复制）。
  final ValueChanged<Future<String>>? onFormattedText;

  /// 追加到 code_forge 右键菜单的自定义项（如“发送到解码器 / AES 解密”），构建时拿到当前
  /// 控制器以便回调里读取选中文本。code_forge 只在桌面端菜单渲染这些项，移动端无扩展点。
  /// null（默认）时菜单保持 code_forge 自带的复制 / 全选。
  final List<CustomContextMenu> Function(CodeForgeController controller)? contextMenuItemsBuilder;

  final double minHeight;

  final double viewportTopOffset;

  const CodeForgeReadOnlyViewer({
    super.key,
    required this.text,
    required this.searchController,
    this.language,
    this.lineWrap = false,
    this.fontSize = _defaultFontSize,
    double? lineHeight,
    this.fontFamily = 'monospace',
    this.editorTheme,
    this.gutterBuilder,
    this.gutterStyle,
    this.gutterSpacing,
    this.outerScrollController,
    this.onFormattedText,
    this.contextMenuItemsBuilder,
    this.minHeight = _defaultMinViewerHeight,
    this.viewportTopOffset = _defaultViewportTopOffset,
  }) : lineHeight = lineHeight ?? fontSize * 1.2;

  @override
  State<CodeForgeReadOnlyViewer> createState() => CodeForgeReadOnlyViewerState();
}

class CodeForgeReadOnlyViewerState extends State<CodeForgeReadOnlyViewer> {
  late Future<String> _formattedText;
  CodeForgeController? _controller;
  FindController? _findController;
  // 不能复用：code_forge 渲染对象构造时向外部 ScrollController 注册的匿名监听
  // 在其 dispose 中不会被移除，复用会让已释放的渲染对象继续收到滚动通知而崩溃，
  // 因此每次 _load 都新建一个，旧的延迟到本帧结束（旧渲染对象卸载、position detach）后释放。
  ScrollController _vScrollController = ScrollController();
  // 自持焦点节点传给 CodeForge：编辑器获得焦点时需要保证其 IME 连接有效（见 _onEditorFocusChanged）。
  // code_forge 不 dispose 外部传入的 focusNode，生命周期由本组件管理。
  final FocusNode _editorFocusNode = FocusNode();
  Object? _error;
  int _loadId = 0;
  bool _syncingSearch = false;
  // 搜索控制器通知合并标记：同一帧内的多次通知（连续输入）只在帧后同步一次。
  bool _searchNotifyScheduled = false;
  // 懒保活下是否为当前可见查看器：隐藏期间不响应共享搜索、不回写计数。
  bool _isActive = true;
  String _searchSignature = '';
  int _findMatchIndex = -1;

  // 搜索高亮窗口化相关状态。
  LineIndexer? _lineIndexer;
  int _appliedWindowFirst = -1;
  int _appliedWindowLast = -1;
  // FindController 每次更新都会写回全量高亮，这里在窗口化前留存一份，供滚动时重建窗口。
  List<SearchHighlight> _allHighlights = const [];
  bool _isWindowed = false;

  // 供外层封装（如 HexViewer）和测试访问的内部状态，不使用 visibleForTesting：
  // HexViewerState 的同名测试入口在生产代码里透传这些 getter。
  CodeForgeController? get controller => _controller;

  FindController? get findController => _findController;

  FocusNode get editorFocusNode => _editorFocusNode;

  ScrollController get scrollController => _vScrollController;

  Future<String> get formattedText => _formattedText;

  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(_onSearchNotified);
    _vScrollController.addListener(_onScroll);
    _editorFocusNode.addListener(_onEditorFocusChanged);
    _load(widget.text);
  }

  @override
  void didUpdateWidget(covariant CodeForgeReadOnlyViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchController != widget.searchController) {
      oldWidget.searchController.removeListener(_onSearchNotified);
      widget.searchController.addListener(_onSearchNotified);
      _searchSignature = '';
      // build 阶段不能同步触发搜索同步：它会写 GetX Rx，导致监听的 Obx 在构建中 markNeedsBuild。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncSearch();
      });
    }
    // 调用方每次内容变化都会传入新的 String/Future 实例，按身份判断即可。
    if (!identical(oldWidget.text, widget.text)) {
      _load(widget.text);
    }
  }

  void _load(FutureOr<String> text) {
    final loadId = ++_loadId;
    final oldController = _controller;
    final oldFindController = _findController;
    final oldScrollController = _vScrollController;
    _controller = null;
    _findController = null;
    _appliedWindowFirst = -1;
    _appliedWindowLast = -1;
    _isWindowed = false;
    // 旧组件在本帧仍持有该 controller，延迟到下一帧再释放，避免帧内 use-after-dispose。
    // 旧 ScrollController 同样延迟释放：它的 position 要等旧渲染对象本帧卸载时才 detach，
    // 且上面还残留 code_forge 渲染对象未清理的匿名监听。
    if (oldController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldFindController?.dispose();
        oldController.dispose();
        oldScrollController.dispose();
      });
    }
    // 首次加载复用字段初始化的实例（监听已在 initState 注册）；
    // 加载途中再次切数据时 oldController 为 null，保留当前实例，避免重复注册监听。
    if (oldController != null) {
      _vScrollController = ScrollController()..addListener(_onScroll);
    }
    // totalMatchCount 是 GetX Rx，可能正被 Obx 监听；didUpdateWidget 处于 build 阶段，
    // 同步写入会触发 Obx 在构建中 markNeedsBuild，统一延迟到帧后再清零。
    // 仅当仍在加载（新 FindController 尚未挂载）时清零，避免覆盖提前完成后算出的真实匹配数。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && loadId == _loadId && _findController == null) {
        widget.searchController.totalMatchCount.value = 0;
      }
    });
    _error = null;

    if (text is String) {
      // 小数据同步格式化并在同一帧挂载，切换消息时不出现 loading 闪烁。
      _formattedText = Future<String>.value(text);
      widget.onFormattedText?.call(_formattedText);
      // 同步路径可能运行在 didUpdateWidget 的 build 阶段，搜索同步会写 GetX Rx，需延迟到帧后。
      _mountController(text, loadId, deferSearchSync: true);
      return;
    }

    // 异步内容（isolate 格式化）完成前显示加载指示，避免大 body 的字符串处理阻塞主线程。
    _formattedText = text;
    widget.onFormattedText?.call(_formattedText);
    if (loadId > 1) setState(() {});

    () async {
      try {
        final formatted = await _formattedText;
        if (!mounted || loadId != _loadId) return;
        _mountController(formatted, loadId);
      } catch (e) {
        if (mounted && loadId == _loadId) {
          setState(() => _error = e);
        }
      }
    }();
  }

  // 用已格式化的文本构建并挂载新的 CodeForge/Find 控制器。同步文本在 _load 中同步调用，
  // 异步 Future 在完成后调用；两者后续流程一致。
  // deferSearchSync：同步挂载可能处于 build 阶段（didUpdateWidget），而搜索同步会写
  // GetX Rx，需延迟到帧后；异步回调本就在帧外，无需延迟。
  void _mountController(String formatted, int loadId, {bool deferSearchSync = false}) {
    _lineIndexer = LineIndexer.of(formatted);

    final controller = CodeForgeController()
      ..readOnly = true
      ..text = formatted;
    // 首帧前先占位，避免挂载当帧的搜索同步走到自带回调；渲染对象构造时会覆盖一次，
    // 因此下面首帧后还要再设置回来。换行模式不覆盖：自带回调按换行后的真实行高定位，
    // 本组件的固定行高算法只在非换行时成立。
    if (!widget.lineWrap) {
      controller.setScrollCallback(_scrollToLineWithoutHighlight);
    }
    final findController = FindController(controller)..addListener(_onFindChanged);
    setState(() {
      _controller = controller;
      _findController = findController;
    });
    // CodeForge 的渲染对象在挂载时会绑定自带的滚动回调，需等到首帧之后再覆盖，
    // 否则会被还原。自带回调会在滚动结束后对目标行播放 800ms 整行淡出高亮，
    // 连续查找时旧动画回调会把灰色背景打到过期行上；本查看器行高固定，直接按
    // 行号滚动即可，无需整行高亮。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller == controller) {
        // 换行模式保留渲染对象自带的换行感知滚动回调，不要用固定行高版本覆盖。
        if (!widget.lineWrap) {
          controller.setScrollCallback(_scrollToLineWithoutHighlight);
        }
        // 新内容挂载后回到顶部（每次 _load 都是全新的 ScrollController，
        // 此 jumpTo 主要用于同实例重试加载的场景），与此前每次新建内部 controller 的行为一致。
        if (_vScrollController.hasClients) {
          _vScrollController.jumpTo(0);
        }
        _applyHighlightWindow(force: true);
      }
    });
    _searchSignature = '';
    _findMatchIndex = -1;
    if (deferSearchSync) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && loadId == _loadId) _syncSearch();
      });
    } else {
      _syncSearch();
    }
  }

  @override
  void dispose() {
    _loadId++;
    widget.searchController.removeListener(_onSearchNotified);
    _editorFocusNode.removeListener(_onEditorFocusChanged);
    _editorFocusNode.dispose();
    _findController?.dispose();
    _controller?.dispose();
    _vScrollController.dispose();
    super.dispose();
  }

  // 搜索浮层的 TextField 获得焦点时，框架会把编辑器的 TextInputConnection 置为 detached
  // （平台只允许一个输入连接）。只读模式下 code_forge 自身不会重连（它的焦点监听和 _resetImeConnection
  // 都有 readOnly 早退），且仍保留这条失效引用；之后在编辑器里按下鼠标时，handleEvent 先
  // requestFocus 再对连接做强制调用，失效连接会抛 attached 断言、null 连接会抛空指针，
  // 本次指针事件直接中断，拖拽选择文字随之失效——表现为"搜索时有时选不中文字"。
  // 这里在编辑器重新获得焦点的同步监听里，用公开的 TextInput.attach 补一条只读连接：
  // 监听在 code_forge 自己的焦点监听之后执行，此刻它的 requestFocus 流程尚未走到连接调用，
  // 补好的连接让后续强制调用全部安全通过；连接配置与 code_forge 内部 _attachImeConnection 对齐。
  void _onEditorFocusChanged() {
    if (!_editorFocusNode.hasFocus) return;
    final controller = _controller;
    if (controller == null) return;
    final connection = controller.connection;
    if (connection != null && connection.attached) return;
    final fresh = TextInput.attach(
      controller,
      TextInputConfiguration(
        readOnly: true,
        enableDeltaModel: true,
        enableSuggestions: false,
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        autocorrect: false,
        viewId: View.of(context).viewId,
      ),
    );
    controller.connection = fresh;
  }

  // 替代 code_forge 渲染对象内置的 _scrollToLine：保持相同的居中滚动语义，
  // 但不触发整行淡出动画（见 _load 中的说明）。
  void _scrollToLineWithoutHighlight(int line) {
    if (!_vScrollController.hasClients) return;
    final position = _vScrollController.position;
    final targetY = line * widget.lineHeight;
    final target = (targetY + widget.lineHeight / 2 - position.viewportDimension / 2)
        .clamp(0.0, position.maxScrollExtent);
    position.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onFindChanged() {
    final find = _findController;
    if (find == null || _syncingSearch || !_isActive) return;
    _findMatchIndex = find.currentMatchIndex;
    widget.searchController.currentMatchIndex.value = max(0, find.currentMatchIndex);
    widget.searchController.updateMatchCount(find.matchCount);
    _applyHighlightWindow(force: true);
  }

  void _onScroll() {
    _applyHighlightWindow();
  }

  // 触摸拖拽级联：内部 ClampingScrollPhysics 把越界量通过 OverscrollNotification 冒泡上来。
  // overscroll 与拖拽增量同号（顶部越界为负、底部为正），直接转给外层即可。
  // 鼠标滚轮/触控板无需这里处理：内层到边时不会注册 pointerSignalResolver，
  // 外层 Scrollable 会自然接管同一滚轮事件（Flutter 框架自带的嵌套滚动级联）。
  bool _onOverscroll(OverscrollNotification notification) {
    final outer = widget.outerScrollController;
    if (outer == null || !outer.hasClients || notification.metrics.axis != Axis.vertical) return false;
    final position = outer.position;
    final overscroll = notification.overscroll;
    if (overscroll > 0 && position.pixels >= position.maxScrollExtent) return false;
    if (overscroll < 0 && position.pixels <= position.minScrollExtent) return false;
    position.jumpTo((position.pixels + overscroll).clamp(position.minScrollExtent, position.maxScrollExtent));
    return true;
  }

  // code_forge 渲染对象每帧会对全部搜索高亮各做两次 charToLine FFI 来判断可见性，
  // 匹配数很大时（长文档常见上千个匹配）每帧上万次 FFI，导致查找导航明显卡顿。
  // 这里只把可视窗口内的高亮交给渲染层，字符偏移到行号在 Dart 侧完成（见 [LineIndexer]），
  // 并在最后做全局封顶（见 [_capHighlights]），防止单个可见长行携带上万匹配时 FFI 风暴。
  void _applyHighlightWindow({bool force = false}) {
    final controller = _controller;
    final indexer = _lineIndexer;
    if (controller == null || indexer == null || !_vScrollController.hasClients) return;

    if (force) {
      // FindController 刚把全量高亮（或空列表）写回 controller，留存一份再决定是否窗口化。
      final fresh = controller.searchHighlights;
      _allHighlights = fresh;
      _isWindowed = false;
      _appliedWindowFirst = -1;
      _appliedWindowLast = -1;
      // 小匹配量原生路径足够便宜，直接用全量（阈值远小于渲染封顶，无需抽稀）。
      if (fresh.length <= _highlightWindowThreshold) return;
    } else if (!_isWindowed) {
      // 纯滚动且当前不是窗口模式（无搜索或匹配量小），无需处理。
      return;
    }

    final all = _allHighlights;
    if (all.isEmpty) return;

    // 换行模式不做按行窗口化：可视行按像素/固定行高换算，单个被折成大量视觉行的超长逻辑行
    // 一旦滚出估算窗口，它上面的匹配会被整行剔除（搜索看不到高亮、导航失效）。
    // 但仍要做全局封顶：换行只影响绘制几何，_drawSearchHighlights 的全量 FFI 遍历依旧存在。
    // 封顶与滚动位置无关，force 重算一次后滚动直接复用。
    if (widget.lineWrap) {
      if (!force || all.length <= _maxRenderedHighlights) return;
      // 换行不做按行窗口，对全量下标区间直接抽稀封顶。
      controller.searchHighlights = _capRange(all, 0, all.length);
      controller.searchHighlightsChanged = true;
      _isWindowed = true;
      return;
    }

    final position = _vScrollController.position;
    final firstLine = max(0, (position.pixels / widget.lineHeight).floor() - _highlightWindowMargin);
    final lastLine =
        ((position.pixels + position.viewportDimension) / widget.lineHeight).ceil() + _highlightWindowMargin;

    // 现有窗口仍完整覆盖可视区域（含半程余量）时无需重建，避免滚动动画每帧分配新列表。
    if (!force &&
        _appliedWindowFirst >= 0 &&
        firstLine >= _appliedWindowFirst + _highlightWindowMargin ~/ 2 &&
        lastLine <= _appliedWindowLast - _highlightWindowMargin ~/ 2) {
      return;
    }

    // 高亮按 start 偏移升序（正则匹配顺序），把可视行区间换算成字符偏移区间后二分切片，
    // 避免滚动重建时对上百万条全量高亮逐条 lineOfOffset（实测这是滚动帧 70ms 的主因）。
    final lineStarts = indexer.lineStarts;
    final startOffset = lineStarts[firstLine];
    final endOffset = lastLine + 1 < lineStarts.length ? lineStarts[lastLine + 1] : null;
    final firstIdx = _lowerBoundByStart(all, startOffset);
    final lastIdx = endOffset == null ? all.length : _lowerBoundByStart(all, endOffset);
    // 直接在下标区间内取样封顶，不物化整个窗口（高密度文档的窗口仍可能有几十万条，
    // sublist 整体复制本身就要数十毫秒）。
    controller.searchHighlights = _capRange(all, firstIdx, lastIdx);
    controller.searchHighlightsChanged = true;
    _isWindowed = true;
    _appliedWindowFirst = firstLine;
    _appliedWindowLast = lastLine;
  }

  // 在按 start 升序的高亮列表里二分查找第一个 start >= offset 的下标。
  int _lowerBoundByStart(List<SearchHighlight> highlights, int offset) {
    var lo = 0;
    var hi = highlights.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (highlights[mid].start < offset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  // 在高亮列表的下标区间 [from, to) 内均匀取样，最多交给渲染层 [_maxRenderedHighlights] 条，
  // 不物化整个区间（高密度文档的可视区间仍可能有几十万条）。视口内可像素分辨的高亮数量远低于
  // 该上限，被抽掉的都是亚像素重叠项，视觉无差异；当前匹配（下标即 FindController 的
  // currentMatchIndex，高亮按匹配顺序构建）落在区间内时必须保留，否则导航时活动高亮会消失。
  // 匹配总数仍取自 FindController 全量计数，UI 上的 1/N 不受抽稀影响。
  List<SearchHighlight> _capRange(List<SearchHighlight> source, int from, int to) {
    final rangeLength = to - from;
    if (rangeLength <= 0) return const [];
    if (rangeLength <= _maxRenderedHighlights) return source.sublist(from, to);

    final stride = rangeLength / _maxRenderedHighlights;
    final capped = <SearchHighlight>[];
    for (var i = 0; i < _maxRenderedHighlights; i++) {
      capped.add(source[from + (i * stride).floor()]);
    }
    final current = _findMatchIndex;
    if (current >= from && current < to && capped.every((highlight) => !highlight.isCurrentMatch)) {
      capped[0] = source[current];
    }
    return capped;
  }

  // 搜索控制器的通知统一延迟到帧后再同步，而不是在监听回调里立即处理。
  // showSearchOverlay 是"先写回 pattern、后插入浮层"：写回触发通知时浮层尚未插入，
  // shouldSearch() 仍为 false，立即同步会把搜索误判为停用；浮层插入后又不再有任何事件，
  // 表现为关闭搜索框再打开时不会重新触发。对齐其它视图 AnimatedBuilder 的"帧后拉取"模式。
  // 同一帧内的多次通知合并成一次同步，连续输入只跑一次。
  void _onSearchNotified() {
    if (_searchNotifyScheduled) return;
    _searchNotifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchNotifyScheduled = false;
      if (mounted) _syncSearch();
    });
  }

  void _syncSearch() {
    if (_syncingSearch || !_isActive) return;
    final find = _findController;
    if (find == null) return;

    final search = widget.searchController;
    final settings = search.value;
    final shouldSearch = search.shouldSearch();
    final signature = '$shouldSearch|${settings.pattern}|${settings.isCaseSensitive}|${settings.isRegExp}';
    _syncingSearch = true;
    try {
      if (signature != _searchSignature) {
        _searchSignature = signature;
        find.caseSensitive = settings.isCaseSensitive;
        find.isRegex = settings.isRegExp;
        find.isActive = shouldSearch;
        find.findInputController.text = shouldSearch ? settings.pattern : '';
        if (shouldSearch && settings.pattern.isNotEmpty) {
          find.find(settings.pattern);
        }
      } else if (find.matchCount > 0 && _findMatchIndex != search.currentMatchIndex.value) {
        // 取环绕最短路径的方向导航。旧实现只按正向差值循环 next()：按"上一个"时差值为 -1，
        // 被 % 换算成 N-1 次 next()，等于从当前匹配绕整整一圈，N 次滚动动画/高亮更新叠加，
        // 匹配一多就明显比"下一个"卡。反向差值直接走 previous()，任何单步导航都只调一次。
        final total = find.matchCount;
        var forward = (search.currentMatchIndex.value - _findMatchIndex) % total;
        if (forward < 0) forward += total;
        final backward = total - forward;
        if (forward <= backward) {
          for (var i = 0; i < forward; i++) {
            find.next();
          }
        } else {
          for (var i = 0; i < backward; i++) {
            find.previous();
          }
        }
      }
    } finally {
      _syncingSearch = false;
    }
    _onFindChanged();
  }

  Map<String, TextStyle> _resolveEditorTheme(BuildContext context) {
    final custom = widget.editorTheme;
    if (custom != null) return custom;
    final brightness = Theme.of(context).brightness;
    final base = brightness == Brightness.light ? atomOneLightTheme : atomOneDarkTheme;
    // code_forge 的右键菜单底色直接取 root.backgroundColor；atom-one 的 root 自带背景色，
    // 换成宿主卡片的 surface 视觉无变化，但菜单随之不透明，与其它视图的选区菜单配色一致。
    return {
      ...base,
      'root': (base['root'] ?? const TextStyle()).copyWith(backgroundColor: Theme.of(context).colorScheme.surface),
    };
  }

  @override
  Widget build(BuildContext context) {
    final viewportHeight = max(widget.minHeight, MediaQuery.sizeOf(context).height - widget.viewportTopOffset);
    // 依赖作用域：Offstage 切回时本组件随 ActiveViewerScope 一起重建。
    final active = ActiveViewerScope.isActive(context);
    if (active && !_isActive) {
      // 重新激活后补一次搜索同步，把隐藏期间错过的共享搜索状态应用到 FindController，
      // 并让本查看器重新成为计数/导航的归属者。延迟到帧后，避免 build 阶段写 Rx。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isActive) _syncSearch();
      });
    }
    _isActive = active;
    final error = _error;
    final controller = _controller;
    if (error != null) {
      return SizedBox(height: viewportHeight, child: Center(child: Text('Code viewer unavailable: $error')));
    }
    if (controller == null) {
      return SizedBox(height: viewportHeight, child: const Center(child: CircularProgressIndicator()));
    }

    // code_forge 的渲染对象在拿到紧高度约束时会把字段高度撑满该约束（performLayout 里
    // contentHeight = max(内容高, constraints.maxHeight)），固定一屏高会让只有几行的
    // 小 body 也留出大片空白。按真实行数算出内容自然高度，内容不足一屏就收缩、超出仍保持
    // 视口高度由内部滚动；下限保留最小可用高度。
    final contentHeight = controller.lineCount * widget.lineHeight;
    final height = max(widget.minHeight, min(viewportHeight, contentHeight));

    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      height: height,
      child: NotificationListener<OverscrollNotification>(
        onNotification: _onOverscroll,
        // code_forge 在 lineWrap=false 时把字段最小宽度取成 MediaQuery.size.width（整屏宽），
        // 而查看器实际视口因面板/卡片内边距比整屏窄，内容会被撑出一段并不存在的横向越界。
        // 用 LayoutBuilder 取真实视口宽度并覆盖子树 MediaQuery.size，让最小宽度等于实际可用
        // 宽度，消除短内容也能左右滚动的问题；真正超长的行仍按自身宽度正常横向滚动。
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mediaQuery = MediaQuery.of(context);
            final viewWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : mediaQuery.size.width;
            return MediaQuery(
              data: mediaQuery.copyWith(size: Size(viewWidth, mediaQuery.size.height)),
              child: CodeForge(
                // CodeForge 只在 initState 读取 verticalScrollController，didUpdateWidget 不处理其变化。
                // 同步路径没有 loading 帧、CodeForge 不会自然卸载，这里用随 _loadId 变化的 key 强制重建，
                // 让新 State 重新捕获当前的 ScrollController，否则会继续持有已被释放的旧实例。
                // lineWrap 在渲染对象里是 late final、didUpdateWidget 不响应切换，一并纳入 key 强制重建。
                key: ValueKey<String>('$_loadId-${widget.lineWrap}'),
                controller: controller,
                findController: _findController,
                focusNode: _editorFocusNode,
                verticalScrollController: _vScrollController,
                language: widget.language,
                lineWrap: widget.lineWrap,
                // 覆盖 code_forge 默认的 thickness 15；thumbColor 沿用其默认 decoration 的取色
                // （编辑器文字色 withAlpha(150)），只改宽度不改观感。
                scrollbarDecoration: ScrollbarDecoration(
                  thickness: _scrollbarThickness,
                  minThumbLength: _scrollbarMinThumbLength,
                  thumbColor: theme.colorScheme.onSurface.withValues(alpha: 150 / 255),
                ),
                readOnly: true,
                // 仅在调用方提供 gutterBuilder 时启用行号槽；默认关闭，纯文本视图保持原样。
                enableGutter: widget.gutterBuilder != null,
                gutterBuilder: widget.gutterBuilder,
                gutterStyle: widget.gutterStyle,
                // 只在指定间距时传 innerPadding，未指定保持 null（code_forge 默认无内边距）。
                // left 同时计入内容宽，长行横向滚动范围会相应增加，与 gutter 占宽同理。
                innerPadding: widget.gutterSpacing != null ? EdgeInsets.only(left: widget.gutterSpacing!) : null,
                enableFolding: false,
                enableGuideLines: false,
                enableLocalSuggestions: false,
                enableKeyboardSuggestions: false,
                editorTheme: _resolveEditorTheme(context),
                textStyle: TextStyle(fontFamily: widget.fontFamily, fontSize: widget.fontSize),
                selectionStyle: CodeSelectionStyle(
                  selectionColor: theme.colorScheme.primary.withValues(alpha: 0.3),
                  cursorBubbleColor: theme.colorScheme.primary,
                ),
                matchHighlightStyle: MatchHighlightStyle(
                  currentMatchStyle: TextStyle(backgroundColor: theme.colorScheme.primary),
                  otherMatchStyle: TextStyle(backgroundColor: theme.colorScheme.inversePrimary),
                ),
                // 仅桌面端菜单会渲染这些自定义项（见 code_forge _buildContextMenu）。
                customContextMenuItems: widget.contextMenuItemsBuilder?.call(controller),
              ),
            );
          },
        ),
      ),
    );
  }
}
