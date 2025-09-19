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

  //状态码
  int? statusCode;

  SearchModel([this.keyword]);

  bool get isNotEmpty {
    return keyword?.trim().isNotEmpty == true ||
        requestMethod != null ||
        requestContentType != null ||
        responseContentType != null ||
        statusCode != null;
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
    searchModel.statusCode = statusCode;
    searchModel.caseSensitive = RxBool(caseSensitive.value);
    return searchModel;
  }

  @override
  String toString() {
    return 'SearchModel{keyword: $keyword, searchOptions: $searchOptions, responseContentType: $responseContentType, requestMethod: $requestMethod, requestContentType: $requestContentType, statusCode: $statusCode}';
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
    if (statusCode != null && response?.status.code != statusCode) {
      return false;
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
