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

/// AI 客户端中注册的 MCP server 名称。桌面端（stdio）与手机端（LAN HTTP）
/// 使用不同名称并存、互不覆盖，agent 据此区分两组工具命名空间。
///
/// 下划线命名：Codex 的 config.toml 裸键不支持连字符。
///
/// @author wanghongen
class McpClientNames {
  McpClientNames._();

  /// 桌面 App：stdio，本机拉起
  static const String desktop = 'proxypin_desktop';

  /// 手机 App：局域网 Streamable HTTP + Bearer token
  static const String mobile = 'proxypin_mobile';

  /// 旧版本使用的名称，配置迁移时清理
  static const String legacy = 'proxypin';
}
