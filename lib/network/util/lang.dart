import 'dart:typed_data';

dynamic getFirstElement(List? list) {
  return list?.firstOrNull;
}

///获取list元素类型
/// @author wanghongen
class Lists {
  static bool isNotEmpty(List? list) {
    return list != null && list.isNotEmpty;
  }

  static Type getElementType(dynamic list) {
    if (list == null || list.isEmpty || list is! List) {
      return Null;
    }

    var type = list.first.runtimeType;

    return type;
  }

  ///转换指定类型
  static List<T> convertList<T>(List list) {
    return list.map((e) => e as T).toList();
  }
}

class Strings {
  ///
  /// Splits the given String [s] in chunks with the given [chunkSize].
  ///
  static List<String> chunk(String s, int chunkSize) {
    var chunked = <String>[];
    for (var i = 0; i < s.length; i += chunkSize) {
      var end = (i + chunkSize < s.length) ? i + chunkSize : s.length;
      chunked.add(s.substring(i, end));
    }
    return chunked;
  }

  static bool isNotEmpty(String? s) {
    return s != null && s.isNotEmpty;
  }
}

class HexUtils {
  static String bytesToHex(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List decode(String hex) {
    var str = hex.replaceAll(" ", "");
    str = str.toLowerCase();
    if (str.length % 2 != 0) {
      str = "0$str";
    }
    var l = str.length ~/ 2;
    var result = Uint8List(l);
    for (var i = 0; i < l; ++i) {
      var x = int.parse(str.substring(i * 2, (2 * (i + 1))), radix: 16);
      if (x.isNaN) {
        throw ArgumentError('Expected hex string');
      }
      result[i] = x;
    }
    return result;
  }
}
