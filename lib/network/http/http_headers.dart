// ignore_for_file: constant_identifier_names

/*
 * Copyright 2023 Hongen Wang All rights reserved.
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

import 'dart:collection';

class HttpHeaders {
  static const String CONTENT_LENGTH = "Content-Length";
  static const String CONTENT_ENCODING = "Content-Encoding";
  static const String CONTENT_TYPE = "Content-Type";
  static const String HOST = "Host";
  static const String TRANSFER_ENCODING = "Transfer-Encoding";
  static const String Cookie = "Cookie";
  static const String PROXY_AUTHORIZATION = "Proxy-Authorization";

  static const List<String> commonHeaderKeys = [
    'Accept',
    'Accept-Charset',
    'Accept-Encoding',
    'Accept-Language',
    'Accept-Ranges',
    'Authorization',
    'Cache-Control',
    'Connection',
    'Content-Type',
    'Content-Length',
    'Content-Encoding',
    'Cookie',
    'Date',
    'Expect',
    'From',
    'Host',
    'If-Match',
    'If-Modified-Since',
    'If-None-Match',
    'If-Range',
    'If-Unmodified-Since',
    'Max-Forwards',
    'Origin',
    'Pragma',
    'Proxy-Authorization',
    'Range',
    'Referer',
    'TE',
    'Upgrade',
    'User-Agent',
    'Via',
    'Warning',
    'X-Requested-With',
    'DNT',
    'X-Forwarded-For',
    'X-Forwarded-Host',
    'X-Forwarded-Proto',
    'Front-End-Https',
    'X-Http-Method-Override',
    'X-ATT-DeviceId',
    'X-Wap-Profile',
    'Proxy-Connection',
    'X-UIDH',
    'X-Csrf-Token',
    'X-Request-ID',
    'X-Correlation-ID',
    'Save-Data'
  ];

  static const Map<String, List<String>> commonHeaderValues = {
    'Accept': [
      'application/json, text/plain, */*',
      'application/xml, text/xml, */*',
      'text/html, application/xhtml+xml, */*',
      '*/*'
    ],
    'Accept-Charset': ['utf-8, iso-8859-1;q=0.5', 'utf-8'],
    'Accept-Encoding': ['gzip, deflate, br', 'gzip, deflate'],
    'Accept-Language': ['en-US,en;q=0.9', 'zh-CN,zh;q=0.9'],
    'Cache-Control': ['no-cache', 'max-age=0', 'no-store'],
    'Connection': ['keep-alive', 'close'],
    'Content-Type': [
      'application/json',
      'application/x-www-form-urlencoded',
      'multipart/form-data',
      'text/plain',
      'text/html',
      'application/xml'
    ],
    'User-Agent': [
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1',
      'Mozilla/5.0 (Android 11; Mobile; rv:68.0) Gecko/68.0 Firefox/68.0'
    ],
  };

  final LinkedHashMap<String, List<String>> _headers = LinkedHashMap<String, List<String>>();

  // 由小写标头名称键入的原始标头名称。
  final Map<String, String> _originalHeaderNames = {};

  HttpHeaders();

  ///设置header。
  void set(String name, String value) {
    var original = _originalHeaderNames[name.toLowerCase()];
    if (original != null && original != name) {
      _headers.remove(original);
    }

    _headers[name] = [value];
    _originalHeaderNames[name.toLowerCase()] = name;
  }

  ///添加header。
  void add(String name, String value) {
    addValues(name, [value]);
  }

  ///添加header。
  void addValues(String name, List<String> values) {
    var original = _originalHeaderNames[name.toLowerCase()];
    if (original != null && original != name) {
      var old = _headers.remove(original);
      _headers[name] = List.from(old!);
    }
    if (_headers[name] == null) {
      _headers[name] = [];
    }

    _headers[name]?.addAll(values);
    _originalHeaderNames[name.toLowerCase()] = name;
  }

  ///从headers中添加
  addAll(HttpHeaders? headers) {
    headers?.forEach((key, values) {
      for (var val in values) {
        add(key, val);
      }
    });
  }

  String? get(String name) {
    return getList(name)?.first;
  }

  String getOriginalName(String name) {
    return _originalHeaderNames[name.toLowerCase()] ?? name;
  }

  List<String>? getList(String name) {
    var originalHeaderName = _originalHeaderNames[name.toLowerCase()];
    if (originalHeaderName == null) {
      return null;
    }
    return _headers[originalHeaderName];
  }

  bool remove(String name) {
    var originalHeaderName = _originalHeaderNames.remove(name.toLowerCase());
    _headers.remove(originalHeaderName);
    return originalHeaderName != null;
  }

  int? getInt(String name) {
    final value = get(name);
    if (value == null) {
      return null;
    }
    return int.parse(value);
  }

  bool getBool(String name) {
    final value = get(name);
    if (value == null) {
      return false;
    }
    return value.toLowerCase() == "true";
  }

  int get contentLength => getInt(CONTENT_LENGTH) ?? 0;

  set contentLength(int contentLength) => set(CONTENT_LENGTH, contentLength.toString());

  String? get contentEncoding => get(HttpHeaders.CONTENT_ENCODING)?.toLowerCase();

  bool get isGzip => contentEncoding == "gzip";

  bool get isChunked => get(HttpHeaders.TRANSFER_ENCODING)?.toLowerCase().trimLeft() == "chunked";

  List<String> get cookies => getList(Cookie) ?? [];

  void forEach(void Function(String name, List<String> values) f) {
    _headers.forEach(f);
  }

  Iterable<MapEntry<String, List<String>>> get entries => _headers.entries;

  set contentType(String contentType) => set(CONTENT_TYPE, contentType);

  String get contentType => get(CONTENT_TYPE) ?? "";

  String? get host => get(HOST);

  set host(String? host) {
    if (host != null) {
      set(HOST, host);
    }
  }

  //清空
  void clear() {
    _headers.clear();
    _originalHeaderNames.clear();
  }

  String headerLines() {
    StringBuffer sb = StringBuffer();
    forEach((name, values) {
      for (var value in values) {
        sb.writeln("$name: $value");
      }
    });

    return sb.toString();
  }

  ///转换json
  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    forEach((name, values) {
      json[name] = values;
    });
    return json;
  }

  ///转换json
  Map<String, String> toMap() {
    Map<String, String> json = {};
    forEach((name, values) {
      json[name] = values.join(";");
    });
    return json;
  }

  Map<String, List<String>> getHeaders() {
    return _headers;
  }

  ///从json解析
  factory HttpHeaders.fromJson(Map<String, dynamic> json) {
    HttpHeaders headers = HttpHeaders();
    json.forEach((key, values) {
      for (var element in (values as List)) {
        headers.add(key, element.toString());
      }
    });

    return headers;
  }

  ///原始header文本
  String toRawHeaders() {
    StringBuffer sb = StringBuffer();
    forEach((name, values) {
      for (var value in values) {
        sb.writeln("$name: $value");
      }
    });

    return sb.toString();
  }

  @override
  String toString() {
    return 'HttpHeaders{$_headers}';
  }
}
