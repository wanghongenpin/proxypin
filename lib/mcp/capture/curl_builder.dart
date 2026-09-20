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

import 'package:proxypin/mcp/capture/sensitive_data.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/utils/curl.dart';
import 'package:proxypin/utils/python.dart';

/// 导出可运行代码（cURL / JavaScript fetch / Python requests）。
/// 复用全局生成函数，并在需要时对敏感头脱敏。
///
/// @author wanghongen
class CurlBuilder {
  static const supportedLanguages = ['curl', 'fetch', 'python'];

  /// 在副本上替换敏感头，避免污染内存中的原始请求。
  static HttpRequest redactedCopy(HttpRequest request) {
    var copy = request.copy();
    for (var name in SensitiveData.redactedHeaders) {
      if (copy.headers.get(name) != null) {
        copy.headers.set(name, SensitiveData.placeholder);
      }
    }
    return copy;
  }

  static String build(HttpRequest request, {bool redact = true}) => code(request, 'curl', redact: redact);

  /// 生成指定语言代码。[language] 支持 curl / fetch / python，未识别时回退 curl。
  static String code(HttpRequest request, String language, {bool redact = true}) {
    var source = redact ? redactedCopy(request) : request;
    switch (language.toLowerCase()) {
      case 'fetch':
      case 'javascript':
      case 'js':
        return copyAsFetch(source);
      case 'python':
      case 'python-requests':
      case 'requests':
        return copyAsPythonRequests(source);
      case 'curl':
      default:
        return curlRequest(source);
    }
  }

  /// 当前可执行文件绝对路径（供接入命令/JSON 配置使用）
  static String get executable => Platform.resolvedExecutable;
}
