/*
 * Copyright 2026 Hongen Wang All rights reserved.
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

/// MCP 监听策略。桌面端始终只监听回环地址；移动端可选仅本机或局域网访问。
class McpListenOptions {
  static const String loopbackAddress = '127.0.0.1';
  static const String anyAddress = '0.0.0.0';

  final InternetAddress address;
  final bool requiresBearerToken;

  McpListenOptions._(this.address, this.requiresBearerToken);

  factory McpListenOptions.resolve({required bool isMobile, Object? configuredAddress}) {
    if (!isMobile) return McpListenOptions._(InternetAddress.loopbackIPv4, false);

    return McpListenOptions._(
      normalizeAddress(configuredAddress) == loopbackAddress ? InternetAddress.loopbackIPv4 : InternetAddress.anyIPv4,
      true,
    );
  }

  /// 旧配置和非法值保持原有局域网监听行为。
  static String normalizeAddress(Object? configuredAddress) {
    return configuredAddress == loopbackAddress ? loopbackAddress : anyAddress;
  }
}
