import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxypin/ui/app_update/app_update_repository.dart';
import 'package:proxypin/ui/app_update/constants.dart';
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

  group('getLatestVersion', () {
    const latestReleaseUrl = 'https://github.com/wanghongenpin/proxypin/releases/tag/v1.5.0';
    const feed = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <updated>2026-11-03T00:00:00Z</updated>
    <link rel="alternate" type="text/html" href="https://github.com/wanghongenpin/proxypin/releases/tag/v1.6.0-rc.1"/>
    <content type="html">&lt;p&gt;V1.6.0-rc.1&lt;/p&gt;&lt;p&gt;Release candidate&lt;/p&gt;</content>
  </entry>
  <entry>
    <updated>2026-11-02T00:00:00Z</updated>
    <link rel="alternate" type="text/html" href="$latestReleaseUrl"/>
    <content type="html">&lt;p&gt;V1.5.0&lt;/p&gt;&lt;ul&gt;&lt;li&gt;First change&lt;/li&gt;&lt;li&gt;Second &amp;amp; third&lt;/li&gt;&lt;/ul&gt;</content>
  </entry>
</feed>''';
    const assets = '''
<ul>
  <li><a href="/wanghongenpin/proxypin/releases/download/v1.5.0/proxypin-windows.zip">
    <span class="text-bold">proxypin-windows.zip</span></a><span>20.5 MB</span></li>
  <li><a href="/wanghongenpin/proxypin/releases/download/v1.5.0/proxypin-macos.dmg">
    <span class="text-bold">proxypin-macos.dmg</span></a><span>21.1 MB</span></li>
</ul>''';

    MockClient fallbackClient(List<Uri> requests) {
      return MockClient((request) async {
        requests.add(request.url);
        if (request.url.host == 'api.github.com') {
          return http.Response('{"message":"API rate limit exceeded"}', 403,
              headers: {'x-ratelimit-remaining': '0', 'x-ratelimit-reset': '1793628866'});
        }
        if (request.url.toString() == Constants.githubLatestReleaseUrl) {
          return http.Response('', 302, headers: {'location': latestReleaseUrl});
        }
        if (request.url.toString() == Constants.githubReleasesFeedUrl) {
          return http.Response(feed, 200);
        }
        if (request.url.path == '/wanghongenpin/proxypin/releases/expanded_assets/v1.5.0') {
          return http.Response(assets, 200);
        }
        return http.Response('not found', 404);
      });
    }

    test('falls back to the releases website when the API is rate limited', () async {
      final requests = <Uri>[];
      final release = await AppUpdateRepository.getLatestVersion(client: fallbackClient(requests));

      expect(release, isNotNull);
      expect(release!.version, '1.5.0');
      expect(release.releaseTag, '1.5.0');
      expect(release.preRelease, isFalse);
      expect(release.url, latestReleaseUrl);
      expect(release.content, contains('First change\nSecond & third'));
      expect(release.assets, hasLength(2));
      expect(release.assets.first.name, 'proxypin-windows.zip');
      expect(release.assets.first.downloadUrl,
          'https://github.com/wanghongenpin/proxypin/releases/download/v1.5.0/proxypin-windows.zip');
      expect(release.assets.first.size, isNull, reason: 'HTML file sizes are rounded and must not be verified exactly');
      expect(requests, hasLength(4));
    });

    test('website fallback can include a pre-release', () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        if (request.url.host == 'api.github.com') {
          return http.Response('Too many requests', 429);
        }
        if (request.url.toString() == Constants.githubLatestReleaseUrl) {
          return http.Response('', 302, headers: {'location': latestReleaseUrl});
        }
        if (request.url.toString() == Constants.githubReleasesFeedUrl) {
          return http.Response(feed, 200);
        }
        if (request.url.path == '/wanghongenpin/proxypin/releases/expanded_assets/v1.6.0-rc.1') {
          return http.Response('', 200);
        }
        return http.Response('not found', 404);
      });

      final release = await AppUpdateRepository.getLatestVersion(client: client, includePreReleases: true);

      expect(release, isNotNull);
      expect(release!.version, '1.6.0');
      expect(release.releaseTag, '1.6.0-rc.1');
      expect(release.preRelease, isTrue);
      expect(release.content, contains('Release candidate'));
      expect(requests, hasLength(4));
    });

    test('does not use the website fallback for an unrelated forbidden response', () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        return http.Response('Forbidden', 403);
      });

      final release = await AppUpdateRepository.getLatestVersion(client: client);

      expect(release, isNull);
      expect(requests, hasLength(1));
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
