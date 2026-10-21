import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowsToolbar extends StatefulWidget {
  final Widget? title;

  const WindowsToolbar({
    super.key,
    this.title,
  });

  @override
  State<WindowsToolbar> createState() => _WindowsToolbarState();
}

class _WindowsToolbarState extends State<WindowsToolbar> with WindowListener {
  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 7),
        Padding(
            padding: EdgeInsets.only(top: 2),
            child: Center(
                child: Image.asset(
              'assets/icon_foreground.png',
              width: 32,
            ))),
        // title 内部含 Spacer（flex 子节点），必须给有界宽度，否则整个 title 布局失败不渲染；
        // 用 Expanded 让它占满标题栏剩余宽度，并整体作为窗口拖动区域（按钮点击不受影响）
        Expanded(child: _ToolbarDragArea(child: widget.title ?? const SizedBox())),
        WindowCaptionButton.minimize(
            brightness: Theme.brightnessOf(context),
            onPressed: () async {
              bool isMinimized = await windowManager.isMinimized();
              if (isMinimized) {
                windowManager.restore();
              } else {
                windowManager.minimize();
              }
            }),
        FutureBuilder<bool>(
            future: windowManager.isMaximized(),
            builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
              if (snapshot.data == true) {
                return WindowCaptionButton.unmaximize(
                  brightness: Theme.brightnessOf(context),
                  onPressed: () {
                    windowManager.unmaximize();
                  },
                );
              }
              return WindowCaptionButton.maximize(
                brightness: Theme.brightnessOf(context),
                onPressed: () {
                  windowManager.maximize();
                },
              );
            }),
        WindowCaptionButton.close(
            brightness: Theme.brightnessOf(context),
            onPressed: () {
              windowManager.close();
            }),
      ],
    );
  }

  @override
  void onWindowMaximize() {
    setState(() {});
  }

  @override
  void onWindowUnmaximize() {
    setState(() {});
  }
}

/// 窗口拖动区域，替代 window_manager 的 DragToMoveArea：
/// DragToMoveArea 自带的 onDoubleTap 手势会在整个区域生效，双击工具栏图标也会误触最大化，
/// 且其双击手势会让子按钮的单击多出约 300ms 等待。
/// 这里拖动照旧；双击改为手动检测：命中路径的最深目标是拖动区自身时（空白区域、图标缝隙，
/// 空白处没有子节点认领命中）才切换最大化，落在按钮等子控件上则忽略。
class _ToolbarDragArea extends StatefulWidget {
  final Widget child;

  const _ToolbarDragArea({required this.child});

  @override
  State<_ToolbarDragArea> createState() => _ToolbarDragAreaState();
}

class _ToolbarDragAreaState extends State<_ToolbarDragArea> {
  final GlobalKey _childKey = GlobalKey();
  Offset _lastTapPos = Offset.zero;
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch && event.buttons != kPrimaryMouseButton) return;
    final now = DateTime.now();
    final isDoubleTap = now.difference(_lastTapTime) <= const Duration(milliseconds: 300) &&
        (event.position - _lastTapPos).distance <= kDoubleTapSlop;
    _lastTapTime = now;
    _lastTapPos = event.position;
    if (isDoubleTap && _hitBlank(event.position)) {
      _toggleMaximize();
    }
  }

  /// 双击是否落在空白区域（工具栏空白、图标缝隙）：
  /// 从命中路径最深目标沿 render 树向上爬，先遇到 child 子树根说明落在按钮等内容上；
  /// 先遇到拖动区自身的根 render（空白处没有子节点认领命中，最深目标是拖动区自己的层）才算空白
  bool _hitBlank(Offset position) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, position, View.of(context).viewId);
    if (result.path.isEmpty) return false;
    final target = result.path.first.target;
    if (target is! RenderObject) return false; // TextSpan 等内容节点
    final childRoot = _childKey.currentContext?.findRenderObject();
    final selfRoot = context.findRenderObject();
    RenderObject? node = target;
    while (node != null) {
      if (node == childRoot) return false;
      if (node == selfRoot) return true;
      node = node.parent;
    }
    return false;
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      windowManager.unmaximize();
    } else {
      windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listener 必须 translucent：空白处没有子节点认领命中，默认 deferToChild 会让
    // Listener 被排除在命中路径之外，空白区域永远收不到 pointer down
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => windowManager.startDragging(),
        child: KeyedSubtree(key: _childKey, child: widget.child),
      ),
    );
  }
}
