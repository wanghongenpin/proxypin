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

const String _h = "-H";
const String _header = "--header";
const String _x = "-X";
const String _request = "--request";
const String _data = "--data";
const String _dataRaw = "--data-raw";
const String _d = "-d";

///解析curl
HttpRequest parseCurl(String curl) {
  var lines = curl.trim().split('\n');

  HttpMethod method = HttpMethod.get;
  HttpHeaders headers = HttpHeaders();
  String requestUrl = '';
  String body = '';

  bool parseBody = false;

  for (var it in lines) {
    it = it.trim();
    if (it.endsWith("\\")) {
      it = it.substring(0, it.length - 1);
    }

    //header
    if (it.startsWith(_h) || it.startsWith(_header)) {
      int index = it.startsWith(_h) ? _h.length : _header.length;
      var line = it.substring(index).trim();
      line = line.startsWith("'") ? line.substring(1) : line;
      var endIdx = endIndex(line);

      it = line.substring(endIdx + 1);
      line = line.substring(0, endIdx == -1 ? line.length : endIdx);
      var pair = _split(line, ":");
      if (pair != null) {
        headers.add(pair.key, pair.value);
      }

      if (endIdx == -1) {
        continue;
      }
      it = it.trim();
    }

    if (it.startsWith(_data) || it.startsWith(_d)) {
      //body
      String value;
      if (it.startsWith(_dataRaw)) {
        value = it.substring(_dataRaw.length).trim();
      } else if (it.startsWith(_data)) {
        value = it.substring(_data.length).trim();
      } else {
        value = it.substring(_d.length).trim();
      }
      value = value.startsWith('\$') || value.startsWith("'") ? value.substring(1) : value;

      int index = endIndex(value);
      if (index > 0) {
        body += value.substring(0, index);
      } else {
        parseBody = true;
        body += value;
      }
    } else if (parseBody) {
      int index = endIndex(it);
      if (index >= 0) {
        parseBody = false;
        body += "\n${it.substring(0, index)}";
      } else {
        body += "\n$it";
      }
    } else if (it.startsWith(_x) || it.startsWith(_request)) {
      //method
      int index = it.startsWith(_x) ? _x.length : _request.length;
      var value = it.substring(index).trim();
      method = HttpMethod.valueOf(Strings.trimWrap(value, "'"));
    } else if (it.trim().startsWith("'http") || it.startsWith('curl') && it.contains("'http")) {
      var index = it.indexOf("'");
      var value = it.substring(index + 1).trim();
      if (value.endsWith("'")) {
        value = value.substring(0, value.length - 1);
      }
      try {
        requestUrl = Uri.decodeFull(value);
      } catch (e) {
        requestUrl = value;
      }
    }
  }

  if (body.isNotEmpty && method == HttpMethod.get) {
    method = HttpMethod.post;
  }
  HttpRequest request = HttpRequest(method, requestUrl);
  request.headers.addAll(headers);
  request.body = body.codeUnits;

  return request;
}

Pair<String, String>? _split(String line, String code) {
  try {
    var index = line.codeUnits.indexOf(code.codeUnits.first);
    var key = line.substring(0, index).trim();
    var value = line.substring(index + 1).trim();
    return Pair(key, value);
  } catch (e) {
    return null;
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
