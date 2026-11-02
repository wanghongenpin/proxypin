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
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/desktop/request/list.dart';
import 'package:proxypin/ui/launch/launch.dart';
import 'package:proxypin/utils/listenable_list.dart';

/// 桌面端底部状态栏（设计稿 .statusbar）：代理地址 / 请求数 / 过滤数 / 上下行速率 / 版本
class DesktopStatusBar extends StatefulWidget {
  final ProxyServer proxyServer;
  final ListenableList<HttpRequest> container;
  final GlobalKey<DesktopRequestListState> requestListStateKey;

  const DesktopStatusBar(
      {super.key, required this.proxyServer, required this.container, required this.requestListStateKey});

  @override
  State<DesktopStatusBar> createState() => _DesktopStatusBarState();
}

class _DesktopStatusBarState extends State<DesktopStatusBar> {
  Timer? _timer;
  late final _ListListener _listListener = _ListListener(onChanged: _refresh);
  int _lastUpBytes = 0;
  int _lastDownBytes = 0;
  int _upRate = 0;
  int _downRate = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    widget.container.addListener(_listListener);
    SocketLaunch.startStatus.addListener(_refresh);
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.container.removeListener(_listListener);
    SocketLaunch.startStatus.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  /// 每秒统计一次上下行速率（按列表内请求/响应包大小的增量近似）
  void _tick() {
    int up = 0, down = 0;
    for (var request in widget.container) {
      up += request.packageSize ?? 0;
      down += request.response?.packageSize ?? 0;
    }
    var upRate = _lastUpBytes == 0 ? 0 : (up - _lastUpBytes).clamp(0, 1 << 62);
    var downRate = _lastDownBytes == 0 ? 0 : (down - _lastDownBytes).clamp(0, 1 << 62);
    _lastUpBytes = up;
    _lastDownBytes = down;
    if (upRate != _upRate || downRate != _downRate) {
      _upRate = upRate;
      _downRate = downRate;
      _refresh();
    }
  }

  String _formatRate(int bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '$bytesPerSecond B/s';
    }
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s';
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    var theme = Theme.of(context);
    var running = SocketLaunch.startStatus.value.get() == true;
    var total = widget.container.length;
    var filtered = 0;
    var view = widget.requestListStateKey.currentState?.currentView();
    if (view != null && view.length < total) {
      filtered = total - view.length;
    }

    var style = TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant);
    return Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: chromeBorderColor(theme), width: 1))),
        child: Row(children: [
          Icon(Icons.circle, size: 7, color: running ? okColor(theme) : theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text('${localizations.proxy} 127.0.0.1:${widget.proxyServer.port}', style: style),
          const SizedBox(width: 14),
          Text('${localizations.request} $total', style: style),
          if (filtered > 0) ...[
            const SizedBox(width: 14),
            Text('${localizations.filtered} $filtered', style: style),
          ],
          const Spacer(),
          Text('↓ ${_formatRate(_downRate)}', style: style),
          const SizedBox(width: 12),
          Text('↑ ${_formatRate(_upRate)}', style: style),
          const SizedBox(width: 12),
          Text('v${AppConfiguration.version}', style: style),
        ]));
  }
}

/// 列表增删时刷新状态栏（计数与过滤数）
class _ListListener extends ListenerListEvent<HttpRequest> {
  final VoidCallback onChanged;

  _ListListener({required this.onChanged});

  @override
  void onAdd(HttpRequest item) => onChanged();

  @override
  void onRemove(HttpRequest item) => onChanged();

  @override
  void onBatchRemove(List<HttpRequest> items) => onChanged();

  @override
  void clear(List<HttpRequest> items) => onChanged();
}
