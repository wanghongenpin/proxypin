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

import 'dart:convert';

import 'package:proxypin/network/components/manager/environment_manager.dart';
import 'package:proxypin/utils/multipart.dart';

/// application/x-www-form-urlencoded body 的构建器与解析器。
///
/// 字段模型复用 [FormBody]（与 multipart 表单编辑器共用），
/// 区别仅在于编码：键值做 percent-encode 后用 `&`、`=` 连接。
///
/// @author wanghongen
class FormUrl {
  /// 构建 x-www-form-urlencoded 二进制 body。
  /// [render] 用于渲染字段值中的环境变量占位符（如 {{name}}），
  /// 默认走 [EnvironmentManager.tryRender]。
  static List<int> buildBytes(FormBody form, {String Function(String)? render}) {
    final valueRender = render ?? (String s) => EnvironmentManager.tryRender(s) ?? s;
    final pairs = <String>[];
    for (final part in form.parts.where((p) => p.enabled && p.name.isNotEmpty)) {
      pairs.add('${Uri.encodeQueryComponent(part.name)}='
          '${Uri.encodeQueryComponent(valueRender(part.value))}');
    }
    return utf8.encode(pairs.join('&'));
  }

  /// 解析 x-www-form-urlencoded body 为 [FormBody]
  static FormBody parse(List<int> body) {
    final form = FormBody();
    final text = utf8.decode(body, allowMalformed: true);
    if (text.isEmpty) return form;

    for (final pair in text.split('&')) {
      if (pair.isEmpty) continue;
      final idx = pair.indexOf('=');
      final key = idx == -1 ? pair : pair.substring(0, idx);
      final value = idx == -1 ? '' : pair.substring(idx + 1);
      form.parts.add(FormPart(
        name: Uri.decodeQueryComponent(key),
        value: Uri.decodeQueryComponent(value),
      ));
    }
    return form;
  }
}
