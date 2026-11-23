import 'package:flutter/widgets.dart';

/// 懒保活场景下标记当前可见内容查看器的作用域。
///
/// HttpBody 的各类型 tab 切换后，访问过的查看器会以 Offstage 方式留在树上（保留选区、
/// 滚动和搜索状态）。隐藏的查看器仍会收到共享 SearchTextController 的通知并重建，
/// 若它们照常回写匹配数，搜索栏的计数会被不可见的查看器覆盖。
/// 查看器通过 [ActiveViewerScope.isActive] 判断自己是否可见，仅在可见时回写计数、
/// 执行查找导航；作用域之外（其它页面复用这些查看器时）默认为可见，行为不变。
class ActiveViewerScope extends InheritedWidget {
  final bool active;

  const ActiveViewerScope({super.key, required this.active, required super.child});

  /// 当前 context 所在查看器是否为活动（可见）查看器。无此作用域时默认 true。
  static bool isActive(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ActiveViewerScope>();
    return scope?.active ?? true;
  }

  @override
  bool updateShouldNotify(ActiveViewerScope oldWidget) => active != oldWidget.active;
}
