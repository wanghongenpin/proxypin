import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/ui/content/panel.dart';

/// 与 panel.dart 中 _overviewChromeHeight 保持一致：
/// ListView 上下内边距(2+12) + 卡间距(12) + 预览卡头(36+1) = 63
const double chromeHeight = 63;

void main() {
  group('responsePreviewMaxHeight with measured info card', () {
    test('fills all remaining viewport space below the info card', () {
      // 视口 950、信息卡 260：预览滚动区 = 950 - 260 - 63 = 627，底部无留白
      expect(responsePreviewMaxHeight(950, infoCardHeight: 260), closeTo(627, 1e-9));
      expect(responsePreviewMaxHeight(600, infoCardHeight: 260), closeTo(277, 1e-9));
    });

    test('never goes below the 120 floor, outer ListView scrolls instead', () {
      // 剩余空间为负时回落到下限
      expect(responsePreviewMaxHeight(400, infoCardHeight: 350), 120);
      expect(responsePreviewMaxHeight(300, infoCardHeight: 500), 120);
    });
  });

  group('responsePreviewMaxHeight first-frame fallback', () {
    test('uses 45% of viewport clamped between 120 and the 520 cap', () {
      expect(responsePreviewMaxHeight(800), closeTo(360, 1e-9));
      expect(responsePreviewMaxHeight(1080), closeTo(486, 1e-9));
      expect(responsePreviewMaxHeight(1200), ResponsePreviewCard.maxHeightCap);
      expect(responsePreviewMaxHeight(600), closeTo(270, 1e-9));
      expect(responsePreviewMaxHeight(200), 120);
    });

    test('unbounded height falls back to the cap', () {
      expect(responsePreviewMaxHeight(double.infinity), ResponsePreviewCard.maxHeightCap);
    });
  });
}
