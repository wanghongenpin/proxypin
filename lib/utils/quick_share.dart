import 'dart:convert';
import 'dart:math';

import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/utils/har.dart';

class QuickShareBatchResult {
  final int success;
  final int failed;

  const QuickShareBatchResult({required this.success, required this.failed});
}

class QuickShareService {
  static const int _maxHistoryPayloadBytes = 3500 * 1024;
  static final Random _random = Random();

  static bool isRemoteConnected(ProxyServer? proxyServer) {
    final remoteHost = proxyServer?.configuration.remoteHost;
    return remoteHost != null && remoteHost.trim().isNotEmpty;
  }

  static Future<bool> sendRequestToRemote(ProxyServer proxyServer, HttpRequest request,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final remoteHost = proxyServer.configuration.remoteHost;
    if (remoteHost == null || remoteHost.trim().isEmpty) {
      return false;
    }

    try {
      final shareUrl = _buildShareUrl(remoteHost);
      final payload = utf8.encode(jsonEncode({'entry': Har.toHar(request)}));
      if (payload.length > _maxHistoryPayloadBytes) {
        logger.w('Quick share payload too large', error: 'bytes=${payload.length}');
        return false;
      }
      final quickShareRequest = _createJsonPostRequest(shareUrl, payload);

      final response = await HttpClients.request(HostAndPort.of(shareUrl), quickShareRequest, timeout: timeout);
      return response.status.isSuccessful();
    } catch (_) {
      return false;
    }
  }

  static Future<QuickShareBatchResult> sendRequestsToRemote(ProxyServer proxyServer, Iterable<HttpRequest> requests,
      {Duration timeout = const Duration(seconds: 10)}) async {
    return sendHistoryToRemote(proxyServer, requests, timeout: timeout);
  }

  static Future<QuickShareBatchResult> sendHistoryToRemote(ProxyServer proxyServer, Iterable<HttpRequest> requests,
      {String? historyName, Duration timeout = const Duration(seconds: 10)}) async {
    final remoteHost = proxyServer.configuration.remoteHost;
    if (remoteHost == null || remoteHost.trim().isEmpty) {
      return const QuickShareBatchResult(success: 0, failed: 0);
    }

    final list = requests.toList();
    if (list.isEmpty) {
      return const QuickShareBatchResult(success: 0, failed: 0);
    }

    try {
      final shareUrl = _buildShareUrl(remoteHost);
      final entries = list.map(Har.toHar).toList();
      final splitResult = _splitHistoryEntries(entries, historyName);
      final batchId = _buildBatchId();

      var success = 0;
      var failed = splitResult.oversizedFailed;
      final totalBatches = splitResult.batches.length;

      for (var i = 0; i < totalBatches; i++) {
        final batch = splitResult.batches[i];
        final sent = await _sendHistoryBatch(
          shareUrl,
          batch,
          historyName: historyName,
          batchId: batchId,
          batchIndex: i + 1,
          batchTotal: totalBatches,
          timeout: timeout,
        );
        if (sent) {
          success += batch.length;
        } else {
          failed += batch.length;
        }
      }

      return QuickShareBatchResult(success: success, failed: failed);
    } catch (e) {
      logger.w('Failed to send history to remote', error: e);
      return QuickShareBatchResult(success: 0, failed: list.length);
    }
  }

  static String _buildShareUrl(String remoteHost) {
    final remoteUri = Uri.parse(remoteHost);
    return '${remoteUri.scheme}://${remoteUri.host}${remoteUri.hasPort ? ':${remoteUri.port}' : ''}/share/quick';
  }

  static HttpRequest _createJsonPostRequest(String url, List<int> payload) {
    return HttpRequest(HttpMethod.post, url)
      ..headers.contentType = 'application/json; charset=utf-8'
      ..headers.contentLength = payload.length
      ..body = payload;
  }

  static Future<bool> _sendHistoryBatch(String shareUrl, List<Map> entries,
      {String? historyName,
      required String batchId,
      required int batchIndex,
      required int batchTotal,
      required Duration timeout}) async {
    final payload = utf8.encode(jsonEncode({
      'shareType': 'history',
      'historyName': historyName,
      'batchId': batchId,
      'batchIndex': batchIndex,
      'batchTotal': batchTotal,
      'entries': entries,
    }));

    final quickShareRequest = _createJsonPostRequest(shareUrl, payload);
    final response = await HttpClients.request(HostAndPort.of(shareUrl), quickShareRequest, timeout: timeout);
    return response.status.isSuccessful();
  }

  static _HistorySplitResult _splitHistoryEntries(List<Map> entries, String? historyName) {
    final batches = <List<Map>>[];
    final current = <Map>[];
    final basePayloadSize = _historyPayloadBaseSize(historyName);

    var currentPayloadSize = basePayloadSize;
    var oversizedFailed = 0;

    for (final entry in entries) {
      final entrySize = utf8.encode(jsonEncode(entry)).length;
      final minSinglePayload = basePayloadSize + entrySize;
      if (minSinglePayload > _maxHistoryPayloadBytes) {
        oversizedFailed++;
        continue;
      }

      final withDelimiterSize = currentPayloadSize + (current.isEmpty ? 0 : 1) + entrySize;
      if (withDelimiterSize > _maxHistoryPayloadBytes) {
        batches.add(List<Map>.from(current));
        current
          ..clear()
          ..add(entry);
        currentPayloadSize = minSinglePayload;
        continue;
      }

      current.add(entry);
      currentPayloadSize = withDelimiterSize;
    }

    if (current.isNotEmpty) {
      batches.add(current);
    }

    return _HistorySplitResult(batches: batches, oversizedFailed: oversizedFailed);
  }

  static int _historyPayloadBaseSize(String? historyName) {
    return utf8
        .encode(jsonEncode({
          'shareType': 'history',
          'historyName': historyName,
          'batchId': '0',
          'batchIndex': 1,
          'batchTotal': 1,
          'entries': const <Map>[]
        }))
        .length;
  }

  static String _buildBatchId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(1 << 32);
    return '$ts-$suffix';
  }
}

class _HistorySplitResult {
  final List<List<Map>> batches;
  final int oversizedFailed;

  const _HistorySplitResult({required this.batches, required this.oversizedFailed});
}

