import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../storage/path.dart';
import '../../http/http.dart';
import '../../http/http_client.dart';
import '../../util/logger.dart';
import '../stream_code/stream_code_data.dart';

/// Manager for stream code extractor feature.
///
/// This singleton class manages persistent configuration and state for the
/// stream code extractor, including auto-extract toggle state and the last
/// captured stream code data. It provides reactive state updates via
/// ValueNotifier and handles JSON persistence.
class StreamCodeManager {
  static StreamCodeManager? _instance;

  // Reactive state
  final ValueNotifier<bool> _autoExtractEnabledNotifier = ValueNotifier(false);
  final ValueNotifier<StreamCodeData?> _lastStreamCodeNotifier = ValueNotifier(null);

  /// Private constructor for singleton pattern
  StreamCodeManager._internal();

  /// Get singleton instance (async to support loadConfig)
  static Future<StreamCodeManager> get instance async {
    if (_instance == null) {
      _instance = StreamCodeManager._internal();
      await _instance!.loadConfig();
    }
    return _instance!;
  }

  // Public getters for reactive state
  ValueNotifier<bool> get autoExtractEnabledNotifier => _autoExtractEnabledNotifier;
  ValueNotifier<StreamCodeData?> get lastStreamCodeNotifier => _lastStreamCodeNotifier;

  // Synchronous getters for current state values
  bool get autoExtractEnabled => _autoExtractEnabledNotifier.value;
  StreamCodeData? get lastStreamCode => _lastStreamCodeNotifier.value;

  /// Load configuration from persistent storage
  Future<void> loadConfig() async {
    try {
      final file = await Paths.createFile("config", "stream_code_config.json");

      if (!await file.exists()) {
        logger.d('Stream code config file not found, using defaults');
        return;
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        logger.d('Stream code config file is empty, using defaults');
        return;
      }

      final json = jsonDecode(content) as Map<String, dynamic>;
      final settings = StreamCodeSettings.fromJson(json);

      _autoExtractEnabledNotifier.value = settings.autoExtractEnabled;
      _lastStreamCodeNotifier.value = settings.lastStreamCode;

      logger.i('Stream code config loaded: autoExtract=${settings.autoExtractEnabled}, '
          'hasData=${settings.lastStreamCode != null}');
    } catch (e, stackTrace) {
      logger.w('Failed to load stream code config: $e', error: e, stackTrace: stackTrace);
      // Use defaults on error
      _autoExtractEnabledNotifier.value = false;
      _lastStreamCodeNotifier.value = null;
    }
  }

  /// Persist current state to disk
  Future<void> _flush() async {
    try {
      final file = await Paths.createFile("config", "stream_code_config.json");
      final settings = StreamCodeSettings(
        autoExtractEnabled: _autoExtractEnabledNotifier.value,
        lastStreamCode: _lastStreamCodeNotifier.value,
      );

      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (e, stackTrace) {
      logger.e('Failed to flush stream code config: $e', error: e, stackTrace: stackTrace);
      // Don't throw - graceful degradation (feature works in-memory)
    }
  }

  /// Update auto-extract toggle state
  Future<void> setAutoExtractEnabled(bool enabled) async {
    _autoExtractEnabledNotifier.value = enabled;
    await _flush();
    logger.i('Auto-extract enabled: $enabled');
  }

  /// Update stream code data (from interceptor or refresh)
  Future<void> updateStreamCode(StreamCodeData data) async {
    _lastStreamCodeNotifier.value = data;
    await _flush();
    logger.i('Stream code updated: ${data.pushAddress}');
  }

  /// Refresh stream code by replaying last captured request
  ///
  /// Uses ProxyPin's request replay mechanism to resend the original request
  /// with all headers, cookies, and parameters preserved. This ensures the
  /// request passes anti-bot protection and authentication checks.
  ///
  /// Throws Exception with localized message on failure.
  /// Old data is preserved if refresh fails.
  Future<StreamCodeData> refreshStreamCode() async {
    final lastData = _lastStreamCodeNotifier.value;

    if (lastData == null) {
      throw Exception('No previous stream code to refresh');
    }

    if (lastData.originalRequest == null) {
      logger.w('Stream code refresh failed: originalRequest not stored (legacy data)');
      throw Exception('刷新失败：旧版本数据不支持刷新\n请重新抓取推流码');
    }

    try {
      // Replay the original request with all headers, cookies, and parameters
      logger.i('Refreshing stream code by replaying request: ${lastData.originalRequest!.requestUrl}');

      final response = await HttpClients.proxyRequest(
        lastData.originalRequest!,
        timeout: const Duration(seconds: 10),
      );

      if (response.status.code != 200) {
        throw Exception('刷新失败：服务器返回 ${response.status.code}');
      }

      // Use bodyAsString to handle decompression automatically
      final responseBody = response.bodyAsString;
      if (responseBody.isEmpty) {
        throw Exception('刷新失败：响应内容为空');
      }

      final jsonData = jsonDecode(responseBody) as Map<String, dynamic>;

      // Extract data map with safe navigation
      final dataMap = jsonData['data'] as Map<String, dynamic>?;

      if (dataMap == null) {
        logger.w('data field not found in refresh response');
        throw Exception('刷新失败：房间信息不可用');
      }

      // Parse new stream code with the original request
      final newData = StreamCodeData.fromApiResponse(dataMap, lastData.originalRequest!);
      await updateStreamCode(newData);

      logger.i('Stream code refreshed successfully: ${newData.pushAddress}');
      return newData;
    } on TimeoutException {
      logger.w('Stream code refresh timeout');
      throw Exception('刷新失败：请求超时');
    } on SocketException catch (e) {
      logger.w('Stream code refresh network error: $e');
      throw Exception('刷新失败：网络连接失败');
    } on FormatException catch (e) {
      logger.w('Stream code refresh parse error: $e');
      throw Exception('解析失败：数据格式异常');
    } catch (e, stackTrace) {
      logger.e('Stream code refresh failed: $e', error: e, stackTrace: stackTrace);
      throw Exception('刷新失败：$e');
    }
  }

  /// Clean up old stream codes (7-day expiry)
  ///
  /// Should be called on app startup to remove expired data.
  Future<void> cleanupOldData() async {
    final lastData = _lastStreamCodeNotifier.value;
    if (lastData == null) return;

    final now = DateTime.now();
    final age = now.difference(lastData.capturedAt);

    if (age.inDays >= 7) {
      logger.i('Cleaning up old stream code (${age.inDays} days old)');
      _lastStreamCodeNotifier.value = null;
      await _flush();
    }
  }

  /// Extract stream code from captured traffic (manual extraction)
  ///
  /// Searches through ProxyPin's captured traffic for the most recent
  /// `/webcast/room/get_latest_room/` response and extracts the stream code.
  ///
  /// Throws Exception with user-friendly message on failure.
  Future<StreamCodeData> extractFromTraffic(List<HttpRequest> traffic) async {
    // Reverse search to find most recent matching request
    final matches = traffic.reversed.where((request) {
      return request.requestUrl.contains('/webcast/room/get_latest_room/');
    });

    if (matches.isEmpty) {
      throw Exception('未找到推流码请求\n请先访问抖音直播间');
    }

    final latestRequest = matches.first;

    // Check if response has been received
    if (latestRequest.response == null) {
      throw Exception('请求尚未完成\n请等待响应返回');
    }

    // Get response body (already decompressed by bodyAsString)
    final responseBody = latestRequest.response!.bodyAsString;
    if (responseBody.isEmpty) {
      throw Exception('响应内容为空');
    }

    // Parse JSON response
    Map<String, dynamic> jsonData;
    try {
      jsonData = jsonDecode(responseBody) as Map<String, dynamic>;
    } on FormatException catch (e) {
      logger.w('Stream code extraction failed: JSON parse error - $e');
      throw Exception('解析失败：响应格式异常');
    }

    // Extract data map with safe navigation
    final dataMap = jsonData['data'] as Map<String, dynamic>?;

    if (dataMap == null) {
      logger.w('Stream code extraction skipped: data field not found');
      throw Exception('未找到推流码\n可能是房间未开播');
    }

    // Parse stream code data
    StreamCodeData newData;
    try {
      newData = StreamCodeData.fromApiResponse(dataMap, latestRequest);
    } on FormatException catch (e) {
      logger.w('Stream code extraction failed: $e');
      throw Exception('推流码格式异常：$e');
    }

    // Save to persistent storage
    await updateStreamCode(newData);

    logger.i('Stream code extracted from traffic: ${newData.pushAddress}');
    return newData;
  }
}
