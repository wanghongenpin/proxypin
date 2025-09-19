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
        widget.title ?? SizedBox(),
        Expanded(child: DragToMoveArea(child: Container())),
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
