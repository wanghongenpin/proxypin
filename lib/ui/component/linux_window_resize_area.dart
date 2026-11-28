import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

class LinuxWindowResizeArea extends StatefulWidget {
  const LinuxWindowResizeArea({super.key, required this.child});

  final Widget child;

  @override
  State<LinuxWindowResizeArea> createState() => _LinuxWindowResizeAreaState();
}

class _LinuxWindowResizeAreaState extends State<LinuxWindowResizeArea> with WindowListener {
  bool _maximized = false;
  bool _fullScreen = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  void onWindowEnterFullScreen() => setState(() => _fullScreen = true);

  @override
  void onWindowLeaveFullScreen() => setState(() => _fullScreen = false);

  @override
  Widget build(BuildContext context) {
    return DragToResizeArea(
      resizeEdgeSize: 4,
      enableResizeEdges: _maximized || _fullScreen ? const [] : null,
      child: widget.child,
    );
  }
}
