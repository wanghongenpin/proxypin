import 'dart:io';

abstract class Constants {
  static const githubUrl = "https://github.com/wanghongenpin/proxypin";
  static const githubReleasesApiUrl = "https://api.github.com/repos/wanghongenpin/proxypin/releases";
  static const githubLatestReleaseUrl = "https://github.com/wanghongenpin/proxypin/releases/latest";
  static const githubReleasesFeedUrl = "https://github.com/wanghongenpin/proxypin/releases.atom";

  static const String ignoreReleaseVersionKey = "ignored_release_version";

  /// GitHub 下载镜像前缀，仅中文环境使用。
  /// 设为空字符串可关闭镜像。
  static const githubMirror = "https://ghproxy.top/";

  /// 返回主 URL 和镜像 URL（仅中文环境有镜像）。
  /// 主 URL 在前，镜像在后，下载时优先直连。
  static List<String> mirrorUrls(String url) {
    final urls = <String>[url];
    if (githubMirror.isEmpty) return urls;
    if (!Platform.localeName.startsWith('zh')) return urls;
    final uri = Uri.tryParse(url);
    if (uri == null) return urls;
    if (uri.host == 'github.com' || uri.host == 'api.github.com') {
      urls.add('$githubMirror$url');
    }
    return urls;
  }
}

const kAnimationDuration = Duration(milliseconds: 250);
