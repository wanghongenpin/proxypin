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

import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:window_manager/window_manager.dart';

/// 监听窗口变化
class WindowChangeListener extends WindowListener {
  final AppConfiguration appConfiguration;

  WindowChangeListener(this.appConfiguration);

  @override
  void onWindowResized() async {
    final windowSize = await windowManager.getSize();
    logger.d("windowSize: $windowSize");
    appConfiguration.windowSize = windowSize;
    appConfiguration.flushConfig();
  }

  @override
  void onWindowMoved() async {
    final windowPosition = await windowManager.getPosition();
    // logger.d("windowPosition: $windowPosition");
    appConfiguration.windowPosition = windowPosition;
    appConfiguration.flushConfig();
  }
}
