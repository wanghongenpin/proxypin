import 'dart:io';

import 'package:proxypin/utils/lang.dart';

/// GitHub release 的单个资产（可下载文件）
class ReleaseAsset {
  final String name;
  final String downloadUrl;
  final int? size;

  ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    this.size,
  });

  /// 安装包类型(扩展名), 如 zip / dmg / exe
  String get installerType {
    final lower = name.toLowerCase();
    final dotIndex = lower.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == lower.length - 1) {
      return '';
    }
    return lower.substring(dotIndex + 1);
  }

  @override
  String toString() => 'ReleaseAsset(name: $name, size: $size)';
}

class RemoteVersionEntity {
  final String version;
  final String buildNumber;
  final String releaseTag;
  final bool preRelease;
  final String url;
  final String? content;
  final DateTime publishedAt;
  final List<ReleaseAsset> assets;

  RemoteVersionEntity({
    required this.version,
    required this.buildNumber,
    required this.releaseTag,
    required this.preRelease,
    required this.url,
    this.content,
    required this.publishedAt,
    this.assets = const [],
  });

  /// 选择当前桌面平台最合适的可下载资产。
  /// macOS: 优先 mac/macos/darwin/osx 的 .zip, 否则 .dmg。
  /// Windows: 均优先 .zip 原地更新; 非 Win7 没有 zip 时回退到 setup.exe。
  /// 其它平台返回 null(走打开链接的旧逻辑)。
  ReleaseAsset? desktopAsset() {
    if (assets.isEmpty) return null;

    bool nameMatches(ReleaseAsset a, List<String> keywords) {
      final lower = a.name.toLowerCase();
      return keywords.any((k) => lower.contains(k));
    }

    if (Platform.isMacOS) {
      final zip = assets.where((a) => a.installerType == 'zip' && nameMatches(a, ['mac', 'macos', 'darwin', 'osx']));
      if (zip.isNotEmpty) return zip.first;
      final dmg = assets.where((a) => a.installerType == 'dmg');
      if (dmg.isNotEmpty) return dmg.first;
      return null;
    }

    if (Platform.isWindows) {
      // Win7 检测: Windows 6.x 开头为 Win7 / Win8 (含 6.1=Win7)
      final isWin7 = Platform.operatingSystemVersion.startsWith('Windows 6.');
      final zips = assets.where((a) => a.installerType == 'zip' && nameMatches(a, ['win', 'windows']));
      if (isWin7) {
        // Win7: 优先 win7 专用 zip, 无则回退到任意 windows zip
        final win7Zip = zips.where((a) => nameMatches(a, ['windows7', 'win7']));
        if (win7Zip.isNotEmpty) return win7Zip.first;
        if (zips.isNotEmpty) return zips.first;
        return null;
      }
      // 非 Win7: 优先非 win7 的 windows zip, 无则回退到 setup.exe
      final nonWin7 = zips.where((a) => !nameMatches(a, ['windows7', 'win7']));
      if (nonWin7.isNotEmpty) return nonWin7.first;
      final exe = assets.where((a) => a.installerType == 'exe' && nameMatches(a, ['setup']));
      if (exe.isNotEmpty) return exe.first;
      return null;
    }

    return null;
  }

  @override
  String toString() {
    return 'RemoteVersionEntity(version: $version, buildNumber: $buildNumber, releaseTag: $releaseTag, preRelease: $preRelease, url: $url, publishedAt: $publishedAt, assets: ${assets.length})';
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

    // release body 格式: "iOS/Google 链接 + V版本号 + 中文列表 + English: + 英文列表"
    // 中文环境取中文段, 其它取英文段; 没有分隔符时原样返回。
    final bodyParts = json['body']?.toString().split("English: ");
    String? content;
    if (bodyParts != null && bodyParts.isNotEmpty) {
      final isCN = Platform.localeName.startsWith('zh');
      content = _cleanReleaseBody(isCN ? bodyParts.first : bodyParts.last);
    }

    final assetsJson = json['assets'] as List? ?? const [];
    final assets = assetsJson
        .whereType<Map<String, dynamic>>()
        .map((e) => ReleaseAsset(
              name: e['name'] as String? ?? '',
              downloadUrl: e['browser_download_url'] as String? ?? '',
              size: (e['size'] as num?)?.toInt(),
            ))
        .where((a) => a.name.isNotEmpty && a.downloadUrl.isNotEmpty)
        .toList();

    return RemoteVersionEntity(
        version: version,
        buildNumber: buildNumber,
        releaseTag: fullTag,
        preRelease: preRelease,
        url: json["html_url"] as String,
        content: content,
        publishedAt: publishedAt,
        assets: assets);
  }

  /// 清理 release 说明: 去掉顶部的商店下载链接行(iOS App Store / Google Play 等),
  /// 从第一个 "V版本号" 标题开始保留; 若无版本标题则去掉含 http 链接的行。
  static String _cleanReleaseBody(String raw) {
    final lines = raw.replaceAll('\r\n', '\n').split('\n');

    // 优先从 "V1.2.9" 这类版本标题处截断
    final versionHeader = RegExp(r'^\s*[vV]\d+(\.\d+)+');
    final startIndex = lines.indexWhere((l) => versionHeader.hasMatch(l));
    if (startIndex >= 0) {
      return lines.sublist(startIndex).join('\n').trim();
    }

    // 兜底: 丢掉包含链接的行
    final filtered = lines.where((l) => !l.contains('http')).join('\n');
    return filtered.trim();
  }
}
