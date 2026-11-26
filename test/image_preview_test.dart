import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/ui/component/image_preview.dart';

void main() {
  test('sniffFormat recognizes private / modern image formats', () {
    expect(ImageBodyPreview.sniffFormat('wxgf'.codeUnits + [1, 2, 3]), contains('WXAM'));
    expect(ImageBodyPreview.sniffFormat([0, 0, 0, 0x1c] + 'ftypavif'.codeUnits), 'AVIF');
    expect(ImageBodyPreview.sniffFormat([0, 0, 0, 0x18] + 'ftypheic'.codeUnits), 'HEIF / HEIC');
    expect(ImageBodyPreview.sniffFormat([0xFF, 0xD8, 0xFF, 0xE0]), 'JPEG');
    expect(ImageBodyPreview.sniffFormat([1, 2, 3]), isNull);
  });

  testWidgets('undecodable image shows a fallback instead of blank', (tester) async {
    final bytes = 'wxgf'.codeUnits + List.filled(200, 7);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ImageBodyPreview(bytes, contentType: 'image/wxpic'))));
    // 让图片解码在真实异步中失败
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 500)));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.textContaining('image/wxpic'), findsOneWidget);
    expect(find.textContaining('WXAM'), findsOneWidget);
  });
}
