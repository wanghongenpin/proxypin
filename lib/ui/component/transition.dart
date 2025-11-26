import 'package:flutter/material.dart';

///颜色过渡动画
class ColorTransition extends StatefulWidget {
  final Color begin;
  final Color end;
  final Duration duration;
  final Widget child;
  final bool startAnimation;

  const ColorTransition(
      {super.key,
      required this.begin,
      this.end = Colors.transparent,
      this.duration = const Duration(milliseconds: 1000),
      required this.child,
      this.startAnimation = true});

  @override
  State<ColorTransition> createState() {
    return ColorTransitionState();
  }
}

class ColorTransitionState extends State<ColorTransition> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation _animation;

  @override
  void initState() {
    super.initState();

    //创建动画控制器
    _animationController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    //添加动画执行刷新监听
    _animationController.addListener(() {
      setState(() {});
    });

    //颜色动画变化
    _animation = ColorTween(begin: widget.begin, end: widget.end).animate(_animationController);

    if (widget.startAnimation) {
      //延迟150毫秒执行动画
      Future.delayed(const Duration(milliseconds: 150), () {
        _animationController.forward();
      });
    } else {
      _animationController.value = _animationController.upperBound;
    }
  }

  void show() {
    _animationController.reset();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _animation.value,
      child: widget.child,
    );
  }
}
