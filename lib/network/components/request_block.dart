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

import 'package:proxypin/network/components/manager/request_block_manager.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';

import 'interceptor.dart';

/// RequestBlockInterceptor is a component that can block the request or response.
/// @author Hongen Wang
class RequestBlockInterceptor extends Interceptor {
  @override
  int get priority => 1000;

  @override
  Future<HttpRequest?> onRequest(HttpRequest request) async {
    var uri = request.domainPath;
    var blockRequest = (await RequestBlockManager.instance).enableBlockRequest(uri);
    if (blockRequest) {
      logger.d("[${request.requestId}] 屏蔽请求 $uri");
      return null;
    }
    return request;
  }

  @override
  Future<HttpResponse?> onResponse(HttpRequest request, HttpResponse response) async {
    var uri = request.domainPath;
    var blockResponse = (await RequestBlockManager.instance).enableBlockResponse(uri);
    if (blockResponse) {
      logger.d("[${request.requestId}] 屏蔽响应 $uri");
      return null;
    }
    return response;
  }
}
