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

import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'dart:convert';

/// 复制为 fetch 请求
String copyAsFetch(HttpRequest request) {
  final headers = request.headers.entries.where((entry) => entry.key.toLowerCase() != 'content-length').toList();

  final sb = StringBuffer();
  sb.writeln('fetch(${jsonEncode(request.requestUrl)}, {');
  sb.writeln('  method: ${jsonEncode(request.method.name.toUpperCase())},');

  if (headers.isNotEmpty) {
    sb.writeln('  headers: {');
    for (final entry in headers) {
      sb.writeln('    ${jsonEncode(entry.key)}: ${jsonEncode(entry.value)},');
    }
    sb.writeln('  },');
  }

  if (request.bodyAsString.isNotEmpty) {
    sb.writeln('  body: ${jsonEncode(request.bodyAsString)},');
  }

  sb.writeln('});');
  return sb.toString();
}

///复制cURL请求
String curlRequest(HttpRequest request) {
  String contentType = request.headers.contentType;
  bool isMultipart = contentType.toLowerCase().contains('multipart/form-data');

  // 先尝试构造 multipart -F 列表；成功才丢弃 Content-Type，让 curl 自动生成。
  // 失败（body 为空/无法解析）时保留原 Content-Type，避免生成损坏的 curl。
  String? multipartBody = isMultipart ? _buildMultipartFormData(request) : null;
  bool dropContentType = multipartBody != null;

  List<String> headers = [];
  request.headers.forEach((key, values) {
    String lowerKey = key.toLowerCase();
    // 跳过 content-length（curl 会自动计算）
    if (lowerKey == 'content-length') return;
    // multipart 成功转成 -F 时才跳过 content-type
    if (dropContentType && lowerKey == 'content-type') return;
    // 跳过 accept-encoding 中的 br（curl 不支持 brotli）
    if (lowerKey == 'accept-encoding') {
      for (var val in values) {
        String filtered =
            val.split(',').map((e) => e.trim()).where((e) => !e.toLowerCase().startsWith('br')).join(', ');
        if (filtered.isNotEmpty) {
          headers.add("  -H '$key: $filtered' ");
        }
      }
      return;
    }

    for (var val in values) {
      headers.add("  -H '$key: $val' ");
    }
  });

  String body = '';
  if (multipartBody != null) {
    body = multipartBody;
  } else if (isMultipart) {
    // multipart 但 body 缺失（如大文件流式未缓存）：给个占位符提示
    body = "  --data-binary '@<PATH_TO_FILE>' \\\n";
  } else if (request.bodyAsString.isNotEmpty) {
    body = "  --data '${request.bodyAsString}' \\\n";
  }

  return "curl -X ${request.method.name} '${request.requestUrl}' \\\n"
      "${headers.join('\\\n')} \\\n $body  --compressed";
}

/// 解析 multipart body 为 curl 的 -F 参数列表；解析失败返回 null。
String? _buildMultipartFormData(HttpRequest request) {
  String? boundary = _extractBoundary(request.headers.contentType);
  String bodyStr = request.bodyAsString;
  if (boundary == null || bodyStr.isEmpty) return null;

  final headerBodySplit = RegExp(r'\r?\n\r?\n');
  // 只去掉两侧换行，保留 header/body 之间的空行
  final trimNewlines = RegExp(r'^(\r?\n)+|(\r?\n)+$');
  final List<String> formFields = [];

  for (String part in bodyStr.split('--$boundary')) {
    part = part.replaceAll(trimNewlines, '');
    if (part.isEmpty || part == '--') continue;

    final sections = part.split(headerBodySplit);
    if (sections.length < 2) {
      // 没有 body 的 part（如空文件字段）：仍尝试从纯 header 里解析出 filename/name
      final name = _extractDispositionParam(part, 'name');
      final filename = _extractDispositionParam(part, 'filename');
      if (name != null && filename != null) {
        formFields.add('  -F "${_fixMojibake(name)}=@${_fixMojibake(filename)}" ');
      }
      continue;
    }

    final headerSection = sections[0];
    // rejoin 剩余段以防 body 里也有空行；再去掉结尾的 \r\n
    final valueSection = sections.sublist(1).join('\r\n\r\n').replaceAll(RegExp(r'\r?\n$'), '');

    final name = _extractDispositionParam(headerSection, 'name');
    if (name == null) continue;

    final filename = _extractDispositionParam(headerSection, 'filename');
    if (filename != null) {
      formFields.add('  -F "${_fixMojibake(name)}=@${_fixMojibake(filename)}" ');
    } else {
      final escaped = _fixMojibake(valueSection).replaceAll("'", "'\\''");
      formFields.add("  -F '${_fixMojibake(name)}=$escaped' ");
    }
  }

  if (formFields.isEmpty) return null;
  return "${formFields.join('\\\n')} \\\n";
}

/// bodyAsString 在 utf8.decode 失败时会走 String.fromCharCodes 逐字节转 char，
/// 若原始字节是 UTF-8 会得到 Latin-1 乱码。这里把 code units 当字节再 UTF-8 解一次。
String _fixMojibake(String s) {
  bool needsFix = false;
  for (int i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c > 0xFF) return s; // 已是正常 Unicode，无需修复
    if (c >= 0x80) needsFix = true;
  }
  if (!needsFix) return s;
  try {
    return utf8.decode(s.codeUnits);
  } catch (_) {
    return s;
  }
}

String? _extractBoundary(String contentType) {
  // multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW
  // 也兼容带引号: boundary="xxx"
  RegExp regExp = RegExp(r'boundary=(?:"([^"]+)"|([^\s;]+))', caseSensitive: false);
  Match? match = regExp.firstMatch(contentType);
  return match?.group(1) ?? match?.group(2);
}

String? _extractDispositionParam(String header, String paramName) {
  // Content-Disposition: form-data; name="field1"; filename="test.pdf"
  // 加前导边界(行首/空白/分号)，避免 name 匹配到 filename 的子串
  RegExp regExp = RegExp('(?:^|[;\\s])$paramName="([^"]*)"', caseSensitive: false);
  Match? match = regExp.firstMatch(header);
  if (match != null) return match.group(1);

  // 也处理无引号的情况: name=field1
  regExp = RegExp('(?:^|[;\\s])$paramName=([^\\s;]+)', caseSensitive: false);
  match = regExp.firstMatch(header);
  return match?.group(1);
}

void main() {
  print(Curl.parse(
      "curl -X POST 'https://example.com/api' -H 'Content-Type: application/json' -d '{\"key\":\"value\"}'"));
}

class Curl {
  static const String _h = "-H";
  static const String _header = "--header";
  static const String _x = "-X";
  static const String _request = "--request";
  static const String _data = "--data";
  static const String _dataRaw = "--data-raw";
  static const String _d = "-d";

  /// 这些选项会带一个值，但当前不实现其功能；
  /// 仅消费掉其值，避免被误当成 URL。
  static const List<String> _ignoredValueOptions = [
    // 长选项
    '--max-time', '--connect-timeout', '--retry', '--limit-rate', '--interface',
    '--local-port', '--resolve', '--dns-ipv4-addr', '--dns-ipv6-addr',
    '--doh-url', '--cacert', '--cert', '--key', '--ciphers', '--proxy',
    '--proxy-user', '--unix-socket', '--output',
    '--upload-file', '--range', '--time-cond', '--form-string', '--form',
    '--etag-save', '--etag-compare', '--aws-sigv4', '--netrc-file',
    '--request-target',
    // 短选项
    '-m', '-y', '-F', '-T', '-o', '-r', '-z', '-x', '-C', '-K',
  ];

  static HttpRequest parse(String curlCommand) {
    HttpMethod method = HttpMethod.get;
    HttpHeaders headers = HttpHeaders();

    String? url;
    final List<String> dataList = [];
    // -G/--get：数据拼到 URL query，而不是作为 body，方法保持 GET
    bool httpGet = false;
    // 是否通过 -X/--request 或 -I 显式指定了方法
    bool methodExplicit = false;

    List<String> parts = _tokenize(curlCommand);
    if (parts.isNotEmpty && parts.first.toLowerCase() == 'curl') {
      parts.removeAt(0);
    }

    String protocolVersion = "HTTP/1.1";

    int i = 0;

    // 读取选项的值，支持 "-X POST"、"-XPOST"、"--request POST"、"--request=POST" 四种写法
    String? optionValue(String token, List<String> longNames, List<String> shortNames) {
      for (final name in longNames) {
        if (token == name) return i + 1 < parts.length ? parts[++i] : null;
        if (token.startsWith('$name=')) return token.substring(name.length + 1);
      }
      for (final name in shortNames) {
        if (token == name) return i + 1 < parts.length ? parts[++i] : null;
        if (token.startsWith(name) && token.length > name.length) return token.substring(name.length);
      }
      return null;
    }

    // 遍历参数列表进行解析
    while (i < parts.length) {
      String part = parts[i];
      String? value;

      if ((value = optionValue(part, const [_request], const [_x])) != null) {
        method = HttpMethod.valueOf(value!);
        methodExplicit = true;
      } else if ((value = optionValue(part, const [_header], const [_h])) != null) {
        _addHeader(headers, value!);
      } else if ((value = optionValue(
          part, const [_data, _dataRaw, '--data-binary', '--data-ascii', '--data-urlencode'], const [_d])) != null) {
        dataList.add(value!);
      } else if ((value = optionValue(part, const ['--user'], const ['-u'])) != null) {
        // basic 认证
        final credential = base64Encode(utf8.encode(value!));
        headers.add('Authorization', 'Basic $credential');
      } else if ((value = optionValue(part, const ['--cookie'], const ['-b'])) != null) {
        headers.add(HttpHeaders.Cookie, value!);
      } else if ((value = optionValue(part, const ['--referer'], const ['-e'])) != null) {
        headers.add('Referer', value!);
      } else if ((value = optionValue(part, const ['--user-agent'], const ['-A'])) != null) {
        headers.add('User-Agent', value!);
      } else if ((value = optionValue(part, const ['--url'], const [])) != null) {
        url = value;
      } else if ((value = optionValue(part, const ['--json'], const [])) != null) {
        // --json：body 用 JSON，并设置 JSON 的 Content-Type / Accept
        dataList.add(value!);
        headers.add('Content-Type', 'application/json');
        headers.add('Accept', 'application/json');
      } else if (part == '-I' || part == '--head') {
        method = HttpMethod.head;
        methodExplicit = true;
      } else if (part == '-G' || part == '--get') {
        httpGet = true;
      } else if (part == '-0' || part == '--http1.0') {
        protocolVersion = "HTTP/1.0";
      } else if (part == '--http1.1') {
        protocolVersion = "HTTP/1.1";
      } else if (part == '--http2') {
        protocolVersion = "HTTP/2";
      } else if (_isIgnoredValueOption(part)) {
        // 识别但不实现的带值选项：消费掉其值，避免漏成 URL
        if (!_optionHasInlineValue(part) && i + 1 < parts.length) {
          i++;
        }
      } else if (part.startsWith('-')) {
        // 其它无值选项（-L/--location、--compressed、-k/--insecure、-s、-v 等）忽略
      } else if (url == null) {
        // 位置参数视为 URL
        url = part;
      }
      i++;
    }

    String? data = dataList.isEmpty ? null : dataList.join('&');
    bool hasData = data?.isNotEmpty == true;

    if (hasData) {
      if (httpGet) {
        // -G：数据拼到 query 串，方法保持（默认 GET，若 -X 显式指定则遵从 -X）
        url = _appendQuery(url ?? '', data!);
        data = null;
        hasData = false;
      } else if (!methodExplicit && method == HttpMethod.get) {
        // 无 -G、未显式指定方法却带 body：curl 默认转 POST
        method = HttpMethod.post;
      }
    }

    HttpRequest request = HttpRequest(method, url ?? '', protocolVersion: protocolVersion);
    request.headers.addAll(headers);
    request.body = data?.codeUnits;
    return request;
  }

  /// 把查询参数追加到 URL，自动判断用 '?' 还是 '&'
  static String _appendQuery(String url, String query) {
    if (query.isEmpty) return url;
    final sep = url.contains('?') ? (url.endsWith('?') || url.endsWith('&') ? '' : '&') : '?';
    return '$url$sep$query';
  }

  /// 判断 part 是否为「识别但不实现」的带值选项（含 --opt=v、-mv 连写形式）
  static bool _isIgnoredValueOption(String part) {
    final eq = part.indexOf('=');
    final name = eq >= 0 ? part.substring(0, eq) : part;
    if (_ignoredValueOptions.contains(name)) return true;
    // 短选项连写，如 -m30
    if (!name.startsWith('--') && name.length > 2) {
      return _ignoredValueOptions.contains(name.substring(0, 2));
    }
    return false;
  }

  /// 值是否已内联在 token 中（--opt=v 或短选项 -mv）；否则值是下一个独立 token
  static bool _optionHasInlineValue(String part) {
    if (part.contains('=')) return true;
    return !part.startsWith('--') && part.length > 2;
  }

  /// 解析单个 header 字符串 "Name: value"，自动去除 value 前导空白
  static void _addHeader(HttpHeaders headers, String headerStr) {
    int idx = headerStr.indexOf(':');
    if (idx <= 0) return;
    String name = headerStr.substring(0, idx).trim();
    String value = headerStr.substring(idx + 1).trim();
    headers.add(name, value);
  }

  /// 类 shell 分词：正确处理反斜杠续行、单/双引号、转义字符
  static List<String> _tokenize(String command) {
    // 去除行尾反斜杠续行 "\" + 换行
    final input = command.replaceAll(RegExp(r'\\\r?\n'), ' ');

    final List<String> tokens = [];
    final StringBuffer current = StringBuffer();
    bool hasToken = false;
    // 0=无引号 1=单引号 2=双引号
    int quote = 0;

    void finishToken() {
      if (hasToken) {
        tokens.add(current.toString());
        current.clear();
        hasToken = false;
      }
    }

    for (int i = 0; i < input.length; i++) {
      final char = input[i];

      if (quote == 1) {
        // 单引号内全部字面
        if (char == "'") {
          quote = 0;
        } else {
          current.write(char);
          hasToken = true;
        }
        continue;
      }

      if (quote == 2) {
        // 双引号内，仅 $ ` " \ 换行 可被反斜杠转义
        if (char == '"') {
          quote = 0;
        } else if (char == r'\' && i + 1 < input.length) {
          final next = input[i + 1];
          if (next == r'$' || next == '`' || next == '"' || next == r'\' || next == '\n' || next == '\r') {
            current.write(next);
            i++;
          } else {
            current.write(char);
          }
          hasToken = true;
        } else {
          current.write(char);
          hasToken = true;
        }
        continue;
      }

      // 无引号
      if (char == "'") {
        quote = 1;
        hasToken = true;
      } else if (char == '"') {
        quote = 2;
        hasToken = true;
      } else if (char == r'\' && i + 1 < input.length) {
        current.write(input[++i]);
        hasToken = true;
      } else if (char == ' ' || char == '\t' || char == '\n' || char == '\r') {
        finishToken();
      } else {
        current.write(char);
        hasToken = true;
      }
    }
    finishToken();
    return tokens;
  }
}

//判断是否结束
int endIndex(String str) {
  for (int i = 0; i < str.length; i++) {
    if (str[i] == '\'') {
      if (i == 0 || str[i - 1] != '\\') {
        return i;
      }
    }
  }
  return -1;
}
