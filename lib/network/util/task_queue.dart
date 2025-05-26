import 'dart:async';
import 'dart:collection';

class SequentialTaskQueue {
  final Queue<_Task> _tasks = Queue();
  bool _isProcessing = false;
  bool _isCancelled = false;
  Completer<void>? _completer;

  final Set<int> completedTasks = {};

  final Map<int, List<_Task>> dependencyTasks = {};

  /// Adds a task to the queue with a priority (e.g., streamId).
  void add(int id, int? dependency, Future Function() task,
      {void Function(dynamic error, StackTrace stackTrace)? onError}) {
    if (_isCancelled) return;

    _tasks.addLast(_Task(id, task, dependency: dependency, onError: onError));

    // Sort tasks by priority (e.g., streamId).
    // _tasks.sort((a, b) => a.key.compareTo(b.key));

    runAllTask();
  }

  runAllTask() async {
    if (!_isProcessing) {
      _isProcessing = true;
      _completer ??= Completer<void>();
      while (_tasks.isNotEmpty) {
        final currentTask = _tasks.removeFirst();
        await runTask(currentTask);
      }
      _isProcessing = false;
      _completer?.complete();
      _completer = null;
    }
  }

  Future<void> runTask(_Task task) async {
    if (_isCancelled) return;

    if (task.dependency != null && task.dependency! > 0 && !completedTasks.contains(task.dependency)) {
      dependencyTasks[task.dependency!] ??= [];
      dependencyTasks[task.dependency]!.add(task);
    } else {
      try {
        await task.task();
      } catch (error, stackTrace) {
        task.onError?.call(error, stackTrace);
      } finally {
        completedTasks.add(task.id);
      }

      if (dependencyTasks[task.id] != null) {
        for (var dependencyTask in dependencyTasks[task.id]!) {
          await runTask(dependencyTask);
        }
        dependencyTasks.remove(task.id);
      }
    }
  }

  Future<void> waitForAll() async {
    if (_isProcessing) {
      _completer ??= Completer<void>();
      return _completer?.future;
    }
    return;
  }

  void cancel() {
    _isCancelled = true;
    _tasks.clear();
  }

  void reset() {
    _isCancelled = false;
    _tasks.clear();
  }
}

class _Task {
  final int id;
  final int? dependency;
  final Future Function() task;
  final Function(dynamic error, StackTrace stackTrace)? onError;

  _Task(this.id, this.task, {this.dependency, this.onError});
}
