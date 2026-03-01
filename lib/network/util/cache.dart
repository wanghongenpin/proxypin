/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:async';
import 'dart:collection';

/// A cache that expires entries after a given duration.
/// The cache uses a timer to remove entries after the specified duration.
/// @author WangHongEn
class ExpiringCache<K, V> {
  final Duration duration;
  final _cache = <K, V>{};
  final _expirationTimes = <K, Timer>{};

  ExpiringCache(this.duration);

  void set(K key, V value) {
    _expirationTimes[key]?.cancel();
    _cache[key] = value;
    _expirationTimes[key] = Timer(duration, () => remove(key));
  }

  void operator []=(K key, V value) => set(key, value);

  V? putIfAbsent(K key, V Function() ifAbsent) {
    if (_cache.containsKey(key)) {
      return _cache[key];
    }
    final value = ifAbsent();
    set(key, value);
    return value;
  }

  bool containsKey(K key) {
    return _cache.containsKey(key);
  }

  V? get(K key) {
    return _cache[key];
  }

  V? operator [](K key) => get(key);

  V? remove(K key) {
    _expirationTimes[key]?.cancel();
    _expirationTimes.remove(key);
    return _cache.remove(key);
  }

  void clear() {
    for (var timer in _expirationTimes.values) {
      timer.cancel();
    }
    _expirationTimes.clear();
    _cache.clear();
  }
}

class LruCache<K, V> {
  final int capacity;
  final _cache = LinkedHashMap<K, V>();

  LruCache(this.capacity);

  V? get(K key) {
    if (!_cache.containsKey(key)) {
      return null;
    }

    // Move the accessed key to the end to show that it was recently used
    final value = _cache.remove(key);
    _cache[key] = value as V;
    return value;
  }

  V pubIfAbsent(K key, V Function() ifAbsent) {
    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    final value = ifAbsent();
    set(key, value);
    return value;
  }

  void set(K key, V value) {
    if (_cache.containsKey(key)) {
      // Remove the old value
      _cache.remove(key);
    } else if (_cache.length == capacity) {
      // Remove the first key (least recently used)
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }

  void remove(K key) {
    _cache.remove(key);
  }

  int get length => _cache.length;

  void clear() {
    _cache.clear();
  }
}
