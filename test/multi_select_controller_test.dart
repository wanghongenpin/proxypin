import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';

void main() {
  group('MultiSelectController', () {
    test('toggle enables and clears selection mode', () {
      final controller = MultiSelectController();

      controller.toggle('a');
      expect(controller.isSelectionMode, isTrue);
      expect(controller.selectedIds, {'a'});

      controller.toggle('a');
      expect(controller.isSelectionMode, isFalse);
      expect(controller.selectedIds, isEmpty);
    });

    test('selectRange uses anchor item', () {
      final controller = MultiSelectController();
      controller.selectOnly('b');

      controller.selectRange(['a', 'b', 'c', 'd'], 'd');

      expect(controller.selectedIds, {'b', 'c', 'd'});
    });

    test('prune keeps only visible ids', () {
      final controller = MultiSelectController();

      controller.selectOnly('b');
      controller.selectRange(['a', 'b', 'c', 'd'], 'c');
      controller.prune(['b', 'c', 'd']);

      expect(controller.isSelectionMode, isTrue);
      expect(controller.selectedIds, {'b', 'c'});
    });

    test('prune clears selection mode when all selected ids disappear', () {
      final controller = MultiSelectController();

      controller.prune(['c']);

      expect(controller.isSelectionMode, isFalse);
      expect(controller.selectedIds, isEmpty);
    });
  });
}

