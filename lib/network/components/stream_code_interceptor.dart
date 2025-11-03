import 'dart:convert';

import '../http/http.dart';
import '../util/logger.dart';
import 'interceptor.dart';
import 'manager/stream_code_manager.dart';
import 'stream_code/stream_code_data.dart';

/// Interceptor for extracting Douyin live streaming push codes.
///
/// This interceptor monitors HTTP responses from the `get_latest_room` API,
/// extracts RTMP push URL from JSON payloads, and delegates to StreamCodeManager
/// for parsing and persistence. Operates at priority 500 (after ScriptInterceptor,
/// before RequestBlockInterceptor).
///
/// Error Handling: Never throws exceptions to proxy pipeline - all errors are
/// caught, logged, and handled gracefully to prevent disrupting HTTP traffic.
class StreamCodeInterceptor extends Interceptor {
  StreamCodeManager? _manager;

  @override
  int get priority => 500;

  /// Initialize interceptor by loading StreamCodeManager singleton
  Future<void> initializeInterceptor() async {
    try {
      _manager = await StreamCodeManager.instance;
      logger.i('StreamCodeInterceptor initialized (priority: $priority)');
    } catch (e, stackTrace) {
      logger.e('Failed to initialize StreamCodeInterceptor: $e',
          error: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<HttpResponse?> onResponse(HttpRequest request, HttpResponse response) async {
    // Fire-and-forget extraction; don't block the proxy pipeline
    _extractStreamCodeIfMatch(request, response);
    return response;
  }

  /// Extract stream code if URL matches and auto-extract is enabled
  void _extractStreamCodeIfMatch(HttpRequest request, HttpResponse response) async {
    try {
      // Check if manager initialized
      if (_manager == null) {
        return; // Silent fail - manager not ready
      }

      // Check if auto-extract enabled
      if (!_manager!.autoExtractEnabled) {
        return; // Feature disabled
      }

      // Check if URL matches target API
      final requestUrl = request.requestUrl;
      if (!requestUrl.contains('/webcast/room/get_latest_room/')) {
        return; // Not target API
      }

      // Read response body (bodyAsString handles decompression automatically)
      final bodyAsString = response.bodyAsString;
      if (bodyAsString.isEmpty) {
        logger.w('Stream code extraction skipped: empty response body');
        return;
      }

      // Parse JSON
      Map<String, dynamic> jsonData;
      try {
        jsonData = jsonDecode(bodyAsString) as Map<String, dynamic>;
      } on FormatException catch (e) {
        logger.w('Stream code extraction failed: JSON parse error - $e');
        return;
      }

      // Extract data map with safe navigation
      final dataMap = jsonData['data'] as Map<String, dynamic>?;

      if (dataMap == null) {
        logger.w('Stream code extraction skipped: data field not found');
        return;
      }

      // Parse stream code data from full data map
      StreamCodeData streamCodeData;
      try {
        streamCodeData = StreamCodeData.fromApiResponse(dataMap, request);
      } on FormatException catch (e) {
        logger.w('Stream code extraction failed: $e');
        return;
      }

      // Update manager (async, but don't await to avoid blocking)
      _manager!.updateStreamCode(streamCodeData).then((_) {
        logger.i('Stream code captured: ${streamCodeData.pushAddress}');
      }).catchError((e, stackTrace) {
        logger.e('Failed to update stream code: $e', error: e, stackTrace: stackTrace);
      });
    } catch (e, stackTrace) {
      // Catch-all: log but never throw to proxy pipeline
      logger.e('Unexpected error in stream code extraction: $e',
          error: e, stackTrace: stackTrace);
    }
  }
}
