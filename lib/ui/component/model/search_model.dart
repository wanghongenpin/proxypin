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
import 'package:get/get.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/network/http/http.dart';

/// @author wanghongen
/// 2023/8/4
class SearchModel {
  String? keyword;

  //是否区分大小写
  RxBool caseSensitive = RxBool(false);

  //搜索范围
  Set<Option> searchOptions = {Option.url};

  //请求方法
  HttpMethod? requestMethod;

  //请求类型
  ContentType? requestContentType;

  //响应类型
  ContentType? responseContentType;

  // 状态码范围（包含两端）
  int? statusCodeFrom;
  int? statusCodeTo;

  // 耗时范围，单位毫秒（包含两端）
  int? durationFromMs;
  int? durationToMs;

  // 协议过滤，可选：HTTP (any), WS, HTTP1, H2. 如果为空则不过滤
  Set<Protocol> protocols = {};

  SearchModel([this.keyword]);

  bool get isNotEmpty {
    return keyword?.trim().isNotEmpty == true ||
        requestMethod != null ||
        requestContentType != null ||
        responseContentType != null ||
        statusCodeFrom != null ||
        statusCodeTo != null ||
        durationFromMs != null ||
        durationToMs != null ||
        protocols.isNotEmpty;
  }

  bool get isEmpty {
    return !isNotEmpty;
  }

  ///复制对象
  SearchModel clone() {
    var searchModel = SearchModel(keyword);
    searchModel.searchOptions = Set.from(searchOptions);
    searchModel.requestMethod = requestMethod;
    searchModel.requestContentType = requestContentType;
    searchModel.responseContentType = responseContentType;
    searchModel.statusCodeFrom = statusCodeFrom;
    searchModel.statusCodeTo = statusCodeTo;
    searchModel.durationFromMs = durationFromMs;
    searchModel.durationToMs = durationToMs;
    searchModel.protocols = Set.from(protocols);
    searchModel.caseSensitive = RxBool(caseSensitive.value);
    return searchModel;
  }

  @override
  String toString() {
    return 'SearchModel{keyword: $keyword, searchOptions: $searchOptions, responseContentType: $responseContentType, requestMethod: $requestMethod, requestContentType: $requestContentType, statusRange: [$statusCodeFrom-$statusCodeTo], durationRangeMs: [$durationFromMs-$durationToMs], protocols: $protocols}';
  }

  ///是否匹配
  bool filter(HttpRequest request, HttpResponse? response) {
    if (isEmpty) {
      return true;
    }

    if (requestMethod != null && requestMethod != request.method) {
      return false;
    }
    if (requestContentType != null && request.contentType != requestContentType) {
      return false;
    }

    if (responseContentType != null && response?.contentType != responseContentType) {
      return false;
    }

    // status range
    if ((statusCodeFrom != null || statusCodeTo != null) && response != null) {
      var code = response.status.code;
      if (statusCodeFrom != null && code < statusCodeFrom!) {
        return false;
      }
      if (statusCodeTo != null && code > statusCodeTo!) {
        return false;
      }
    }

    // duration range
    if ((durationFromMs != null || durationToMs != null) && response != null) {
      var cost = response.responseTime.difference(request.requestTime).inMilliseconds;
      if (durationFromMs != null && cost < durationFromMs!) {
        return false;
      }
      if (durationToMs != null && cost > durationToMs!) {
        return false;
      }
    }

    // protocol filters
    if (protocols.isNotEmpty) {
      bool matched = false;
      for (var p in protocols) {
        if (_matchProtocol(p, request, response)) {
          matched = true;
          break;
        }
      }
      if (!matched) {
        return false;
      }
    }

    if (keyword == null || keyword?.isEmpty == true || searchOptions.isEmpty) {
      return true;
    }

    for (var option in searchOptions) {
      if (keywordFilter(keyword!, caseSensitive.value, option, request, response)) {
        return true;
      }
    }

    return false;
  }

  bool _matchProtocol(Protocol p, HttpRequest request, HttpResponse? response) {
    switch (p) {
      case Protocol.https:
        return request.hostAndPort?.scheme == 'https://';
      case Protocol.http:
        return request.requestUrl.startsWith('http://');
      case Protocol.ws:
        return request.isWebSocket || (response != null && response.isWebSocket == true);
      case Protocol.http1:
        return request.protocolVersion == 'HTTP/1.1';
      case Protocol.h2:
        return request.protocolVersion == 'HTTP/2' || request.protocolVersion == 'h2';
    }
  }

  ///关键字过滤
  bool keywordFilter(String keyword, bool caseSensitive, Option option, HttpRequest request, HttpResponse? response) {
    if (option == Option.url) {
      if (caseSensitive) {
        return request.requestUrl.contains(keyword);
      }
      return request.requestUrl.toLowerCase().contains(keyword.toLowerCase());
    }

    if (option == Option.method) {
      return caseSensitive
          ? request.method.name.contains(keyword)
          : request.method.name.toLowerCase().contains(keyword.toLowerCase());
    }
    if (option == Option.responseContentType && response?.headers.contentType.contains(keyword) == true) {
      return true;
    }

    if (option == Option.requestBody && request.bodyAsString.contains(keyword) == true) {
      return true;
    }
    if (option == Option.responseBody && response?.bodyAsString.contains(keyword) == true) {
      return true;
    }

    if (option == Option.requestHeader || option == Option.responseHeader) {
      var entries = option == Option.requestHeader ? request.headers.entries : response?.headers.entries ?? [];

      for (var entry in entries) {
        if (caseSensitive) {
          if (entry.key.contains(keyword) || entry.value.any((element) => element.contains(keyword))) {
            return true;
          }
        } else {
          if (entry.key.toLowerCase() == keyword.toLowerCase() ||
              entry.value.any((element) => element.toLowerCase().contains(keyword.toLowerCase()))) {
            return true;
          }
        }
      }
    }
    return false;
  }
}

enum Option {
  url,
  method,
  responseContentType,
  requestHeader,
  requestBody,
  responseHeader,
  responseBody,
}

/// 协议快速筛选
enum Protocol { http, https, ws, http1, h2 }
