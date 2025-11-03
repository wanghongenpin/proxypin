import '../../http/http.dart';

/// Data entity representing a captured Douyin live streaming push code.
///
/// This class holds the complete stream code information extracted from
/// `get_latest_room` API responses, including the original URL, parsed
/// components (push address and stream key), capture timestamp, and the
/// original request for replay functionality.
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

  /// Original request URL (with query parameters) for backward compatibility
  /// Example: "https://webcast5-mate-lf.amemv.com/webcast/room/get_latest_room/?room_id=xxx"
  final String requestUrl;

  /// Original HTTP request with all headers, cookies, and parameters
  /// Used for accurate request replay to refresh stream code
  final HttpRequest? originalRequest;

  /// Live room title from API response
  final String? roomTitle;

  /// Live room cover image URL (first URL from cover.url_list)
  final String? coverImageUrl;

  /// Account nickname from owner.nickname
  final String? accountNickname;

  /// Account avatar URL (first URL from owner.avatar_thumb.url_list)
  final String? accountAvatarUrl;

  /// Account Douyin ID from owner.short_id
  final String? accountShortId;

  /// Live room ID from id_str (or id as fallback)
  final String? roomId;

  StreamCodeData({
    required this.rtmpPushUrl,
    required this.pushAddress,
    required this.streamKey,
    required this.capturedAt,
    required this.requestUrl,
    this.originalRequest,
    this.roomTitle,
    this.coverImageUrl,
    this.accountNickname,
    this.accountAvatarUrl,
    this.accountShortId,
    this.roomId,
  });

  /// Deserialize from JSON (for persistence)
  factory StreamCodeData.fromJson(Map<String, dynamic> json) {
    return StreamCodeData(
      rtmpPushUrl: json['rtmpPushUrl'] as String,
      pushAddress: json['pushAddress'] as String,
      streamKey: json['streamKey'] as String,
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      requestUrl: json['requestUrl'] as String,
      originalRequest: json['originalRequest'] != null
          ? HttpRequest.fromJson(json['originalRequest'] as Map<String, dynamic>)
          : null,
      roomTitle: json['roomTitle'] as String?,
      coverImageUrl: json['coverImageUrl'] as String?,
      accountNickname: json['accountNickname'] as String?,
      accountAvatarUrl: json['accountAvatarUrl'] as String?,
      accountShortId: json['accountShortId'] as String?,
      roomId: json['roomId'] as String?,
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
      'originalRequest': originalRequest?.toJson(),
      'roomTitle': roomTitle,
      'coverImageUrl': coverImageUrl,
      'accountNickname': accountNickname,
      'accountAvatarUrl': accountAvatarUrl,
      'accountShortId': accountShortId,
      'roomId': roomId,
    };
  }

  /// Factory method to parse from API response
  ///
  /// Expects the `data` object from API response containing:
  /// - stream_url.rtmp_push_url (required)
  /// - id_str or id (optional, room ID)
  /// - title (optional)
  /// - cover.url_list (optional)
  /// - owner.nickname (optional)
  /// - owner.avatar_thumb.url_list (optional)
  /// - owner.short_id (optional)
  ///
  /// Throws FormatException if URL format is invalid (missing "stream-" separator)
  factory StreamCodeData.fromApiResponse(
    Map<String, dynamic> dataMap,
    HttpRequest request,
  ) {
    // Extract rtmp_push_url (required)
    final rtmpPushUrl = dataMap['stream_url']?['rtmp_push_url'] as String?;
    if (rtmpPushUrl == null || rtmpPushUrl.isEmpty) {
      throw FormatException('Missing rtmp_push_url in API response');
    }

    final streamIndex = rtmpPushUrl.indexOf('stream-');
    if (streamIndex == -1) {
      throw FormatException('Invalid rtmpPushUrl: missing "stream-" separator');
    }

    // Extract optional fields with safe navigation
    final roomTitle = dataMap['title'] as String?;

    // Cover image: get first URL from url_list array
    final coverList = (dataMap['cover']?['url_list'] as List<dynamic>?)
        ?.map((e) => e as String?)
        .where((url) => url != null && url.isNotEmpty)
        .toList();
    final coverImageUrl = coverList?.isNotEmpty == true ? coverList!.first : null;

    // Owner info
    final ownerMap = dataMap['owner'] as Map<String, dynamic>?;
    final accountNickname = ownerMap?['nickname'] as String?;
    final accountShortId = ownerMap?['short_id']?.toString();

    // Avatar: get first URL from url_list array
    final avatarList = (ownerMap?['avatar_thumb']?['url_list'] as List<dynamic>?)
        ?.map((e) => e as String?)
        .where((url) => url != null && url.isNotEmpty)
        .toList();
    final accountAvatarUrl = avatarList?.isNotEmpty == true ? avatarList!.first : null;

    // Room ID: prefer id_str to avoid precision loss with large numbers
    final roomId = dataMap['id_str'] as String? ?? dataMap['id']?.toString();

    return StreamCodeData(
      rtmpPushUrl: rtmpPushUrl,
      pushAddress: rtmpPushUrl.substring(0, streamIndex),
      streamKey: rtmpPushUrl.substring(streamIndex),
      capturedAt: DateTime.now(),
      requestUrl: request.requestUrl,
      originalRequest: request,
      roomTitle: roomTitle,
      coverImageUrl: coverImageUrl,
      accountNickname: accountNickname,
      accountAvatarUrl: accountAvatarUrl,
      accountShortId: accountShortId,
      roomId: roomId,
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
