import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/storage/histories.dart';

HistoryItem _history(String name, String path) {
  return HistoryItem(name, path, 1, 1024);
}

void main() {
  group('pickHistoriesByIds', () {
    final first = _history('first', '/home/history/1700000000001.txt');
    final second = _history('second', '/home/history/1700000000002.txt');
    // 非时间戳命名：stableId 退化为 path.hashCode
    final legacy = _history('legacy', '/home/history/legacy-name.txt');
    final items = [first, second, legacy];

    test('returns empty list when stableIds is empty', () {
      expect(pickHistoriesByIds(items, <int>{}), isEmpty);
    });

    test('ignores unknown ids', () {
      final result = pickHistoriesByIds(items, {999, -1});

      expect(result, isEmpty);
    });

    test('picks matching items and keeps source order', () {
      final result = pickHistoriesByIds(items, {second.stableId, first.stableId});

      expect(result, [first, second]);
    });

    test('resolves hashCode fallback id for non-timestamp filenames', () {
      final result = pickHistoriesByIds(items, {legacy.stableId});

      expect(result, [legacy]);
      expect(result.single.stableId, legacy.path.hashCode);
    });

    test('mixes timestamp ids and hashCode fallback ids in one call', () {
      final result = pickHistoriesByIds(items, {first.stableId, legacy.stableId});

      expect(result, [first, legacy]);
    });

    test('is safe against index shifts: same id set on reordered list resolves same sessions', () {
      // 删除中间项后列表重排，历史页仍持有旧的 stableId 集合
      final reordered = [legacy, first];
      final selectedBeforeReorder = {first.stableId, second.stableId, legacy.stableId};

      final before = pickHistoriesByIds(items, selectedBeforeReorder);
      final after = pickHistoriesByIds(reordered, selectedBeforeReorder);

      expect(before.map((item) => item.stableId),
          containsAll([first.stableId, second.stableId, legacy.stableId]));
      // second 已被删除，不会错位命中其他会话；first/legacy 仍按 id 精确命中
      expect(after, [legacy, first]);
      expect(after.map((item) => item.stableId), isNot(contains(second.stableId)));
    });
  });
}
