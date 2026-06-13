import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/util/cache.dart';

void main() {
  group('LruCache', () {
    test('stores and retrieves values', () {
      var cache = LruCache<String, int>(3);
      cache.set('a', 1);
      cache.set('b', 2);
      expect(cache.get('a'), 1);
      expect(cache.get('b'), 2);
    });

    test('returns null for missing key', () {
      var cache = LruCache<String, int>(3);
      expect(cache.get('x'), null);
    });

    test('evicts LRU entry when capacity exceeded', () {
      var cache = LruCache<String, int>(2);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.set('c', 3);
      expect(cache.get('a'), null);
      expect(cache.get('b'), 2);
      expect(cache.get('c'), 3);
    });

    test('accessing moves entry to most recent', () {
      var cache = LruCache<String, int>(2);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.get('a'); // access 'a' making 'b' LRU
      cache.set('c', 3); // should evict 'b'
      expect(cache.get('b'), null);
      expect(cache.get('a'), 1);
      expect(cache.get('c'), 3);
    });

    test('pubIfAbsent inserts if absent', () {
      var cache = LruCache<String, int>(3);
      var value = cache.pubIfAbsent('x', () => 42);
      expect(value, 42);
      expect(cache.get('x'), 42);
    });

    test('pubIfAbsent returns existing value', () {
      var cache = LruCache<String, int>(3);
      cache.set('x', 10);
      var value = cache.pubIfAbsent('x', () => 42);
      expect(value, 10);
    });

    test('remove deletes entry', () {
      var cache = LruCache<String, int>(3);
      cache.set('a', 1);
      cache.remove('a');
      expect(cache.get('a'), null);
      expect(cache.length, 0);
    });

    test('clear empties cache', () {
      var cache = LruCache<String, int>(3);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.clear();
      expect(cache.length, 0);
    });
  });

  group('LruCacheSet', () {
    test('add returns true for new entries', () {
      var cache = LruCacheSet<String>(3);
      expect(cache.add('a'), true);
      expect(cache.add('b'), true);
    });

    test('add returns false for existing entries', () {
      var cache = LruCacheSet<String>(3);
      cache.add('a');
      expect(cache.add('a'), false);
    });

    test('evicts LRU entry when capacity exceeded', () {
      var cache = LruCacheSet<String>(2);
      cache.add('a');
      cache.add('b');
      cache.add('c');
      expect(cache.contains('a'), false);
      expect(cache.contains('b'), true);
      expect(cache.contains('c'), true);
    });

    test('re-adding moves to most recent', () {
      var cache = LruCacheSet<String>(2);
      cache.add('a');
      cache.add('b');
      cache.add('a'); // refresh 'a'
      cache.add('c'); // evicts 'b'
      expect(cache.contains('b'), false);
      expect(cache.contains('a'), true);
      expect(cache.contains('c'), true);
    });

    test('remove deletes entry', () {
      var cache = LruCacheSet<String>(3);
      cache.add('a');
      cache.remove('a');
      expect(cache.contains('a'), false);
    });

    test('removeAll removes multiple', () {
      var cache = LruCacheSet<String>(5);
      cache.add('a');
      cache.add('b');
      cache.add('c');
      cache.removeAll(['a', 'c']);
      expect(cache.contains('a'), false);
      expect(cache.contains('b'), true);
      expect(cache.contains('c'), false);
    });

    test('removeWhere with predicate', () {
      var cache = LruCacheSet<int>(5);
      cache.add(1);
      cache.add(2);
      cache.add(3);
      cache.add(4);
      cache.removeWhere((k) => k % 2 == 0);
      expect(cache.contains(2), false);
      expect(cache.contains(4), false);
      expect(cache.contains(1), true);
      expect(cache.contains(3), true);
    });
  });

  group('ExpiringCache', () {
    test('stores and retrieves values', () {
      var cache = ExpiringCache<String, int>(Duration(seconds: 10));
      cache.set('a', 1);
      expect(cache.get('a'), 1);
      expect(cache['a'], 1);
    });

    test('containsKey works', () {
      var cache = ExpiringCache<String, int>(Duration(seconds: 10));
      cache['x'] = 5;
      expect(cache.containsKey('x'), true);
      expect(cache.containsKey('y'), false);
    });

    test('remove deletes entry', () {
      var cache = ExpiringCache<String, int>(Duration(seconds: 10));
      cache.set('a', 1);
      cache.remove('a');
      expect(cache.get('a'), null);
    });

    test('clear empties cache', () {
      var cache = ExpiringCache<String, int>(Duration(seconds: 10));
      cache.set('a', 1);
      cache.set('b', 2);
      cache.clear();
      expect(cache.get('a'), null);
      expect(cache.get('b'), null);
    });

    test('putIfAbsent inserts if absent', () {
      var cache = ExpiringCache<String, int>(Duration(seconds: 10));
      var val = cache.putIfAbsent('x', () => 42);
      expect(val, 42);
    });

    test('putIfAbsent returns existing value', () {
      var cache = ExpiringCache<String, int>(Duration(seconds: 10));
      cache.set('x', 10);
      var val = cache.putIfAbsent('x', () => 42);
      expect(val, 10);
    });
  });
}
