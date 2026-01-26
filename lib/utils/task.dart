import 'dart:async';

/// 延时任务工具类
class DelayedTask {
  // 私有构造函数，实现单例
  DelayedTask._internal();

  static final DelayedTask _instance = DelayedTask._internal();

  factory DelayedTask() => _instance;

  // 维护一个任务池，支持同时管理多个不同的延时任务
  final Map<String, Timer> _taskPool = {};

  /// 执行防抖任务 (Debounce)
  /// 如果在 [duration] 时间内再次调用相同 [tag] 的任务，前一个任务会被自动取消
  void debounce(
    String tag,
    Duration duration,
    void Function() action,
  ) {
    // 1. 如果旧任务还在运行，直接取消
    _taskPool[tag]?.cancel();

    // 2. 开启新任务
    _taskPool[tag] = Timer(duration, () {
      action();
      _taskPool.remove(tag); // 执行完毕后移除
    });
  }

  /// 延迟 [duration] 后执行一次，返回可手动取消的 Timer
  /// 适用于不需要防抖，但需要精准手动控制取消的场景
  Timer delay(Duration duration, void Function() action) {
    return Timer(duration, action);
  }

  /// 取消特定标签的任务
  void cancel(String tag) {
    if (_taskPool.containsKey(tag)) {
      _taskPool[tag]?.cancel();
      _taskPool.remove(tag);
    }
  }

  /// 取消所有正在运行的任务 (通常在 dispose 时调用)
  void cancelAll() {
    _taskPool.forEach((tag, timer) => timer.cancel());
    _taskPool.clear();
  }
}
