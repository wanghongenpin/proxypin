import 'dart:collection';

/// Uri构建工具类
class UriBuild {
  /// 构建Uri
  static Uri build(String url, {Map<String, String>? params}) {
    var uri = Uri.parse(url);
    if (params == null) {
      return uri;
    }
    var queries = HashMap<String, String>();
    queries.addAll(uri.queryParameters);
    queries.addAll(params);

    return uri.replace(queryParameters: queries);
  }
}

class UriUtils {
  //map转url参数
  static String mapToQuery(Map<String, dynamic>? map) {
    if (map == null) {
      return '';
    }
    List<String> list = [];
    map.forEach((key, value) {
      list.add('$key=${Uri.encodeComponent(value.toString())}');
    });
    return list.join('&');
  }
}
