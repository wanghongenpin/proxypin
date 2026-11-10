import 'dart:io';

import 'package:flutter/material.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

/// 给无边框窗口补上「拖动边缘/角落改变大小」的能力。
///
/// 主窗口在 Linux/Windows 上是 `TitleBarStyle.hidden`（无系统边框），
/// 于是窗口管理器不再提供边缘 resize 热区；这里在四条边和四个角放一圈
/// 透明的拖拽热区，按下即调用 `windowManager.startResizing(edge)`，
/// 交给窗口管理器完成实际缩放（Wayland/X11 都支持）。
class WindowResizeBorder extends StatelessWidget {
  /// 热区宽度；太宽会挡住右侧滚动条，4px 是经验值
  static const double thickness = 4;

  final Widget child;

  const WindowResizeBorder({super.key, required this.child, this.thicknessOverride});

  final double? thicknessOverride;

  double get _t => thicknessOverride ?? thickness;

  @override
  Widget build(BuildContext context) {
    if (!Platforms.isDesktop()) {
      return child;
    }

    final t = _t;
    return Stack(children: [
      child,
      _zone(edge: ResizeEdge.top, left: t, right: t, top: 0, height: t),
      _zone(edge: ResizeEdge.bottom, left: t, right: t, bottom: 0, height: t),
      _zone(edge: ResizeEdge.left, top: t, bottom: t, left: 0, width: t),
      _zone(edge: ResizeEdge.right, top: t, bottom: t, right: 0, width: t),
      _zone(edge: ResizeEdge.topLeft, top: 0, left: 0, width: t * 2, height: t * 2),
      _zone(edge: ResizeEdge.topRight, top: 0, right: 0, width: t * 2, height: t * 2),
      _zone(edge: ResizeEdge.bottomLeft, bottom: 0, left: 0, width: t * 2, height: t * 2),
      _zone(edge: ResizeEdge.bottomRight, bottom: 0, right: 0, width: t * 2, height: t * 2),
    ]);
  }

  Widget _zone({
    required ResizeEdge edge,
    double? top,
    double? bottom,
    double? left,
    double? right,
    double? width,
    double? height,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      width: width,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // 光标形状随热区变化，方便用户发现可以拉边
        child: MouseRegion(
          cursor: _cursor(edge),
          child: const SizedBox.expand(),
        ),
        onPanStart: (_) {
          if (!Platform.isLinux && !Platform.isWindows) {
            return;
          }
          windowManager.startResizing(edge);
        },
      ),
    );
  }

  MouseCursor _cursor(ResizeEdge edge) {
    switch (edge) {
      case ResizeEdge.top:
      case ResizeEdge.bottom:
        return SystemMouseCursors.resizeUpDown;
      case ResizeEdge.left:
      case ResizeEdge.right:
        return SystemMouseCursors.resizeLeftRight;
      case ResizeEdge.topLeft:
      case ResizeEdge.bottomRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case ResizeEdge.topRight:
      case ResizeEdge.bottomLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
    }
  }
}
