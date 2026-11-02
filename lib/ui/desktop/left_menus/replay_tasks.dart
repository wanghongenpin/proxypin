/*
 * Copyright 2023 Hongen Wang All rights reserved.
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
import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/replay_task.dart';

import '../../../utils/flutter_compat.dart';

///显示重放任务对话框
Future<void> showReplayTasksDialog(BuildContext context) {
  return showDialog(
      context: context, builder: (_) => const ReplayTasksDialog());
}

///重放任务列表
class ReplayTasksDialog extends StatefulWidget {
  const ReplayTasksDialog({super.key});

  @override
  State<StatefulWidget> createState() => _ReplayTasksDialogState();
}

class _ReplayTasksDialogState extends State<ReplayTasksDialog> {
  final manager = ReplayTaskManager.instance;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 580,
        height: 520,
        child: Column(children: [
          //标题栏
          Padding(
              padding:
                  const EdgeInsets.only(left: 16, right: 8, top: 8, bottom: 8),
              child: Row(children: [
                Text(localizations.replayTasks,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
                const Expanded(child: SizedBox()),
                if (manager.hasFinished)
                  TextButton(
                      onPressed: manager.clearFinished,
                      child: Text(localizations.clearFinished)),
                IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20)),
              ])),
          const Divider(height: 1, thickness: 0.5),
          Expanded(
            child: AnimatedBuilder(
                animation: manager,
                builder: (context, _) {
                  if (manager.tasks.isEmpty) {
                    return Center(
                        child: Text(localizations.emptyData,
                            style: Theme.of(context).textTheme.bodyMedium));
                  }
                  return ListView(
                      children: manager.tasks.source.map(_tile).toList());
                }),
          ),
        ]),
      ),
    );
  }

  Widget _tile(ReplayTask task) {
    return AnimatedBuilder(
        animation: task,
        builder: (context, _) {
          final color =
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.65);
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -2),
            leading: Text(task.request.method.name,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w500)),
            title: Text(task.request.requestUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
            subtitle: Row(children: [
              _statusChip(task),
              const SizedBox(width: 10),
              Text("${task.executedCount}/${task.totalCount}",
                  style: const TextStyle(fontSize: 11)),
              if (task.isActive && task.nextRunAt != null) ...[
                const SizedBox(width: 10),
                Text(_formatTime(task.nextRunAt!),
                    style: const TextStyle(fontSize: 11)),
              ],
            ]),
            trailing: task.isActive
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    if (task.status == ReplayTaskStatus.paused)
                      IconButton(
                          iconSize: 18,
                          tooltip: localizations.resume,
                          onPressed: () => manager.resume(task),
                          icon: const Icon(Icons.play_arrow_outlined))
                    else
                      IconButton(
                          iconSize: 18,
                          tooltip: localizations.pause,
                          onPressed: () => manager.pause(task),
                          icon: const Icon(Icons.pause_circle_outline)),
                    IconButton(
                        iconSize: 18,
                        tooltip: localizations.cancel,
                        onPressed: () => manager.cancel(task),
                        icon: const Icon(Icons.cancel_outlined)),
                  ])
                : IconButton(
                    iconSize: 18,
                    tooltip: localizations.delete,
                    onPressed: () => manager.remove(task),
                    icon: const Icon(Icons.delete_outline)),
          );
        });
  }

  Widget _statusChip(ReplayTask task) {
    final (label, color) = switch (task.status) {
      ReplayTaskStatus.waiting => (localizations.statusWaiting, Colors.grey),
      ReplayTaskStatus.running => (localizations.statusRunning, Colors.blue),
      ReplayTaskStatus.paused => (localizations.statusPaused, Colors.orange),
      ReplayTaskStatus.completed => (localizations.done, Colors.green),
      ReplayTaskStatus.cancelled => (localizations.statusCancelled, Colors.red),
    };
    return Text(label, style: TextStyle(fontSize: 11, color: color));
  }

  String _formatTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return "${two(time.hour)}:${two(time.minute)}:${two(time.second)}";
  }
}
