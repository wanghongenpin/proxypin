import 'dart:io';

/// 系统字体探测（目前只用于「代码字体」下拉框）
class SystemFonts {
  SystemFonts._();

  static List<String>? _monospaceCache;

  /// 常见等宽字体：fontconfig 不可用时兜底
  static const List<String> commonMonospace = [
    'JetBrains Mono',
    'Fira Code',
    'Cascadia Code',
    'Source Code Pro',
    'IBM Plex Mono',
    'Hack',
    'Inconsolata',
    'Victor Mono',
    'Roboto Mono',
    'Ubuntu Mono',
    'DejaVu Sans Mono',
    'Liberation Mono',
    'Noto Sans Mono',
    'Sarasa Mono SC',
    'Consolas',
    'Menlo',
    'Monaco',
    'Courier New',
  ];

  /// 「系统等宽」对应的字体族：各平台的通用等宽别名
  static String get systemMonospaceFamily {
    if (Platform.isMacOS) {
      return 'Menlo';
    }
    if (Platform.isWindows) {
      return 'Consolas';
    }
    return 'monospace';
  }

  static List<String>? _allCache;

  /// 已安装的全部字体族（界面字体设置用；fontconfig 不可用时返回常见字体）
  static Future<List<String>> families() async {
    final cached = _allCache;
    if (cached != null) {
      return cached;
    }

    final families = <String>{};
    if (Platform.isLinux) {
      try {
        final result = await Process.run('fc-list', [':', 'family']);
        if (result.exitCode == 0) {
          for (final line in result.stdout.toString().split('\n')) {
            for (final name in line.split(',')) {
              final family = name.trim();
              if (family.isNotEmpty) {
                families.add(family);
              }
            }
          }
        }
      } catch (_) {
        // ignore：走下面的兜底列表
      }
    }

    if (families.isEmpty) {
      families.addAll(const [
        'Noto Sans',
        'Noto Sans CJK SC',
        'Source Han Sans SC',
        'Sarasa Gothic SC',
        'DejaVu Sans',
        'Liberation Sans',
        'Segoe UI',
        'Microsoft YaHei',
        'PingFang SC',
        'Helvetica Neue',
      ]);
    }
    final list = families.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _allCache = list;
    return list;
  }

  /// 已安装的等宽字体族（Linux 用 fontconfig 枚举，其它平台返回常见列表）
  static Future<List<String>> monospaceFamilies() async {
    final cached = _monospaceCache;
    if (cached != null) {
      return cached;
    }

    final families = <String>{};
    if (Platform.isLinux) {
      try {
        final result = await Process.run('fc-list', [':spacing=mono', 'family']);
        if (result.exitCode == 0) {
          for (final line in result.stdout.toString().split('\n')) {
            for (final name in line.split(',')) {
              final family = name.trim();
              if (family.isNotEmpty) {
                families.add(family);
              }
            }
          }
        }
      } catch (_) {
        // fc-list 不可用就走常见列表
      }
    }

    if (families.isEmpty) {
      families.addAll(commonMonospace);
    }
    final list = families.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _monospaceCache = list;
    return list;
  }
}
