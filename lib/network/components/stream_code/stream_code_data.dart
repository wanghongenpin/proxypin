/// Data entity representing a captured Douyin live streaming push code.
///
/// This class holds the complete stream code information extracted from
/// `get_latest_room` API responses, including the original URL, parsed
/// components (push address and stream key), capture timestamp, and the
/// original request URL for refresh functionality.
class StreamCodeData {
  /// Original complete URL extracted from API response
  /// Example: "rtmp://push-rtmp-l3.douyincdn.com/stage/stream-xxx?auth_key=..."
  final String rtmpPushUrl;

  /// Push address (URL portion before "stream-")
  /// Example: "rtmp://push-rtmp-l3.douyincdn.com/stage/"
  final String pushAddress;

  /// Stream key (URL portion from "stream-" onwards)
  /// Example: "stream-xxx?auth_key=..."
  final String streamKey;

  /// Timestamp when this stream code was captured
  final DateTime capturedAt;

  /// Original request URL (with query parameters) for refresh functionality
  /// Example: "https://webcast5-mate-lf.amemv.com/webcast/room/get_latest_room/?room_id=xxx"
  final String requestUrl;

  StreamCodeData({
    required this.rtmpPushUrl,
    required this.pushAddress,
    required this.streamKey,
    required this.capturedAt,
    required this.requestUrl,
  });

  /// Deserialize from JSON (for persistence)
  factory StreamCodeData.fromJson(Map<String, dynamic> json) {
    return StreamCodeData(
      rtmpPushUrl: json['rtmpPushUrl'] as String,
      pushAddress: json['pushAddress'] as String,
      streamKey: json['streamKey'] as String,
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      requestUrl: json['requestUrl'] as String,
    );
  }

  /// Serialize to JSON (for persistence)
  Map<String, dynamic> toJson() {
    return {
      'rtmpPushUrl': rtmpPushUrl,
      'pushAddress': pushAddress,
      'streamKey': streamKey,
      'capturedAt': capturedAt.toIso8601String(),
      'requestUrl': requestUrl,
    };
  }

  /// Factory method to parse from API response
  /// Throws FormatException if URL format is invalid (missing "stream-" separator)
  factory StreamCodeData.fromApiResponse(String rtmpPushUrl, String requestUrl) {
    final streamIndex = rtmpPushUrl.indexOf('stream-');
    if (streamIndex == -1) {
      throw FormatException('Invalid rtmpPushUrl: missing "stream-" separator');
    }

    return StreamCodeData(
      rtmpPushUrl: rtmpPushUrl,
      pushAddress: rtmpPushUrl.substring(0, streamIndex),
      streamKey: rtmpPushUrl.substring(streamIndex),
      capturedAt: DateTime.now(),
      requestUrl: requestUrl,
    );
  }

  @override
  String toString() {
    return 'StreamCodeData(pushAddress: $pushAddress, streamKey: $streamKey, '
        'capturedAt: $capturedAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StreamCodeData &&
        other.rtmpPushUrl == rtmpPushUrl &&
        other.capturedAt == capturedAt;
  }

  @override
  int get hashCode => rtmpPushUrl.hashCode ^ capturedAt.hashCode;
}

/// Settings entity for the stream code extractor feature.
///
/// Stores persistent configuration including the auto-extract toggle state
/// and the last captured stream code data.
class StreamCodeSettings {
  /// Whether auto-extraction is enabled
  bool autoExtractEnabled;

  /// Last captured stream code data (nullable)
  StreamCodeData? lastStreamCode;

  StreamCodeSettings({
    this.autoExtractEnabled = false,
    this.lastStreamCode,
  });

  /// Deserialize from JSON (for persistence)
  factory StreamCodeSettings.fromJson(Map<String, dynamic> json) {
    return StreamCodeSettings(
      autoExtractEnabled: json['autoExtractEnabled'] as bool? ?? false,
      lastStreamCode: json['lastStreamCode'] != null
          ? StreamCodeData.fromJson(json['lastStreamCode'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Serialize to JSON (for persistence)
  Map<String, dynamic> toJson() {
    return {
      'autoExtractEnabled': autoExtractEnabled,
      'lastStreamCode': lastStreamCode?.toJson(),
    };
  }

  @override
  String toString() {
    return 'StreamCodeSettings(autoExtractEnabled: $autoExtractEnabled, '
        'hasLastStreamCode: ${lastStreamCode != null})';
  }
}
