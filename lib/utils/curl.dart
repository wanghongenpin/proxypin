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
import 'package:proxypin/utils/lang.dart';

///复制cURL请求
String curlRequest(HttpRequest request) {
  List<String> headers = [];
  request.headers.forEach((key, values) {
    for (var val in values) {
      headers.add("  -H '$key: $val' ");
    }
  });

  String body = '';
  if (request.bodyAsString.isNotEmpty) {
    body = "  --data '${request.bodyAsString}' \\\n";
  }
  return "curl -X ${request.method.name} '${request.requestUrl}' \\\n"
      "${headers.join('\\\n')} \\\n $body  --compressed";
}

main() {
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

  static HttpRequest parse(String curlCommand) {
    HttpMethod method = HttpMethod.get;
    HttpHeaders headers = HttpHeaders();

    String? url;
    String? data;

    // 去除 "curl" 关键字并去除首尾空格
    String trimmedCommand = curlCommand.replaceFirst('curl', '').trim();

    List<String> parts = [];
    String currentPart = '';
    bool inQuotes = false;
    bool inBody = false;

    // 处理可能包含引号的参数
    for (int i = 0; i < trimmedCommand.length; i++) {
      String char = trimmedCommand[i];
      if (char == '"' || char == "'") {
        if (inBody) {
          currentPart += char;
          continue;
        }

        // 如果当前字符是引号，切换 inQuotes 状态
        inQuotes = !inQuotes;
      } else if (char == ' ' && !inQuotes) {
        if (inBody && currentPart.length > 2) {
          // 如果当前部分是数据，去掉前后的引号
          currentPart = currentPart.substring(1, currentPart.length - 1);
        }

        if (currentPart == '-d' || currentPart == '--data' || currentPart == '--data-raw') {
          inBody = true;
        } else {
          inBody = false;
        }

        parts.add(currentPart);
        currentPart = '';
      } else {
        currentPart += char;
      }
    }

    if (currentPart.isNotEmpty) {
      if (inBody && currentPart.length > 2) {
        // 如果当前部分是数据，去掉前后的引号
        currentPart = currentPart.substring(1, currentPart.length - 1);
      }

      parts.add(currentPart);
    }

    String protocolVersion = "HTTP/1.1";

    // 遍历参数列表进行解析
    for (int i = 0; i < parts.length; i++) {
      String part = parts[i];
      if (part == _x || part == _request) {
        // 解析请求方法
        if (i + 1 < parts.length) {
          method = HttpMethod.valueOf(parts[++i]);
        }
      } else if (part == _h || part == _header) {
        // 解析请求头
        if (i + 1 < parts.length) {
          String headerStr = parts[++i];
          List<String> headerParts = headerStr.splitFirst(':'.codeUnits.first);
          if (headerParts.length == 2) {
            headers.add(headerParts[0], headerParts[1]);
          }
        }
      } else if (part == _d || part == _dataRaw || part == _data) {
        // 解析请求数据
        if (i + 1 < parts.length) {
          data = parts[++i];
        }
      } else if (!part.startsWith('-') && part.startsWith("http")) {
        // 解析请求 URL
        url = part;
      } else if ("--http2" == part) {
        // protocolVersion = "HTTP2";
      }
    }

    if (data?.isNotEmpty == true && method == HttpMethod.get) {
      method = HttpMethod.post;
    }

    HttpRequest request = HttpRequest(method, url ?? '', protocolVersion: protocolVersion);
    request.headers.addAll(headers);
    request.body = data?.codeUnits;
    return request;
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
