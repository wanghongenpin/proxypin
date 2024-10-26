dynamic getFirstElement(List? list) {
  return list?.firstOrNull;
}

///获取list元素类型
/// @author wanghongen
class Lists {
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
