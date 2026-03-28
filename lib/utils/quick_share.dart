import 'dart:convert';

import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/utils/har.dart';

class QuickShareBatchResult {
  final int success;
  final int failed;

  const QuickShareBatchResult({required this.success, required this.failed});
}

class QuickShareService {
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
      final remoteUri = Uri.parse(remoteHost);
      final shareUrl =
          '${remoteUri.scheme}://${remoteUri.host}${remoteUri.hasPort ? ':${remoteUri.port}' : ''}/share/quick';
      final payload = utf8.encode(jsonEncode({'entry': Har.toHar(request)}));
      final quickShareRequest = HttpRequest(HttpMethod.post, shareUrl)
        ..headers.contentType = 'application/json; charset=utf-8'
        ..headers.contentLength = payload.length
        ..body = payload;

      final response = await HttpClients.request(HostAndPort.of(shareUrl), quickShareRequest, timeout: timeout);
      return response.status.isSuccessful();
    } catch (_) {
      return false;
    }
  }

  static Future<QuickShareBatchResult> sendRequestsToRemote(ProxyServer proxyServer, Iterable<HttpRequest> requests,
      {Duration timeout = const Duration(seconds: 5)}) async {
    return sendHistoryToRemote(proxyServer, requests, timeout: timeout);
  }

  static Future<QuickShareBatchResult> sendHistoryToRemote(ProxyServer proxyServer, Iterable<HttpRequest> requests,
      {String? historyName, Duration timeout = const Duration(seconds: 5)}) async {
    final remoteHost = proxyServer.configuration.remoteHost;
    if (remoteHost == null || remoteHost.trim().isEmpty) {
      return const QuickShareBatchResult(success: 0, failed: 0);
    }

    final list = requests.toList();
    if (list.isEmpty) {
      return const QuickShareBatchResult(success: 0, failed: 0);
    }

    try {
      final remoteUri = Uri.parse(remoteHost);
      final shareUrl =
          '${remoteUri.scheme}://${remoteUri.host}${remoteUri.hasPort ? ':${remoteUri.port}' : ''}/share/quick';
      final payload = utf8.encode(jsonEncode({
        'shareType': 'history',
        'historyName': historyName,
        'entries': list.map(Har.toHar).toList(),
      }));

      final quickShareRequest = HttpRequest(HttpMethod.post, shareUrl)
        ..headers.contentType = 'application/json; charset=utf-8'
        ..headers.contentLength = payload.length
        ..body = payload;

      final response = await HttpClients.request(HostAndPort.of(shareUrl), quickShareRequest, timeout: timeout);
      if (response.status.isSuccessful()) {
        return QuickShareBatchResult(success: list.length, failed: 0);
      }
      return QuickShareBatchResult(success: 0, failed: list.length);
    } catch (_) {
      return QuickShareBatchResult(success: 0, failed: list.length);
    }
  }
}

