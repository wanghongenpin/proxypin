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

///重放任务列表
class ReplayTasksPage extends StatefulWidget {
  const ReplayTasksPage({super.key});

  @override
  State<StatefulWidget> createState() => _ReplayTasksPageState();
}

class _ReplayTasksPageState extends State<ReplayTasksPage> {
  final manager = ReplayTaskManager.instance;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.replayTasks),
        actions: [
          if (manager.hasFinished)
            TextButton(
                onPressed: manager.clearFinished,
                child: Text(localizations.clearFinished)),
        ],
      ),
      body: AnimatedBuilder(
          animation: manager,
          builder: (context, _) {
            if (manager.tasks.isEmpty) {
              return Center(child: Text(localizations.emptyData));
            }
            return ListView(children: manager.tasks.source.map(_card).toList());
          }),
    );
  }

  Widget _card(ReplayTask task) {
    return AnimatedBuilder(
        animation: task,
        builder: (context, _) {
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(task.request.method.name,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.75),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(task.request.requestUrl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13))),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      _statusText(task),
                      const SizedBox(width: 12),
                      Text("${task.executedCount}/${task.totalCount}",
                          style: const TextStyle(fontSize: 12)),
                      if (task.isActive && task.nextRunAt != null) ...[
                        const SizedBox(width: 12),
                        Text(_formatTime(task.nextRunAt!),
                            style: const TextStyle(fontSize: 12)),
                      ],
                      const Expanded(child: SizedBox()),
                      if (task.isActive) ...[
                        if (task.status == ReplayTaskStatus.paused)
                          TextButton.icon(
                              style: TextButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: const Size(0, 32)),
                              onPressed: () => manager.resume(task),
                              icon: const Icon(Icons.play_arrow_outlined,
                                  size: 18),
                              label: Text(localizations.resume))
                        else
                          TextButton.icon(
                              style: TextButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: const Size(0, 32)),
                              onPressed: () => manager.pause(task),
                              icon: const Icon(Icons.pause_circle_outline,
                                  size: 18),
                              label: Text(localizations.pause)),
                        TextButton.icon(
                            style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                minimumSize: const Size(0, 32)),
                            onPressed: () => manager.cancel(task),
                            icon: const Icon(Icons.cancel_outlined, size: 16),
                            label: Text(localizations.cancel)),
                      ] else
                        IconButton(
                            iconSize: 20,
                            tooltip: localizations.delete,
                            onPressed: () => manager.remove(task),
                            icon: const Icon(Icons.delete_outline)),
                    ]),
                  ]),
            ),
          );
        });
  }

  Widget _statusText(ReplayTask task) {
    final (label, color) = switch (task.status) {
      ReplayTaskStatus.waiting => (localizations.statusWaiting, Colors.grey),
      ReplayTaskStatus.running => (localizations.statusRunning, Colors.blue),
      ReplayTaskStatus.paused => (localizations.statusPaused, Colors.orange),
      ReplayTaskStatus.completed => (localizations.done, Colors.green),
      ReplayTaskStatus.cancelled => (localizations.statusCancelled, Colors.red),
    };
    return Text(label, style: TextStyle(fontSize: 12, color: color));
  }

  String _formatTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return "${two(time.hour)}:${two(time.minute)}:${two(time.second)}";
  }
}
