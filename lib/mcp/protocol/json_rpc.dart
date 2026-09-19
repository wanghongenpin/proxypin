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

/// 最小 JSON-RPC 2.0 类型与错误码（MCP 复用）。
///
/// @author wanghongen
class JsonRpcError {
  // JSON-RPC 标准错误码
  static const int parseError = -32700;
  static const int invalidRequest = -32600;
  static const int methodNotFound = -32601;
  static const int invalidParams = -32602;
  static const int internalError = -32603;

  final int code;
  final String message;
  final dynamic data;

  JsonRpcError(this.code, this.message, {this.data});

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (data != null) 'data': data,
      };
}

class JsonRpcResponse {
  /// 成功响应
  static Map<String, dynamic> result(Object? id, dynamic result) => {
        'jsonrpc': '2.0',
        if (id != null) 'id': id,
        'result': result,
      };

  /// 错误响应
  static Map<String, dynamic> error(Object? id, JsonRpcError error) => {
        'jsonrpc': '2.0',
        if (id != null) 'id': id,
        'error': error.toJson(),
      };
}
