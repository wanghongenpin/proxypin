import 'package:proxypin/utils/lang.dart';

class RemoteVersionEntity {
  final String version;
  final String buildNumber;
  final String releaseTag;
  final bool preRelease;
  final String url;
  final String? content;
  final DateTime publishedAt;

  RemoteVersionEntity({
    required this.version,
    required this.buildNumber,
    required this.releaseTag,
    required this.preRelease,
    required this.url,
    this.content,
    required this.publishedAt,
  });

  @override
  String toString() {
    return 'RemoteVersionEntity(version: $version, buildNumber: $buildNumber, releaseTag: $releaseTag, preRelease: $preRelease, url: $url, publishedAt: $publishedAt)';
  }
}

abstract class GithubReleaseParser {
  static RemoteVersionEntity parse(Map<String, dynamic> json) {
    final fullTag = json['tag_name'] as String;
    final fullVersion = fullTag.removePrefix("v").split("-").first.split("+");
    var version = fullVersion.first;
    var buildNumber = fullVersion.elementAtOrElse(1, (index) => "");

    final preRelease = json["prerelease"] as bool;
    final publishedAt = DateTime.parse(json["published_at"] as String);

    var body = json['body']?.toString().split("English: ");
    return RemoteVersionEntity(
        version: version,
        buildNumber: buildNumber,
        releaseTag: fullTag,
        preRelease: preRelease,
        url: json["html_url"] as String,
        content: body?.last,
        publishedAt: publishedAt);
  }
}

