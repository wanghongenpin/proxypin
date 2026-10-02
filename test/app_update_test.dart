import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/ui/app_update/app_update_repository.dart';
import 'package:proxypin/ui/app_update/remote_version_entity.dart';

void main() {
  group('compareVersions', () {
    test('should handle uppercase V prefix (V1.3.3 regression)', () {
      expect(AppUpdateRepository.compareVersions('1.3.2', 'V1.3.3'), isTrue);
      expect(AppUpdateRepository.compareVersions('1.3.3', 'V1.3.3'), isFalse);
      expect(AppUpdateRepository.compareVersions('1.3.4', 'V1.3.3'), isFalse);
    });

    test('should handle lowercase v prefix', () {
      expect(AppUpdateRepository.compareVersions('1.3.2', 'v1.3.3'), isTrue);
      expect(AppUpdateRepository.compareVersions('1.3.3', 'v1.3.3'), isFalse);
    });

    test('should handle versions without prefix', () {
      expect(AppUpdateRepository.compareVersions('1.3.2', '1.3.3'), isTrue);
      expect(AppUpdateRepository.compareVersions('1.3.3', '1.3.3'), isFalse);
    });

    test('should compare extra sub-version segments', () {
      expect(AppUpdateRepository.compareVersions('1.3.3', '1.3.3.1'), isTrue);
      expect(AppUpdateRepository.compareVersions('1.3.3.1', '1.3.3'), isFalse);
    });

    test('should not throw on pre-release suffixes', () {
      expect(() => AppUpdateRepository.compareVersions('1.3.3', '1.3.4-beta'), returnsNormally);
      expect(AppUpdateRepository.compareVersions('1.3.3', '1.3.4-beta'), isTrue);
    });
  });

  group('GithubReleaseParser', () {
    Map<String, dynamic> releaseJson(String tag) => {
          'tag_name': tag,
          'prerelease': false,
          'published_at': '2026-09-29T06:23:52Z',
          'html_url': 'https://github.com/wanghongenpin/proxypin/releases/tag/$tag',
          'body': '',
          'assets': const [],
        };

    test('should parse uppercase V tag', () {
      final entity = GithubReleaseParser.parse(releaseJson('V1.3.3'));
      expect(entity.version, '1.3.3');
      expect(entity.releaseTag, '1.3.3');
    });

    test('should parse lowercase v tag with build number', () {
      final entity = GithubReleaseParser.parse(releaseJson('v1.3.4+5'));
      expect(entity.version, '1.3.4');
      expect(entity.buildNumber, '5');
      expect(entity.releaseTag, '1.3.4+5');
    });

    test('should parse tag without prefix', () {
      final entity = GithubReleaseParser.parse(releaseJson('1.3.5'));
      expect(entity.version, '1.3.5');
      expect(entity.releaseTag, '1.3.5');
    });
  });
}
