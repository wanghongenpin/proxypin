import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 响应图片预览：解码失败（私有 / 不支持的格式）时显示格式、大小与查看方式，而不是一片空白。
class ImageBodyPreview extends StatelessWidget {
  final List<int> bytes;
  final String? contentType;

  const ImageBodyPreview(this.bytes, {super.key, this.contentType});

  /// 按文件头识别常见格式，便于说明为何无法预览
  static String? sniffFormat(List<int> b) {
    bool at(int offset, List<int> sig) {
      if (b.length < offset + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[offset + i] != sig[i]) return false;
      }
      return true;
    }

    if (at(0, 'wxgf'.codeUnits)) return '微信私有格式 WXAM（wxgf，基于 HEVC）';
    if (at(4, 'ftyp'.codeUnits)) {
      final brand = b.length >= 12 ? String.fromCharCodes(b.sublist(8, 12)) : '';
      if (brand.startsWith('avi')) return 'AVIF';
      if (brand.startsWith('hei') || brand.startsWith('mif') || brand.startsWith('hev')) return 'HEIF / HEIC';
      return 'ISO BMFF ($brand)';
    }
    if (at(0, 'TPG'.codeUnits)) return '腾讯 TPG';
    if (at(0, [0x89, 0x50, 0x4E, 0x47])) return 'PNG';
    if (at(0, [0xFF, 0xD8, 0xFF])) return 'JPEG';
    if (at(0, 'GIF8'.codeUnits)) return 'GIF';
    if (at(0, 'RIFF'.codeUnits) && at(8, 'WEBP'.codeUnits)) return 'WebP';
    if (at(0, '<svg'.codeUnits) || at(0, '<?xml'.codeUnits)) return 'SVG';
    return null;
  }

  static String _size(int n) =>
      n < 1024 ? '$n B' : (n < 1024 * 1024 ? '${(n / 1024).toStringAsFixed(1)} KB' : '${(n / 1048576).toStringAsFixed(1)} MB');

  @override
  Widget build(BuildContext context) {
    final data = bytes is Uint8List ? bytes as Uint8List : Uint8List.fromList(bytes);
    return Center(
        child: Image.memory(data,
            fit: BoxFit.scaleDown,
            errorBuilder: (context, error, stack) => _fallback(context, data)));
  }

  Widget _fallback(BuildContext context, Uint8List data) {
    final theme = Theme.of(context);
    final isCN = Localizations.localeOf(context).languageCode == 'zh';
    final format = sniffFormat(data);
    final head = data.take(16).map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
    final hint = TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.broken_image_outlined, size: 36, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(isCN ? '无法预览该图片格式' : 'Image format not supported for preview',
              style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          SelectableText(
              [
                if (contentType != null) contentType!,
                if (format != null) format,
                _size(data.length),
              ].join(' · '),
              textAlign: TextAlign.center,
              style: hint),
          const SizedBox(height: 4),
          SelectableText(head, style: hint.copyWith(fontFamily: 'monospace')),
          const SizedBox(height: 6),
          Text(
              isCN
                  ? '数据已完整抓到，可切换到 Hex 查看原始字节，或导出后用支持该格式的工具打开'
                  : 'The data was captured in full: view raw bytes in Hex, or export it to a tool that supports the format',
              textAlign: TextAlign.center,
              style: hint),
        ]));
  }
}
