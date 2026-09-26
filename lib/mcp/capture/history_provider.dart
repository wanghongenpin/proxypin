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

import 'package:proxypin/network/http/http.dart';

/// 历史会话元数据（不携带报文内容）。
class HistoryMeta {
  /// 会话 id，即历史存储中的索引；用于各 MCP 工具的 history_id 参数
  final int id;
  final String name;
  final int requestCount;
  final int? fileSize;
  final int createTimeMs;

  HistoryMeta({
    required this.id,
    required this.name,
    required this.requestCount,
    this.fileSize,
    required this.createTimeMs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'requestCount': requestCount,
        'fileSize': fileSize,
        'createTime': createTimeMs,
      };
}

/// 历史抓包数据源。
///
/// 抽象层让 mcp 核心（[FlowStore] 等）不直接依赖历史存储及其平台插件，
/// 由编排层桥接 `HistoryStorage` 实现；测试可注入内存实现。
/// 全部异步以兼容历史存储的懒初始化。会话以 [HistoryMeta.id]（稳定 id，
/// 不随列表增删改变）标识，[requests] 每次返回的列表由调用方做有界缓存，
/// 实现方不应长期持有报文。
abstract class HistoryProvider {
  /// 全部历史会话元数据
  Future<List<HistoryMeta>> list();

  /// 按稳定 id 读取某会话的请求；id 不存在时抛 [ArgumentError]。
  Future<List<HttpRequest>> requests(int id);
}
