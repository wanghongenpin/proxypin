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
import 'dart:math';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/ui/component/search/active_viewer_scope.dart';
import 'package:proxypin/ui/component/search/search_controller.dart';

String _formatHexIsolate(Map<String, Object> args) => formatHex(args['data'] as List<int>, args['bytesPerRow'] as int);

// 与 CodeForge textStyle 的字号保持一致；code_forge 未显式设置 height 时行高倍率为 1.2。
const double _hexFontSize = 14;
const double _hexLineHeight = _hexFontSize * 1.2;

// 可视行窗口外预留的行数，滚动到窗口边缘前就提前纳入高亮。
const int _highlightWindowMargin = 20;

// 小于该字节数直接在主 isolate 同步格式化：compute 的 isolate 往返至少跨一帧，
// 小消息也走异步会在切换时闪一下 loading。超过阈值才进后台 isolate，避免大 body 阻塞 UI。
const int _syncFormatByteLimit = 256 * 1024;

// 内容很少时查看器仍保留的最小高度：留出可点击、可滚动的基本视口，避免缩成一两行难以交互。
const double _minViewerHeight = 240.0;

// 大内容/加载态的视口高度：屏高减去头部工具栏等占用，沿用历史值。
const double _viewerViewportTopOffset = 210.0;

// code_forge 内置垂直滚动条默认 thickness 是 15，偏宽；只改细宽度，其它行为保持默认。
const double _scrollbarThickness = 8.0;

// Hex 文档行数多，thumb 自然长度很小，基本贴着默认 minThumbLength 18 画，显得太短。
// 调大下限让它更长、更容易点按；minOverscrollLength 不传时会自动取这个值，无需单独设置。
const double _scrollbarMinThumbLength = 48.0;

@visibleForTesting
String formatHex(List<int> data, int bytesPerRow) {
  final buffer = StringBuffer();
  for (int i = 0; i < data.length; i += bytesPerRow) {
    for (int j = 0; j < bytesPerRow; j++) {
      if (i + j < data.length) {
        buffer.write(data[i + j].toRadixString(16).padLeft(2, '0'));
      } else {
        buffer.write('  ');
      }
      buffer.write(' ');
    }

    buffer.write('    ');
    for (int j = 0; j < bytesPerRow && i + j < data.length; j++) {
      final byte = data[i + j];
      buffer.write(byte >= 32 && byte <= 126 ? String.fromCharCode(byte) : '.');
    }
    buffer.writeln();
  }
  return buffer.toString();
}

class HexViewer extends StatefulWidget {
  final List<int> data;
  final int bytesPerRow;
  final SearchTextController searchController;

  /// 外层（header 所在）滚动视图的 controller。内部 Hex 滚到边后，剩余滚动量交给它，
  /// 实现 header ↔ body 级联；为 null 时不启用级联（如新窗口、请求编辑页等无外层滚动的场景）。
  final ScrollController? outerScrollController;

  /// 每次（重新）格式化都会把当前消息对应的 Future 回传，供父级获取完整 Hex 文本，
  /// 避免父级持有 GlobalKey（子树重挂载时 GlobalKey 容易出现多实例冲突）。
  final ValueChanged<Future<String>>? onFormattedText;

  const HexViewer({
    super.key,
    required this.data,
    this.bytesPerRow = 16,
    required this.searchController,
    this.outerScrollController,
    this.onFormattedText,
  });

  @override
  State<HexViewer> createState() => HexViewerState();
}

class HexViewerState extends State<HexViewer> {
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
  int _lineCharLength = 1;
  int _appliedWindowFirst = -1;
  int _appliedWindowLast = -1;
  // FindController 每次更新都会写回全量高亮，这里在窗口化前留存一份，供滚动时重建窗口。
  List<SearchHighlight> _allHighlights = const [];
  bool _isWindowed = false;

  @visibleForTesting
  CodeForgeController? get controller => _controller;

  @visibleForTesting
  FindController? get findController => _findController;

  @visibleForTesting
  FocusNode get editorFocusNode => _editorFocusNode;

  @visibleForTesting
  ScrollController get scrollController => _vScrollController;

  @visibleForTesting
  Future<String> get formattedText => _formattedText;

  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(_onSearchNotified);
    _vScrollController.addListener(_onScroll);
    _editorFocusNode.addListener(_onEditorFocusChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant HexViewer oldWidget) {
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
    if (!identical(oldWidget.data, widget.data) || oldWidget.bytesPerRow != widget.bytesPerRow) {
      _load();
    }
  }

  void _load() {
    final loadId = ++_loadId;
    final oldController = _controller;
    final oldFindController = _findController;
    final oldScrollController = _vScrollController;
    _controller = null;
    _findController = null;
    _appliedWindowFirst = -1;
    _appliedWindowLast = -1;
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

    final data = widget.data;
    if (data.length <= _syncFormatByteLimit) {
      // 小数据同步格式化并在同一帧挂载，切换消息时不出现 loading 闪烁。
      final formatted = formatHex(data, widget.bytesPerRow);
      _formattedText = Future<String>.value(formatted);
      widget.onFormattedText?.call(_formattedText);
      // 同步路径可能运行在 didUpdateWidget 的 build 阶段，搜索同步会写 GetX Rx，需延迟到帧后。
      _mountController(formatted, loadId, deferSearchSync: true);
      return;
    }

    // 大数据进后台 isolate，避免大 body 的字符串拼接阻塞主线程。
    _formattedText = compute(_formatHexIsolate, {'data': data, 'bytesPerRow': widget.bytesPerRow});
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

  // 用已格式化的文本构建并挂载新的 CodeForge/Find 控制器。小数据在 _load 中同步调用，
  // 大数据在 isolate 返回后调用；两者后续流程一致。
  // deferSearchSync：同步挂载可能处于 build 阶段（didUpdateWidget），而搜索同步会写
  // GetX Rx，需延迟到帧后；isolate 回调本就在帧外，无需延迟。
  void _mountController(String formatted, int loadId, {bool deferSearchSync = false}) {
    final newline = formatted.indexOf('\n');
    _lineCharLength = newline >= 0 ? newline + 1 : max(1, formatted.length);

    final controller = CodeForgeController()
      ..readOnly = true
      ..text = formatted;
    // 首帧前先占位，避免挂载当帧的搜索同步走到自带回调；渲染对象构造时会覆盖一次，
    // 因此下面首帧后还要再设置回来。
    controller.setScrollCallback(_scrollToLineWithoutHighlight);
    final findController = FindController(controller)..addListener(_onFindChanged);
    setState(() {
      _controller = controller;
      _findController = findController;
    });
    // CodeForge 的渲染对象在挂载时会绑定自带的滚动回调，需等到首帧之后再覆盖，
    // 否则会被还原。自带回调会在滚动结束后对目标行播放 800ms 整行淡出高亮，
    // 连续查找时旧动画回调会把灰色背景打到过期行上；Hex 视图行高固定，直接按
    // 行号滚动即可，无需整行高亮。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller == controller) {
        controller.setScrollCallback(_scrollToLineWithoutHighlight);
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
    final targetY = line * _hexLineHeight;
    final target = (targetY + _hexLineHeight / 2 - position.viewportDimension / 2).clamp(0.0, position.maxScrollExtent);
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
  // 匹配数很大时（Hex 文档常见上千个匹配）每帧上万次 FFI，导致查找导航明显卡顿。
  // Hex 每行定长，字符偏移到行号是纯 Dart 整除，这里只把可视窗口内的高亮交给渲染层。
  void _applyHighlightWindow({bool force = false}) {
    final controller = _controller;
    if (controller == null || !_vScrollController.hasClients) return;

    if (force) {
      // FindController 刚把全量高亮（或空列表）写回 controller，留存一份再决定是否窗口化。
      final fresh = controller.searchHighlights;
      _allHighlights = fresh;
      _isWindowed = false;
      _appliedWindowFirst = -1;
      _appliedWindowLast = -1;
      // 小匹配量原生路径足够便宜，直接用全量。
      if (fresh.length <= 80) return;
    } else if (!_isWindowed) {
      // 纯滚动且当前不是窗口模式（无搜索或匹配量小），无需处理。
      return;
    }

    final all = _allHighlights;
    if (all.length <= 80) return;

    final position = _vScrollController.position;
    final firstLine = max(0, (position.pixels / _hexLineHeight).floor() - _highlightWindowMargin);
    final lastLine = ((position.pixels + position.viewportDimension) / _hexLineHeight).ceil() + _highlightWindowMargin;

    // 现有窗口仍完整覆盖可视区域（含半程余量）时无需重建，避免滚动动画每帧分配新列表。
    if (!force &&
        _appliedWindowFirst >= 0 &&
        firstLine >= _appliedWindowFirst + _highlightWindowMargin ~/ 2 &&
        lastLine <= _appliedWindowLast - _highlightWindowMargin ~/ 2) {
      return;
    }

    final window = <SearchHighlight>[];
    for (final highlight in all) {
      final line = highlight.start ~/ _lineCharLength;
      if (line >= firstLine && line <= lastLine) {
        window.add(highlight);
      }
    }
    controller.searchHighlights = window;
    controller.searchHighlightsChanged = true;
    _isWindowed = true;
    _appliedWindowFirst = firstLine;
    _appliedWindowLast = lastLine;
  }

  // 搜索控制器的通知统一延迟到帧后再同步，而不是在监听回调里立即处理。
  // showSearchOverlay 是"先写回 pattern、后插入浮层"：写回触发通知时浮层尚未插入，
  // shouldSearch() 仍为 false，立即同步会把搜索误判为停用；浮层插入后又不再有任何事件，
  // 表现为关闭搜索框再打开时不会重新触发。其他视图用 AnimatedBuilder 在下一帧拉取最新
  // 状态所以没这个问题；这里对齐同样的"帧后拉取"模式即可，无需改动共享的搜索控制器。
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

  @override
  Widget build(BuildContext context) {
    final viewportHeight = max(_minViewerHeight, MediaQuery.sizeOf(context).height - _viewerViewportTopOffset);
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
      return SizedBox(height: viewportHeight, child: Center(child: Text('Hex viewer unavailable: $error')));
    }
    if (controller == null) {
      return SizedBox(height: viewportHeight, child: const Center(child: CircularProgressIndicator()));
    }

    // code_forge 的渲染对象在拿到紧高度约束时会把字段高度撑满该约束（performLayout 里
    // contentHeight = max(内容高, constraints.maxHeight)），所以以前固定一屏高会让只有几行的
    // 小 body 也留出大片空白。这里按真实行数算出内容自然高度（非换行、无折叠时渲染层就是
    // lineCount * 行高，见 code_area.dart 的 visibleHeight），内容不足一屏就收缩、超出仍保持
    // 视口高度由内部滚动；下限保留最小可用高度。与横向宽度问题同源，都是被"屏幕级最小尺寸"撑住。
    final contentHeight = controller.lineCount * _hexLineHeight;
    final height = max(_minViewerHeight, min(viewportHeight, contentHeight));

    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      height: height,
      child: NotificationListener<OverscrollNotification>(
        onNotification: _onOverscroll,
        // code_forge 在 lineWrap=false 时把字段最小宽度取成 MediaQuery.size.width（整屏宽，
        // code_area.dart:7140/7274 的 minWidth），而 HexViewer 实际视口因面板/卡片内边距
        // 比整屏窄，内容于是被撑出一段并不存在的横向越界（实测 extent 恰为屏宽与视口宽之差）。
        // 用 LayoutBuilder 取真实视口宽度并覆盖子树 MediaQuery.size，让最小宽度等于实际可用
        // 宽度，消除短内容也能左右滚动的问题；真正超长的 Hex 行仍按自身宽度正常横向滚动。
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
                key: ValueKey<int>(_loadId),
                controller: controller,
                findController: _findController,
                focusNode: _editorFocusNode,
                verticalScrollController: _vScrollController,
                // 覆盖 code_forge 默认的 thickness 15；thumbColor 沿用其默认 decoration 的取色
                // （编辑器文字色 withAlpha(150)），只改宽度不改观感。
                scrollbarDecoration: ScrollbarDecoration(
                  thickness: _scrollbarThickness,
                  minThumbLength: _scrollbarMinThumbLength,
                  thumbColor: theme.colorScheme.onSurface.withValues(alpha: 150 / 255),
                ),
                readOnly: true,
                enableGutter: false,
                enableFolding: false,
                enableGuideLines: false,
                enableLocalSuggestions: false,
                enableKeyboardSuggestions: false,
                lineWrap: false,
                editorTheme: {
                  'root': TextStyle(
                    fontFamily: 'Courier',
                    fontSize: _hexFontSize,
                    color: theme.colorScheme.onSurface,
                    // code_forge 的右键菜单（桌面 Card、移动端工具条）底色直接取 root.backgroundColor，
                    // 原来传透明色导致菜单半透明看不清。宿主卡片本身就是 surface 色（panel.dart），
                    // 渲染层每帧用此色铺编辑器底，换成 surface 视觉无变化，但菜单随之变为不透明，
                    // 与其他视图的选区菜单（同样基于 surface 配色）保持一致。
                    backgroundColor: theme.colorScheme.surface,
                  ),
                },
                textStyle: const TextStyle(fontFamily: 'Courier', fontSize: _hexFontSize),
                selectionStyle: CodeSelectionStyle(
                  selectionColor: theme.colorScheme.primary.withValues(alpha: 0.3),
                  cursorBubbleColor: theme.colorScheme.primary,
                ),
                matchHighlightStyle: MatchHighlightStyle(
                  currentMatchStyle: TextStyle(backgroundColor: theme.colorScheme.primary),
                  otherMatchStyle: TextStyle(backgroundColor: theme.colorScheme.inversePrimary),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
