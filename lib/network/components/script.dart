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

import 'package:proxypin/network/components/interceptor.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';

import 'manager/script_manager.dart';

///  developers can write JS code to flexibly manipulate requests/responses
///@author Hongen Wang
class ScriptInterceptor extends Interceptor {
  @override
  int get priority => 10;

  @override
  Future<HttpRequest?> onRequest(HttpRequest request) async {
    //脚本替换
    var scriptManager = await ScriptManager.instance;
    HttpRequest? httpRequest = await scriptManager.runScript(request);
    if (httpRequest == null) {
      return null;
    }
    return request;
  }

  @override
  Future<HttpResponse?> onResponse(HttpRequest request, HttpResponse response) async {
    //脚本替换
    var scriptManager = await ScriptManager.instance;
    try {
      HttpResponse? httpResponse = await scriptManager.runResponseScript(response);
      if (httpResponse == null) {
        return null;
      }
      return httpResponse;
    } catch (e, t) {
      response.status = HttpStatus(-1, 'Script exec error');
      response.body = "$e\n${response.bodyAsString}".codeUnits;
      logger.e('[${request.requestId}] 执行脚本异常 ', error: e, stackTrace: t);
    }
    return response;
  }
}
