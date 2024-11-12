/*
 * Copyright 2024 Hongen Wang All rights reserved.
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
import 'package:proxypin/utils/lang.dart';

///重写规则
///@author: wanghongen
enum RuleType {
  // body("重写消息体"), //OLD VERSION

  requestReplace("替换请求"),
  responseReplace("替换响应"),
  requestUpdate("修改请求"),
  responseUpdate("修改响应"),
  redirect("重定向");

  //名称
  final String label;

  const RuleType(this.label);

  static RuleType fromName(String name) {
    return values.firstWhere((element) => element.name == name || element.label == name);
  }
}

class RequestRewriteRule {
  bool enabled;
  RuleType type;

  String? name;
  String url;
  RegExp _urlReg;
  String? rewritePath;

  RequestRewriteRule({this.enabled = true, this.name, required this.url, required this.type, this.rewritePath})
      : _urlReg = RegExp(url.replaceAll("*", ".*").replaceAll('?', '\\?'));

  bool match(String url, {RuleType? type}) {
    if (enabled && (type == null || this.type == type)) {
      return _urlReg.hasMatch(url);
    }
    return false;
  }

  bool matchUrl(String url, RuleType type) {
    return this.type == type && _urlReg.hasMatch(url);
  }

  /// 从json中创建
  factory RequestRewriteRule.formJson(Map<dynamic, dynamic> map) {
    return RequestRewriteRule(
        enabled: map['enabled'] == true,
        name: map['name'],
        url: map['url'] ?? map['domain'] + map['path'],
        type: RuleType.fromName(map['type']),
        rewritePath: map['rewritePath']);
  }

  void updatePathReg() {
    _urlReg = RegExp(url.replaceAll("*", ".*"));
  }

  toJson() {
    return {
      'name': name,
      'enabled': enabled,
      'url': url,
      'type': type.name,
      'rewritePath': rewritePath,
    };
  }
}

enum ReplaceBodyType {
  text("文本"),
  file("文件");

  final String label;

  const ReplaceBodyType(this.label);
}

class RewriteItem {
  bool enabled;
  RewriteType type;

  //key redirectUrl, method, path, queryParam, headers, body, statusCode
  final Map<String, dynamic> values = {};

  RewriteItem(this.type, this.enabled, {Map<dynamic, dynamic>? values}) {
    if (values != null) {
      this.values.addAll(Map.from(values));
    }
  }

  factory RewriteItem.fromJson(Map<dynamic, dynamic> map) {
    return RewriteItem(RewriteType.fromName(map['type']), map['enabled'], values: map['values']);
  }

  static List<RewriteItem> fromRequest(HttpRequest request) {
    List<RewriteItem> items = [];
    items.add(RewriteItem(RewriteType.replaceRequestLine, false)..path = request.requestUri?.path);
    items.add(RewriteItem(RewriteType.replaceRequestHeader, false)..headers = request.headers.toMap());
    items.add(RewriteItem(RewriteType.replaceRequestBody, true)..body = request.getBodyString());

    return items;
  }

  static List<RewriteItem> fromResponse(HttpResponse response) {
    List<RewriteItem> items = [];
    items.add(RewriteItem(RewriteType.replaceResponseStatus, false)..statusCode = response.status.code);
    items.add(RewriteItem(RewriteType.replaceResponseHeader, false)..headers = response.headers.toMap());
    items.add(RewriteItem(RewriteType.replaceResponseBody, true)..body = response.getBodyString());

    return items;
  }

  //key
  String? get key => values['key'];

  set key(String? key) => values['key'] = key;

  String? get value => values['value'];

  set value(String? value) => values['value'] = value;

  //redirectUrl
  String? get redirectUrl => values['redirectUrl'];

  set redirectUrl(String? redirectUrl) => values['redirectUrl'] = redirectUrl;

  //method
  HttpMethod? get method => values['method'] == null
      ? null
      : HttpMethod.values.firstWhereOrNull((element) => element.name == values['method']);

  set method(HttpMethod? method) => values['method'] = method?.name;

  String? get path => values['path'];

  set path(String? path) => values['path'] = path;

  //queryParam
  String? get queryParam => values['queryParam'];

  set queryParam(String? queryParam) => values['queryParam'] = queryParam;

  //statusCode
  int? get statusCode => values['statusCode'];

  set statusCode(int? statusCode) => values['statusCode'] = statusCode;

  //headers
  Map<String, String>? get headers => values['headers'] == null ? null : Map.from(values['headers']);

  set headers(Map<String, String>? headers) => values['headers'] = headers;

  //body
  String? get body => values['body'];

  set body(String? body) => values['body'] = body;

  String? get bodyType => values['bodyType'];

  set bodyType(String? bodyType) => values['bodyType'] = bodyType;

  String? get bodyFile => values['bodyFile'];

  set bodyFile(String? bodyFile) => values['bodyFile'] = bodyFile;

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'type': type.name,
      'values': values,
    };
  }

  @override
  String toString() {
    return toJson().toString();
  }
}

enum RewriteType {
  //重定向
  redirect("重定向"),

  //替换请求
  replaceRequestLine("请求行"),
  replaceRequestHeader("请求头"),
  replaceRequestBody("请求体"),
  replaceResponseStatus("状态码"),
  replaceResponseHeader("响应头"),
  replaceResponseBody("响应体"),

  //修改请求
  updateBody("修改Body"),
  addQueryParam("添加参数"),
  removeQueryParam("删除参数"),
  updateQueryParam("修改参数"),
  addHeader("添加头部"),
  removeHeader("删除头部"),
  updateHeader("修改头部"),
  ;

  static List<RewriteType> updateRequest = [
    updateBody,
    addQueryParam,
    updateQueryParam,
    removeQueryParam,
    addHeader,
    updateHeader,
    removeHeader
  ];

  static List<RewriteType> updateResponse = [updateBody, addHeader, updateHeader, removeHeader];

  final String label;

  const RewriteType(this.label);

  static RewriteType fromName(String name) {
    return values.firstWhere((element) => element.name == name);
  }

  String getDescribe(bool isCN) {
    if (isCN) {
      return label;
    }

    return name.replaceFirst("replace", "").replaceFirst("Query", "");
  }
}
