import 'dart:io';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/app_update/constants.dart';
import 'package:proxypin/ui/app_update/remote_version_entity.dart';
import 'package:xml/xml.dart';

/// Reads release information from GitHub's public web pages without using the
/// rate-limited REST API.
class GithubReleaseWebsite {
  static const _headers = {HttpHeaders.userAgentHeader: 'ProxyPin-Updater'};

  static Future<RemoteVersionEntity?> fetch(http.Client client, {bool includePreReleases = false}) async {
    final latestUri = Uri.parse(Constants.githubLatestReleaseUrl);
    final latestRequest = http.Request('GET', latestUri)
      ..followRedirects = false
      ..headers.addAll(_headers);
    final latestResponse = await http.Response.fromStream(await client.send(latestRequest));
    final location = latestResponse.headers[HttpHeaders.locationHeader];
    if (!_isRedirect(latestResponse.statusCode) || location == null) {
      throw http.ClientException('Failed to resolve the latest release (HTTP ${latestResponse.statusCode})', latestUri);
    }

    final latestTag = _tagFromReleaseUrl(latestUri.resolve(location));
    if (latestTag == null) {
      logger.w('[AppUpdate] could not resolve latest release tag from $location');
      return null;
    }

    final feedResponse = await client.get(Uri.parse(Constants.githubReleasesFeedUrl), headers: _headers);
    if (feedResponse.statusCode != HttpStatus.ok) {
      throw http.ClientException(
          'Failed to fetch the releases feed (HTTP ${feedResponse.statusCode})', feedResponse.request?.url);
    }

    final release = _parseFeed(feedResponse.body, latestTag, includePreReleases: includePreReleases);
    if (release == null) {
      logger.w('[AppUpdate] latest release $latestTag was not found in the releases feed');
      return null;
    }

    var assets = const <ReleaseAsset>[];
    try {
      final fullTag = _tagFromReleaseUrl(Uri.parse(release.url))!;
      final assetsUrl = Uri.parse('${Constants.githubUrl}/releases/expanded_assets/${Uri.encodeComponent(fullTag)}');
      final assetsResponse = await client.get(assetsUrl, headers: _headers);
      if (assetsResponse.statusCode == HttpStatus.ok) {
        assets = _parseAssets(assetsResponse.body);
      } else {
        logger.w('[AppUpdate] failed to fetch release assets: HTTP ${assetsResponse.statusCode}');
      }
    } catch (e) {
      // The release page still allows a manual download when asset discovery fails.
      logger.w('[AppUpdate] failed to fetch release assets: $e');
    }

    return RemoteVersionEntity(
      version: release.version,
      buildNumber: release.buildNumber,
      releaseTag: release.releaseTag,
      preRelease: release.preRelease,
      url: release.url,
      content: release.content,
      publishedAt: release.publishedAt,
      assets: assets,
    );
  }

  static RemoteVersionEntity? _parseFeed(String body, String latestTag, {required bool includePreReleases}) {
    final document = XmlDocument.parse(body);
    for (final entry in document.findAllElements('entry')) {
      final url = entry.findElements('link').map((e) => e.getAttribute('href')).whereType<String>().firstWhere(
            (href) => _tagFromReleaseUrl(Uri.tryParse(href)) != null,
            orElse: () => '',
          );
      final tag = _tagFromReleaseUrl(Uri.tryParse(url));
      final publishedAt = entry.getElement('updated')?.innerText;
      if (tag == null || publishedAt == null) continue;
      if (!includePreReleases && tag != latestTag) continue;

      final content = entry.getElement('content')?.innerText ?? '';
      return GithubReleaseParser.parse({
        'tag_name': tag,
        'prerelease': tag != latestTag,
        'published_at': publishedAt,
        'html_url': url,
        'body': _htmlToPlainText(content),
        'assets': const [],
      });
    }
    return null;
  }

  static List<ReleaseAsset> _parseAssets(String body) {
    final assets = <ReleaseAsset>[];
    final seenUrls = <String>{};
    for (final link in html.parse(body).querySelectorAll('a[href]')) {
      final href = link.attributes['href'];
      if (href == null) continue;
      final url = Uri.parse(Constants.githubUrl).resolve(href);
      if (url.host != 'github.com' || !url.path.contains('/releases/download/')) continue;

      final name = link.querySelector('.text-bold')?.text.trim() ?? link.text.trim();
      if (name.isEmpty || !seenUrls.add(url.toString())) continue;

      // GitHub's HTML rounds file sizes, so leave size null instead of using an
      // approximate value for the downloader's exact size verification.
      assets.add(ReleaseAsset(name: name, downloadUrl: url.toString()));
    }
    return assets;
  }

  static String _htmlToPlainText(String body) {
    final withLineBreaks = body
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</(?:p|div|li|h[1-6]|ul|ol|blockquote|pre)>', caseSensitive: false), '\n');
    return html.parseFragment(withLineBreaks).text?.trim() ?? '';
  }

  static bool _isRedirect(int statusCode) {
    return statusCode == HttpStatus.movedPermanently ||
        statusCode == HttpStatus.found ||
        statusCode == HttpStatus.seeOther ||
        statusCode == HttpStatus.temporaryRedirect ||
        statusCode == HttpStatus.permanentRedirect;
  }

  static String? _tagFromReleaseUrl(Uri? uri) {
    if (uri == null) return null;
    final segments = uri.pathSegments;
    for (var i = 0; i + 2 < segments.length; i++) {
      if (segments[i] == 'releases' && segments[i + 1] == 'tag') {
        return segments[i + 2];
      }
    }
    return null;
  }
}
