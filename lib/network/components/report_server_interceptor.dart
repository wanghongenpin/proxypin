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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:proxypin/network/util/compress.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/utils/har.dart';

import '../http/http.dart';
import 'interceptor.dart';
import 'manager/report_server_manager.dart';

/// Hosts interceptor
/// @author wanghongen
class ReportServerInterceptor extends Interceptor {
  Future<ReportServerManager> get reportServerManager async => await ReportServerManager.instance;

  static HttpClient httpClient = HttpClient();

  @override
  int get priority => 1000;

  @override
  Future<HttpResponse?> onResponse(HttpRequest request, HttpResponse response) async {
    // Fire-and-forget reporting; don't block the proxy pipeline
    unawaited(reportServer(request, response));
    return response;
  }

  @override
  Future<void> onError(HttpRequest? request, error, StackTrace? stackTrace) async {
    if (request != null) {
      unawaited(reportServer(request, null, error: error, stackTrace: stackTrace));
    }
    return;
  }

  Future<void> reportServer(HttpRequest request, HttpResponse? response,
      {dynamic error, StackTrace? stackTrace}) async {
    String requestUrl = request.requestUrl;
    var manager = await reportServerManager;
    var server = await manager.matchServer(requestUrl);
    if (server == null) {
      return;
    }

    try {
      logger.i("reportServer start: $requestUrl -> ${server.name} (${server.serverUrl})");

      // Prepare server URL (ensure scheme)
      var serverUrl = (server.serverUrl).trim();
      if (serverUrl.isEmpty) {
        logger.w('reportServer skipped: serverUrl empty for ${server.name}');
        return;
      }
      if (!serverUrl.startsWith('http://') && !serverUrl.startsWith('https://')) {
        serverUrl = 'http://$serverUrl';
      }

      final uri = Uri.parse(serverUrl);

      var payload = Har.toHar(request);

      List<int> body = utf8.encode(jsonEncode(payload));
      // Apply compression if configured
      final compression = server.compression?.toLowerCase();
      if (compression == 'gzip') {
        try {
          body = gzipEncode(body);
        } catch (e) {
          logger.w('reportServer gzip compress failed: $e');
        }
      }

      // Send POST
      final ioReq = await httpClient.postUrl(uri).timeout(const Duration(seconds: 5));

      // Set headers
      final matchedRule = server.name;
      if (matchedRule.isNotEmpty) {
        ioReq.headers.set('X-Report-Name', matchedRule);
      }

      ioReq.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      if (compression == 'gzip') {
        ioReq.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      }

      // Write body and close
      ioReq.add(body);
      final ioResp = await ioReq.close().timeout(const Duration(seconds: 30));
      final respText = await ioResp.transform(utf8.decoder).join();
      if (ioResp.statusCode >= 200 && ioResp.statusCode < 300) {
        logger.i('reportServer delivered to ${server.name} (${uri.toString()}), status=${ioResp.statusCode}');
      } else {
        logger.w('reportServer delivery to ${server.name} failed, status=${ioResp.statusCode}, body=$respText');
      }
    } catch (e, st) {
      logger.e("reportServer error $requestUrl", error: e, stackTrace: st);
    }
  }
}
