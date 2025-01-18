import 'dart:convert';

import 'package:date_format/date_format.dart';
import 'package:flutter/material.dart';

/// @author wanghongen
/// 2023/10/8
extension ListFirstWhere<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    try {
      return firstWhere(test);
    } on StateError {
      return null;
    }
  }
}

extension DateTimeFormat on DateTime {
  String format() {
    return formatDate(this, [yyyy, '-', mm, '-', dd, ' ', HH, ':', nn, ':', ss]);
  }

  String formatMillisecond() {
    return formatDate(this, [yyyy, '-', mm, '-', dd, ' ', HH, ':', nn, ':', ss, '.', SSS]);
  }

  String dateFormat() {
    return formatDate(this, [yyyy, '-', mm, '-', dd]);
  }

  String timeFormat() {
    return formatDate(this, [HH, ':', nn, ':', ss]);
  }
}

class JSON {
  ///  格式化json
  static String pretty(String jsonString) {
    try {
      var jsonObject = jsonDecode(jsonString);
      var encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(jsonObject);
    } catch (e) {
      return jsonString;
    }
  }

  /// 压缩json
  static String compact(String jsonString) {
    try {
      var jsonObject = jsonDecode(jsonString);
      return jsonEncode(jsonObject);
    } catch (e) {
      return jsonString;
    }
  }
}

class ValueWrap<V> {
  V? _v;

  ValueWrap();

  factory ValueWrap.of(V v) {
    var valueWrap = ValueWrap<V>();
    valueWrap._v = v;
    return valueWrap;
  }

  void set(V? v) => this._v = v;

  V? get() => this._v;

  bool isNull() => this._v == null;
}

class Strings {
  static MapEntry<String, String>? splitFirst(String str, Pattern pattern) {
    var index = str.indexOf(pattern);
    if (index > 0) {
      return MapEntry(str.substring(0, index), str.substring(index + 1));
    }

    return null;
  }

  static String trimWrap(String str, String wrap) {
    if (str.startsWith(wrap) && str.endsWith(wrap)) {
      return str.substring(1, str.length - 1);
    }
    return str;
  }

  ///防止文字自动换行
  static String autoLineString(String str) {
    return str.fixAutoLines();
  }
}

/// 防止文字自动换行
/// 当中英文混合，或者中文与数字或者特殊符号，或则英文单词时，文本会被自动换行，
/// 这样会导致，换行时上一行可能会留很大的空白区域
/// 把每个字符插入一个0宽的字符， \u{200B}
extension StringEnhance on String {
  String fixAutoLines() {
    return Characters(this).join('\u{200B}');
  }

  List<String> splitFirst(int code) {
    var index = codeUnits.indexOf(code);
    if (index == -1) {
      return [this];
    }
    var key = substring(0, index).trim();
    var value = substring(index + 1).trim();
    return [key, value];
  }

  String camelCaseToSpaced() {
    var input = this;
    return input.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (Match match) {
      return '${match.group(1)} ${match.group(2)}';
    }).toLowerCase();
  }
}

class Pair<K, V> {
  final K key;
  final V value;

  Pair(this.key, this.value);
}

class Maps {
  static K? getKey<K, V>(Map<K, V> map, V? value) {
    for (var entry in map.entries) {
      if (entry.value == value) {
        return entry.key;
      }
    }
    return null;
  }
}

/// 用于存储一些数据，当数据超过指定大小时，删除最早的数据
class CapacityList<T> {
  final int capacity;
  final List<T> list = [];

  CapacityList(this.capacity);

  void add(T value) {
    if (list.length >= capacity) {
      list.removeAt(0);
    }
    list.add(value);
  }

  void remove(T value) {
    list.remove(value);
  }

  void clear() {
    list.clear();
  }
}
