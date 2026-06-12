import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/ui/component/search/search_controller.dart';

void main() {
  group('SearchTextController', () {
    test('updateMatchCount keeps ValueNotifier state in sync with currentMatchIndex', () {
      final controller = SearchTextController();

      controller.currentMatchIndex.value = 5;
      controller.updateMatchCount(2);

      expect(controller.currentMatchIndex.value, 1);
      expect(controller.value.currentMatchIndex, 1);

      controller.updateMatchCount(0);

      expect(controller.currentMatchIndex.value, 0);
      expect(controller.value.currentMatchIndex, 0);

      controller.dispose();
    });
  });
}

