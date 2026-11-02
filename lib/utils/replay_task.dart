/*
 * Copyright 2023 Hongen Wang
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

import 'package:flutter/foundation.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/utils/listenable_list.dart';

/// 重放任务状态
enum ReplayTaskStatus { waiting, running, paused, completed, cancelled }

/// 高级重放配置
class ReplayTaskConfig {
  /// 总次数
  final int count;

  /// 首次延时(毫秒,含指定时刻换算后的延时)
  final int initialDelay;

  /// 是否固定间隔
  final bool fixed;

  /// 固定间隔(毫秒)
  final int interval;

  /// 随机最小间隔(毫秒)
  final int minInterval;

  /// 随机最大间隔(毫秒)
  final int maxInterval;

  ReplayTaskConfig(
      {required this.count,
      required this.initialDelay,
      required this.fixed,
      required this.interval,
      required this.minInterval,
      required this.maxInterval});
}

/// 一个可查看、可取消的重放任务。
///
/// 用可取消的 [Timer] 驱动,取代高级重放里无法干预的 `Future.delayed` 递归。
class ReplayTask extends ChangeNotifier {
  static int _idCounter = 0;

  final String id;

  /// 展示用请求快照
  final HttpRequest request;

  /// 每次 tick 实际执行的发包动作
  final void Function() action;

  final int totalCount;
  final int initialDelay;
  final bool fixed;
  final int interval;
  final int minInterval;
  final int maxInterval;

  final DateTime createdAt;

  int executedCount = 0;
  ReplayTaskStatus status = ReplayTaskStatus.waiting;
  DateTime? nextRunAt;

  Timer? _timer;

  /// 当前这一跳的总时长与起始时刻,用于暂停时计算剩余时间
  int _currentDelayMs = 0;
  DateTime _scheduledAt = DateTime.now();

  /// 任务进入终态(已完成/已取消)时触发,不随每次 tick 触发
  void Function()? onFinished;

  ReplayTask({
    required this.request,
    required this.action,
    required ReplayTaskConfig config,
  })  : id = 'replay-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}',
        totalCount = config.count,
        initialDelay = config.initialDelay,
        fixed = config.fixed,
        interval = config.interval,
        minInterval = config.minInterval,
        maxInterval = config.maxInterval,
        createdAt = DateTime.now();

  /// 剩余次数
  int get remaining => totalCount - executedCount;

  bool get isActive =>
      status == ReplayTaskStatus.waiting ||
      status == ReplayTaskStatus.running ||
      status == ReplayTaskStatus.paused;

  /// 启动任务
  void start() {
    status = ReplayTaskStatus.waiting;
    _schedule(initialDelay);
  }

  void _schedule(int delayMs) {
    if (status == ReplayTaskStatus.completed || status == ReplayTaskStatus.cancelled) return;
    _currentDelayMs = delayMs;
    _scheduledAt = DateTime.now();
    nextRunAt = _scheduledAt.add(Duration(milliseconds: delayMs));
    _timer = Timer(Duration(milliseconds: delayMs), _tick);
    notifyListeners();
  }

  /// 暂停,保留当前这一跳的剩余时间
  void pause() {
    if (status != ReplayTaskStatus.waiting && status != ReplayTaskStatus.running) return;
    _timer?.cancel();
    _timer = null;
    status = ReplayTaskStatus.paused;
    nextRunAt = null;
    notifyListeners();
  }

  /// 继续,按暂停时这一跳的剩余时间重排
  void resume() {
    if (status != ReplayTaskStatus.paused) return;
    final elapsed = DateTime.now().difference(_scheduledAt).inMilliseconds;
    final remainingMs = (_currentDelayMs - elapsed).clamp(0, _currentDelayMs);
    status = ReplayTaskStatus.waiting;
    _schedule(remainingMs);
  }

  void _tick() {
    if (!isActive) return;

    status = ReplayTaskStatus.running;
    action();
    executedCount++;

    if (executedCount >= totalCount) {
      status = ReplayTaskStatus.completed;
      nextRunAt = null;
      notifyListeners();
      onFinished?.call();
      return;
    }

    status = ReplayTaskStatus.waiting;
    _schedule(_nextInterval());
  }

  /// 计算下次间隔,随机区间做了边界保护,min==max 时不抛异常。
  int _nextInterval() {
    if (fixed) {
      return interval;
    }
    final span = maxInterval - minInterval;
    if (span <= 0) {
      return minInterval;
    }
    return minInterval + Random().nextInt(span);
  }

  /// 取消任务,已调度但未发送的请求不再发出
  void cancel() {
    if (!isActive) return;
    _timer?.cancel();
    _timer = null;
    status = ReplayTaskStatus.cancelled;
    nextRunAt = null;
    notifyListeners();
    onFinished?.call();
  }
}

/// 重放任务管理器,纯内存(本次运行期间保留)。
class ReplayTaskManager extends ChangeNotifier {
  static final ReplayTaskManager instance = ReplayTaskManager._();

  ReplayTaskManager._() {
    tasks.addListener(OnchangeListEvent<ReplayTask>(notifyListeners));
  }

  final ListenableList<ReplayTask> tasks = ListenableList();

  /// 进行中/等待中的任务数
  int get activeCount => tasks.where((t) => t.isActive).length;

  /// 是否存在已结束(完成/取消)的任务
  bool get hasFinished => tasks.any((t) => !t.isActive);

  /// 创建并启动一个重放任务
  ReplayTask start({required HttpRequest request, required void Function() action, required ReplayTaskConfig config}) {
    final snapshot = request.copy(uri: request.requestUrl);
    final task = ReplayTask(request: snapshot, action: action, config: config);
    task.onFinished = notifyListeners;
    tasks.add(task);
    task.start();
    return task;
  }

  void pause(ReplayTask task) => task.pause();

  void resume(ReplayTask task) => task.resume();

  void cancel(ReplayTask task) => task.cancel();

  /// 删除任务(若仍在执行先取消)
  void remove(ReplayTask task) {
    task.onFinished = null;
    task.cancel();
    tasks.remove(task);
    task.dispose();
  }

  /// 清除已完成/已取消的任务
  void clearFinished() {
    final finished = tasks.where((t) => !t.isActive).toList();
    for (final task in finished) {
      task.onFinished = null;
      tasks.remove(task);
      task.dispose();
    }
  }
}
