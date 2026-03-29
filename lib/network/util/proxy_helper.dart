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

import 'dart:convert';
import 'dart:io';

import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/components/manager/script_manager.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/util/crts.dart';
import 'package:proxypin/network/util/localizations.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/histories.dart';
import 'package:proxypin/utils/har.dart';

import '../components/host_filter.dart';

class ProxyHelper {
  static const Duration _remoteHistoryBatchTtl = Duration(minutes: 5);
  static final Map<String, _RemoteHistoryBatchState> _remoteHistoryBatchStates = {};

  //请求本服务
  static Future<void> localRequest(ChannelContext channelContext, HttpRequest msg, Channel channel,
      {EventListener? listener}) async {
    //获取配置
    if (msg.path == '/config') {
      final requestRewrites = await RequestRewriteManager.instance;
      var response = HttpResponse(HttpStatus.ok, protocolVersion: msg.protocolVersion);
      var body = {
        "requestRewrites": await requestRewrites.toFullJson(),
        'whitelist': HostFilter.whitelist.toJson(),
        'blacklist': HostFilter.blacklist.toJson(),
        'scripts': await ScriptManager.instance.then((script) {
          var list = script.list.map((e) async {
            return {'name': e.name, 'enabled': e.enabled, 'url': e.urls, 'script': await script.getScript(e)};
          });
          return Future.wait(list);
        }),

      };
      response.body = utf8.encode(json.encode(body));
      channel.writeAndClose(channelContext, response);
      return;
    }

    // 快捷分享：支持单条请求注入，以及历史记录直接导入历史列表。
    if (msg.path == '/share/quick' && msg.method == HttpMethod.post) {
      final response = HttpResponse(HttpStatus.ok, protocolVersion: msg.protocolVersion);
      try {
        final payload = jsonDecode(msg.bodyAsString);
        final shareType = payload is Map ? payload['shareType'] : null;

        if (shareType == 'history') {
          if (payload is! Map || payload['entries'] is! List) {
            throw const FormatException('invalid history share payload');
          }

          final entries = (payload['entries'] as List)
              .whereType<Map>()
              .map((entry) => Har.toRequest(Map<String, dynamic>.from(entry)))
              .toList();
          final historyName = payload['historyName']?.toString();

          final batchId = payload['batchId']?.toString();
          final batchIndex = _toPositiveInt(payload['batchIndex']);
          final batchTotal = _toPositiveInt(payload['batchTotal']);
          final isBatched = batchId != null && batchId.isNotEmpty && batchIndex != null && batchTotal != null;

          if (!isBatched || batchTotal <= 1) {
            await (await HistoryStorage.instance)
                .addRequests(entries, name: historyName, notifyRemoteImported: true);
            response.body = utf8.encode('ok');
            channel.writeAndClose(channelContext, response);
            return;
          }

          _cleanupExpiredRemoteHistoryBatchStates();
          final state = _remoteHistoryBatchStates.putIfAbsent(
            batchId,
            () => _RemoteHistoryBatchState(historyName: historyName, batchTotal: batchTotal),
          );
          if (state.batchTotal != batchTotal) {
            _remoteHistoryBatchStates[batchId] = _RemoteHistoryBatchState(historyName: historyName, batchTotal: batchTotal)
              ..addBatch(batchIndex, entries);
          } else {
            state.addBatch(batchIndex, entries);
            if ((state.historyName == null || state.historyName!.trim().isEmpty) &&
                historyName != null &&
                historyName.trim().isNotEmpty) {
              state.historyName = historyName;
            }
          }

          final currentState = _remoteHistoryBatchStates[batchId]!;
          if (currentState.isCompleted) {
            final merged = currentState.mergedRequests;
            _remoteHistoryBatchStates.remove(batchId);
            await (await HistoryStorage.instance)
                .addRequests(merged, name: currentState.historyName, notifyRemoteImported: true);
          }
          response.body = utf8.encode('ok');
          channel.writeAndClose(channelContext, response);
          return;
        }

        final entry = payload is Map && payload['entry'] != null ? payload['entry'] : payload;
        if (entry is! Map) {
          throw const FormatException('invalid share payload');
        }

        final request = Har.toRequest(Map<String, dynamic>.from(entry));
        request.attributes['quickShare'] = true;
        listener?.onRequest(channel, request);
        if (request.response != null) {
          listener?.onResponse(channelContext, request.response!);
        }
        response.body = utf8.encode('ok');
      } catch (e, st) {
        logger.e('Failed to process quick share payload', error: e, stackTrace: st);
        response.status = HttpStatus.badRequest;
        response.body = utf8.encode('invalid payload');
      }
      channel.writeAndClose(channelContext, response);
      return;
    }

    var response = HttpResponse(HttpStatus.ok, protocolVersion: msg.protocolVersion);
    response.body = utf8.encode('pong');
    response.headers.set("os", Platform.operatingSystem);
    response.headers.set("hostname", Platform.isAndroid ? Platform.operatingSystem : Platform.localHostname);
    channel.writeAndClose(channelContext, response);
  }

  static int? _toPositiveInt(dynamic value) {
    if (value == null) {
      return null;
    }
    final parsed = int.tryParse(value.toString());
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  static void _cleanupExpiredRemoteHistoryBatchStates() {
    final now = DateTime.now();
    _remoteHistoryBatchStates.removeWhere((_, state) => now.difference(state.updatedAt) > _remoteHistoryBatchTtl);
  }

  /// 下载证书
  static void crtDownload(ChannelContext channelContext, Channel channel, HttpRequest request) async {
    const String fileMimeType = 'application/x-x509-ca-cert';
    var response = HttpResponse(HttpStatus.ok);
    response.headers.set(HttpHeaders.CONTENT_TYPE, fileMimeType);
    response.headers.set("Content-Disposition", 'inline;filename=ProxyPinCA.crt');
    response.headers.set("Connection", 'close');

    var caFile = await CertificateManager.certificateFile();
    var caBytes = await caFile.readAsBytes();
    response.headers.set("Content-Length", caBytes.lengthInBytes.toString());

    if (request.method == HttpMethod.head) {
      channel.writeAndClose(channelContext, response);
      return;
    }
    response.body = caBytes;
    channel.writeAndClose(channelContext, response);
  }

  ///异常处理
  static Future<void> exceptionHandler(
      ChannelContext channelContext, Channel channel, EventListener? listener, HttpRequest? request, error) async {
    HostAndPort? hostAndPort = channelContext.host;
    hostAndPort ??= HostAndPort.host(
        scheme: HostAndPort.httpScheme, channel.remoteSocketAddress.host, channel.remoteSocketAddress.port);
    String message = error.toString();
    HttpStatus status = HttpStatus(-1, message);
    if (error is HandshakeException) {
      status = HttpStatus(
          -2,
          Localizations.isZH
              ? 'SSL handshake failed, 请检查证书安装是否正确'
              : 'SSL handshake failed, please check the certificate');
    } else if (error is ParserException) {
      status = HttpStatus(-3, error.message);
    } else if (error is SocketException) {
      status = HttpStatus(-4, error.message);
    } else if (error is SignalException) {
      status.reason(Localizations.isZH ? '执行脚本异常' : 'Execute script exception');
    }

    request ??= HttpRequest(HttpMethod.connect, hostAndPort.domain)
      ..body = message.codeUnits
      ..headers.contentLength = message.codeUnits.length
      ..hostAndPort = hostAndPort;
    request.processInfo ??= channelContext.processInfo;

    if (request.method == HttpMethod.connect && !request.uri.startsWith("http")) {
      request.uri = hostAndPort.domain;
    }

    if (request.response == null || request.method == HttpMethod.connect) {
      request.response = HttpResponse(status)
        ..headers.contentType = 'text/plain'
        ..headers.contentLength = message.codeUnits.length
        ..body = message.codeUnits;
    }

    request.response?.request = request;

    channelContext.host = hostAndPort;

    listener?.onRequest(channel, request);
    listener?.onResponse(channelContext, request.response!);
  }
}

class _RemoteHistoryBatchState {
  String? historyName;
  final int batchTotal;
  final Map<int, List<HttpRequest>> _batches = {};
  DateTime updatedAt = DateTime.now();

  _RemoteHistoryBatchState({required this.historyName, required this.batchTotal});

  void addBatch(int batchIndex, List<HttpRequest> requests) {
    if (batchIndex <= 0 || batchIndex > batchTotal) {
      return;
    }
    updatedAt = DateTime.now();
    _batches.putIfAbsent(batchIndex, () => requests);
  }

  bool get isCompleted => _batches.length == batchTotal;

  List<HttpRequest> get mergedRequests {
    final merged = <HttpRequest>[];
    for (var i = 1; i <= batchTotal; i++) {
      final part = _batches[i];
      if (part != null) {
        merged.addAll(part);
      }
    }
    return merged;
  }
}

