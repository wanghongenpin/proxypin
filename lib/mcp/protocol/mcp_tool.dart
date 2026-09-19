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

/// 一个 MCP 工具的描述与处理器。
///
/// @author wanghongen
class McpTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  /// 处理一次 tools/call，入参为 arguments（可能为空），返回结构化结果（会以 JSON 文本返回）。
  final Future<dynamic> Function(Map<String, dynamic> args) handler;

  /// 所属作用域：minimal 表示默认精简集即包含
  final String scope;

  McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
    this.scope = 'minimal',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'inputSchema': inputSchema,
      };
}
