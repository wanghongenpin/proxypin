/*
 * Copyright 2023 Hongen Wang
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
abstract class ListenerListEvent<T> {
  /// 监听的源
  sourceAware(List<T> source) {}

  void onAdd(T item);

  void onRemove(T item);

  void onUpdate(T item) {}

  void onBatchRemove(List<T> items);

  clear();
}

class OnchangeListEvent<T> extends ListenerListEvent<T> {
  final Function onChange;

  OnchangeListEvent(this.onChange);

  @override
  void onAdd(T item) => onChange.call();

  @override
  void onRemove(T item) => onChange.call();

  @override
  void onUpdate(T item) => onChange.call();

  @override
  void onBatchRemove(List<T> items) => onChange.call();

  @override
  clear() => onChange.call();
}

/// 可监听list
/// @author wanghongen
/// 2024/01/30
class ListenableList<T> extends Iterable<T> {
  List<T> source = [];
  final List<ListenerListEvent<T>> _listeners = [];

  ListenableList([List<T>? source]) {
    if (source != null) this.source = source;
  }

  addListener(ListenerListEvent<T> listener) {
    if (_listeners.contains(listener)) return;
    listener.sourceAware(source);
    _listeners.add(listener);
  }

  removeListener(ListenerListEvent<T> listener) {
    _listeners.remove(listener);
  }

  @override
  int get length => source.length;

  @override
  bool get isEmpty => source.isEmpty;

  int indexOf(T item) => source.indexOf(item);

  @override
  T elementAt(int index) => source[index];

  List<T> sublist(int start, [int? end]) {
    return source.sublist(start, end);
  }

  void removeRange(start, end) {
    source.removeRange(start, end > source.length ? source.length : end);
    for (var element in _listeners) {
      element.clear();
    }
  }

  update(int index, T item) {
    source[index] = item;
    for (var element in _listeners) {
      element.onUpdate(item);
    }
  }

  add(T item) {
    source.add(item);
    for (var element in _listeners) {
      element.onAdd(item);
    }
  }

  bool remove(T item) {
    var remove = source.remove(item);
    if (remove) {
      for (var element in _listeners) {
        element.onRemove(item);
      }
    }
    return remove;
  }

  T removeAt(int index) {
    var item = source.removeAt(index);
    if (item != null) {
      for (var element in _listeners) {
        element.onRemove(item);
      }
    }
    return item;
  }

  clear() {
    source.clear();
    for (var element in _listeners) {
      element.clear();
    }
  }

  removeWhere(bool Function(T element) test) {
    var list = <T>[];
    source.removeWhere((it) {
      if (test.call(it)) {
        list.add(it);
        return true;
      }
      return false;
    });
    if (list.isEmpty) return;

    for (var element in _listeners) {
      element.onBatchRemove(list);
    }
  }

  @override
  Iterator<T> get iterator => source.iterator;
}
