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

    test('selectAll selects every visible id and enters selection mode', () {
      final controller = MultiSelectController();

      controller.selectAll(['a', 'b', 'c']);

      expect(controller.isSelectionMode, isTrue);
      expect(controller.selectedIds, {'a', 'b', 'c'});
      expect(controller.selectedCount, 3);
    });

    test('selectAll replaces previous selection', () {
      final controller = MultiSelectController();
      controller.selectOnly('a');

      controller.selectAll(['b', 'c']);

      expect(controller.selectedIds, {'b', 'c'});
    });

    test('selectAll ignores empty ids', () {
      final controller = MultiSelectController();
      controller.selectOnly('a');

      controller.selectAll(const []);

      expect(controller.selectedIds, {'a'});
      expect(controller.isSelectionMode, isTrue);
    });

    test('toggleSelectAll selects all when partially selected', () {
      final controller = MultiSelectController();
      controller.selectOnly('a');

      controller.toggleSelectAll(['a', 'b', 'c']);

      expect(controller.selectedIds, {'a', 'b', 'c'});
    });

    test('toggleSelectAll clears selection but keeps selection mode when all selected', () {
      final controller = MultiSelectController();
      controller.selectAll(['a', 'b', 'c']);

      controller.toggleSelectAll(['a', 'b', 'c']);

      expect(controller.isSelectionMode, isTrue);
      expect(controller.selectedIds, isEmpty);
    });

    test('clearSelection empties selection without leaving selection mode', () {
      final controller = MultiSelectController();
      controller.selectAll(['a', 'b']);

      controller.clearSelection();

      expect(controller.isSelectionMode, isTrue);
      expect(controller.selectedIds, isEmpty);

      // 保留模式下可继续手动勾选
      controller.toggle('a');
      expect(controller.selectedIds, {'a'});
    });

    test('toggleSelectAll on empty list keeps current selection', () {
      final controller = MultiSelectController();
      controller.selectOnly('a');

      controller.toggleSelectAll(const []);

      expect(controller.selectedIds, {'a'});
    });
  });
}

