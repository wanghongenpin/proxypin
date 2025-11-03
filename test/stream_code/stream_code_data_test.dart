import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/components/stream_code/stream_code_data.dart';

void main() {
  group('StreamCodeData', () {
    const validRtmpUrl = 'rtmp://push-rtmp-l3.douyincdn.com/stage/stream-123456?auth_key=abc&expires=123';
    const validRequestUrl = 'https://webcast5-mate-lf.amemv.com/webcast/room/get_latest_room/?room_id=7123456789';

    test('fromApiResponse with valid URL should split correctly', () {
      final data = StreamCodeData.fromApiResponse(validRtmpUrl, validRequestUrl);

      expect(data.rtmpPushUrl, equals(validRtmpUrl));
      expect(data.pushAddress, equals('rtmp://push-rtmp-l3.douyincdn.com/stage/'));
      expect(data.streamKey, equals('stream-123456?auth_key=abc&expires=123'));
      expect(data.requestUrl, equals(validRequestUrl));
      expect(data.capturedAt, isA<DateTime>());
    });

    test('fromApiResponse without "stream-" separator should throw FormatException', () {
      const invalidUrl = 'rtmp://push-rtmp-l3.douyincdn.com/stage/invalid-url';

      expect(
        () => StreamCodeData.fromApiResponse(invalidUrl, validRequestUrl),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('missing "stream-" separator'),
        )),
      );
    });

    test('toJson and fromJson should preserve data', () {
      final capturedTime = DateTime.parse('2025-11-03T10:30:45.123Z');
      final original = StreamCodeData(
        rtmpPushUrl: validRtmpUrl,
        pushAddress: 'rtmp://push-rtmp-l3.douyincdn.com/stage/',
        streamKey: 'stream-123456?auth_key=abc&expires=123',
        capturedAt: capturedTime,
        requestUrl: validRequestUrl,
      );

      final json = original.toJson();
      final restored = StreamCodeData.fromJson(json);

      expect(restored.rtmpPushUrl, equals(original.rtmpPushUrl));
      expect(restored.pushAddress, equals(original.pushAddress));
      expect(restored.streamKey, equals(original.streamKey));
      expect(restored.capturedAt, equals(original.capturedAt));
      expect(restored.requestUrl, equals(original.requestUrl));
    });

    test('equality operator should compare by rtmpPushUrl and capturedAt', () {
      final time1 = DateTime.parse('2025-11-03T10:30:45.123Z');
      final time2 = DateTime.parse('2025-11-03T10:30:45.123Z');
      final time3 = DateTime.parse('2025-11-03T10:35:00.000Z');

      final data1 = StreamCodeData(
        rtmpPushUrl: validRtmpUrl,
        pushAddress: 'rtmp://push-rtmp-l3.douyincdn.com/stage/',
        streamKey: 'stream-123456?auth_key=abc&expires=123',
        capturedAt: time1,
        requestUrl: validRequestUrl,
      );

      final data2 = StreamCodeData(
        rtmpPushUrl: validRtmpUrl,
        pushAddress: 'rtmp://push-rtmp-l3.douyincdn.com/stage/',
        streamKey: 'stream-123456?auth_key=abc&expires=123',
        capturedAt: time2,
        requestUrl: validRequestUrl,
      );

      final data3 = StreamCodeData(
        rtmpPushUrl: validRtmpUrl,
        pushAddress: 'rtmp://push-rtmp-l3.douyincdn.com/stage/',
        streamKey: 'stream-123456?auth_key=abc&expires=123',
        capturedAt: time3,
        requestUrl: validRequestUrl,
      );

      expect(data1, equals(data2)); // Same time
      expect(data1, isNot(equals(data3))); // Different time
    });

    test('hashCode should be consistent with equality', () {
      final time = DateTime.parse('2025-11-03T10:30:45.123Z');

      final data1 = StreamCodeData(
        rtmpPushUrl: validRtmpUrl,
        pushAddress: 'rtmp://push-rtmp-l3.douyincdn.com/stage/',
        streamKey: 'stream-123456?auth_key=abc&expires=123',
        capturedAt: time,
        requestUrl: validRequestUrl,
      );

      final data2 = StreamCodeData(
        rtmpPushUrl: validRtmpUrl,
        pushAddress: 'rtmp://push-rtmp-l3.douyincdn.com/stage/',
        streamKey: 'stream-123456?auth_key=abc&expires=123',
        capturedAt: time,
        requestUrl: validRequestUrl,
      );

      expect(data1.hashCode, equals(data2.hashCode));
    });

    test('toString should include key fields', () {
      final data = StreamCodeData.fromApiResponse(validRtmpUrl, validRequestUrl);
      final str = data.toString();

      expect(str, contains('pushAddress'));
      expect(str, contains('streamKey'));
      expect(str, contains('capturedAt'));
    });
  });

  group('StreamCodeSettings', () {
    test('default constructor should have correct defaults', () {
      final settings = StreamCodeSettings();

      expect(settings.autoExtractEnabled, isFalse);
      expect(settings.lastStreamCode, isNull);
    });

    test('toJson and fromJson with null lastStreamCode should preserve data', () {
      final original = StreamCodeSettings(
        autoExtractEnabled: true,
        lastStreamCode: null,
      );

      final json = original.toJson();
      final restored = StreamCodeSettings.fromJson(json);

      expect(restored.autoExtractEnabled, isTrue);
      expect(restored.lastStreamCode, isNull);
    });

    test('toJson and fromJson with valid lastStreamCode should preserve nested data', () {
      final streamCodeData = StreamCodeData.fromApiResponse(
        'rtmp://push-rtmp-l3.douyincdn.com/stage/stream-123456?auth_key=abc',
        'https://webcast5-mate-lf.amemv.com/webcast/room/get_latest_room/?room_id=123',
      );

      final original = StreamCodeSettings(
        autoExtractEnabled: true,
        lastStreamCode: streamCodeData,
      );

      final json = original.toJson();
      final restored = StreamCodeSettings.fromJson(json);

      expect(restored.autoExtractEnabled, isTrue);
      expect(restored.lastStreamCode, isNotNull);
      expect(restored.lastStreamCode!.rtmpPushUrl, equals(streamCodeData.rtmpPushUrl));
      expect(restored.lastStreamCode!.pushAddress, equals(streamCodeData.pushAddress));
      expect(restored.lastStreamCode!.streamKey, equals(streamCodeData.streamKey));
      expect(restored.lastStreamCode!.requestUrl, equals(streamCodeData.requestUrl));
    });

    test('fromJson with missing autoExtractEnabled should default to false', () {
      final json = <String, dynamic>{};
      final settings = StreamCodeSettings.fromJson(json);

      expect(settings.autoExtractEnabled, isFalse);
      expect(settings.lastStreamCode, isNull);
    });

    test('toString should indicate presence of lastStreamCode', () {
      final settingsWithoutData = StreamCodeSettings();
      final settingsWithData = StreamCodeSettings(
        autoExtractEnabled: true,
        lastStreamCode: StreamCodeData.fromApiResponse(
          'rtmp://push-rtmp-l3.douyincdn.com/stage/stream-123?auth_key=abc',
          'https://webcast5-mate-lf.amemv.com/webcast/room/get_latest_room/?room_id=123',
        ),
      );

      expect(settingsWithoutData.toString(), contains('hasLastStreamCode: false'));
      expect(settingsWithData.toString(), contains('hasLastStreamCode: true'));
    });
  });

  group('JSON Edge Cases', () {
    test('StreamCodeData fromJson with invalid capturedAt should throw', () {
      final invalidJson = {
        'rtmpPushUrl': 'rtmp://test/stream-123',
        'pushAddress': 'rtmp://test/',
        'streamKey': 'stream-123',
        'capturedAt': 'invalid-date-format',
        'requestUrl': 'https://test.com',
      };

      expect(
        () => StreamCodeData.fromJson(invalidJson),
        throwsA(isA<FormatException>()),
      );
    });

    test('StreamCodeSettings fromJson with null lastStreamCode field should work', () {
      final json = {
        'autoExtractEnabled': true,
        'lastStreamCode': null,
      };

      final settings = StreamCodeSettings.fromJson(json);
      expect(settings.autoExtractEnabled, isTrue);
      expect(settings.lastStreamCode, isNull);
    });
  });
}
