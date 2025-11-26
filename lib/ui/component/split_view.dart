import 'package:flutter/material.dart';

class VerticalSplitView extends StatefulWidget {
  final Widget left;
  final Widget right;
  final double ratio;
  final double minRatio;
  final double maxRatio;
  final Function(double ratio)? onRatioChanged;

  const VerticalSplitView(
      {super.key,
      required this.left,
      required this.right,
      this.ratio = 0.5,
      this.minRatio = 0,
      this.maxRatio = 1,
      this.onRatioChanged})
      : assert(ratio >= 0 && ratio <= 1);

  @override
  State<VerticalSplitView> createState() => _VerticalSplitViewState();
}

class _VerticalSplitViewState extends State<VerticalSplitView> {
  final _dividerWidth = 10.0;

  //from 0-1
  late double _ratio;
  double _maxWidth = double.infinity;

  double get _width1 => _ratio * _maxWidth;

  double get _width2 => (1 - _ratio) * _maxWidth;

  @override
  void initState() {
    super.initState();
    _ratio = widget.ratio;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, BoxConstraints constraints) {
      if (_maxWidth != constraints.maxWidth) {
        _maxWidth = constraints.maxWidth - _dividerWidth;
      }

      return SizedBox(
        width: constraints.maxWidth,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: _width1 - 5,
              child: widget.left,
            ),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: SizedBox(
                    width: _dividerWidth,
                    height: double.infinity,
                    child: (_ratio <= 0 || _ratio >= 1)
                        ? const Icon(Icons.drag_handle, size: 16)
                        : const VerticalDivider(thickness: 1),
                  )),
              onPanEnd: (DragEndDetails details) {
                widget.onRatioChanged?.call(_ratio);
              },
              onPanUpdate: (DragUpdateDetails details) {
                setState(() {
                  _ratio += details.delta.dx / _maxWidth;

                  if (_ratio > widget.maxRatio) {
                    _ratio = widget.maxRatio;
                  } else if (_ratio < widget.minRatio) {
                    _ratio = widget.minRatio;
                  }
                });
              },
            ),
            SizedBox(
              width: _width2,
              child: widget.right,
            ),
          ],
        ),
      );
    });
  }
}
