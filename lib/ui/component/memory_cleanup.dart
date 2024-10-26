/*
 * Copyright 2024 hongen Wang All rights reserved.
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

import 'dart:io';

import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/configuration.dart';

/// Memory cleanup handle
/// @author wanghongen

class MemoryCleanupMonitor {
  static bool _processing = false;

  static void onMonitor({Function? onCleanup}) {
    var threshold = AppConfiguration.current?.memoryCleanupThreshold;
    if (threshold == null || threshold <= 0) {
      return;
    }

    if (_processing) return;
    _processing = true;
    Future.delayed(const Duration(seconds: 3), () {
      _processing = false;
      _cleanup(threshold, onCleanup);
    });
  }

  static void _cleanup(int threshold, Function? onCleanup) {
    final memory = ProcessInfo.currentRss / 1024 / 1024;
    logger.d('Memory cleanup, current memory: ${memory.toInt()}M, threshold: ${threshold}M');
    if (memory > threshold) {
      onCleanup?.call();
      logger.i('Memory cleanup, current memory: ${memory.toInt()}M, threshold: ${threshold}M, cleanup');
    }
  }
}
