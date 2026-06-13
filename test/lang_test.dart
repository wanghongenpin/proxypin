import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/lang.dart';

void main() {
  group('ListFirstWhere extension', () {
    test('firstWhereOrNull returns matching element', () {
      var list = [1, 2, 3, 4, 5];
      expect(list.firstWhereOrNull((e) => e > 3), 4);
    });

    test('firstWhereOrNull returns null when no match', () {
      var list = [1, 2, 3];
      expect(list.firstWhereOrNull((e) => e > 10), null);
    });

    test('elementAtOrElse returns element at valid index', () {
      var list = ['a', 'b', 'c'];
      expect(list.elementAtOrElse(1, (i) => 'default'), 'b');
    });

    test('elementAtOrElse returns default for out-of-bounds index', () {
      var list = ['a', 'b'];
      expect(list.elementAtOrElse(5, (i) => 'default'), 'default');
    });

    test('elementAtOrElse returns default for negative index', () {
      var list = ['a', 'b'];
      expect(list.elementAtOrElse(-1, (i) => 'default'), 'default');
    });
  });

  group('JSON utility', () {
    test('pretty formats valid JSON', () {
      var result = JSON.pretty('{"a":1,"b":[1,2,3]}');
      expect(result, contains('"a": 1'));
      expect(result, contains('"b": ['));
    });

    test('pretty returns original for invalid JSON', () {
      var invalid = 'not json at all';
      expect(JSON.pretty(invalid), invalid);
    });

    test('compact minifies JSON', () {
      var pretty = '{\n  "a": 1,\n  "b": 2\n}';
      var result = JSON.compact(pretty);
      expect(result, '{"a":1,"b":2}');
    });

    test('compact returns original for invalid JSON', () {
      var invalid = 'invalid';
      expect(JSON.compact(invalid), invalid);
    });
  });

  group('StringEnhance extension', () {
    test('removePrefix removes matching prefix', () {
      expect('hello world'.removePrefix('hello '), 'world');
    });

    test('removePrefix returns unchanged if no match', () {
      expect('hello world'.removePrefix('xyz'), 'hello world');
    });

    test('splitFirst splits at first occurrence', () {
      var result = 'key: value: extra'.splitFirst(':'.codeUnitAt(0));
      expect(result.length, 2);
      expect(result[0], 'key');
      expect(result[1], 'value: extra');
    });

    test('splitFirst returns single element when delimiter absent', () {
      var result = 'nodelimiter'.splitFirst(':'.codeUnitAt(0));
      expect(result.length, 1);
      expect(result[0], 'nodelimiter');
    });

    test('camelCaseToSpaced converts camelCase', () {
      expect('camelCase'.camelCaseToSpaced(), 'camel case');
      expect('myVariableName'.camelCaseToSpaced(), 'my variable name');
    });
  });

  group('Strings utility', () {
    test('splitFirst splits at first pattern', () {
      var result = Strings.splitFirst('key=value=extra', '=');
      expect(result?.key, 'key');
      expect(result?.value, 'value=extra');
    });

    test('splitFirst returns null when pattern not found', () {
      var result = Strings.splitFirst('noequals', '=');
      expect(result, null);
    });

    test('trimWrap trims matching wrap characters', () {
      expect(Strings.trimWrap('"hello"', '"'), 'hello');
      expect(Strings.trimWrap("'test'", "'"), 'test');
    });

    test('trimWrap returns unchanged if wrap does not match', () {
      expect(Strings.trimWrap('hello', '"'), 'hello');
      expect(Strings.trimWrap('"hello', '"'), '"hello');
    });
  });

  group('ValueWrap', () {
    test('of creates with value', () {
      var wrap = ValueWrap.of(42);
      expect(wrap.get(), 42);
      expect(wrap.isNull(), false);
    });

    test('default constructor is null', () {
      var wrap = ValueWrap<int>();
      expect(wrap.get(), null);
      expect(wrap.isNull(), true);
    });

    test('set updates value', () {
      var wrap = ValueWrap<String>();
      wrap.set('hello');
      expect(wrap.get(), 'hello');
    });
  });

  group('Maps utility', () {
    test('getKey returns key for matching value', () {
      var map = {'a': 1, 'b': 2, 'c': 3};
      expect(Maps.getKey(map, 2), 'b');
    });

    test('getKey returns null for missing value', () {
      var map = {'a': 1, 'b': 2};
      expect(Maps.getKey(map, 99), null);
    });
  });

  group('CapacityList', () {
    test('stores items up to capacity', () {
      var list = CapacityList<int>(3);
      list.add(1);
      list.add(2);
      list.add(3);
      expect(list.list, [1, 2, 3]);
    });

    test('evicts oldest when capacity exceeded', () {
      var list = CapacityList<int>(3);
      list.add(1);
      list.add(2);
      list.add(3);
      list.add(4);
      expect(list.list, [2, 3, 4]);
    });

    test('remove removes specific item', () {
      var list = CapacityList<int>(5);
      list.add(1);
      list.add(2);
      list.add(3);
      list.remove(2);
      expect(list.list, [1, 3]);
    });

    test('clear empties list', () {
      var list = CapacityList<int>(5);
      list.add(1);
      list.add(2);
      list.clear();
      expect(list.list, isEmpty);
    });
  });

  group('Pair', () {
    test('holds key and value', () {
      var pair = Pair('name', 42);
      expect(pair.key, 'name');
      expect(pair.value, 42);
    });

    test('value is mutable', () {
      var pair = Pair('k', 1);
      pair.value = 99;
      expect(pair.value, 99);
    });
  });
}
