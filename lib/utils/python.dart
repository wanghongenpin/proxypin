import 'package:proxypin/network/http/http.dart';

// 复制为 Python Requests 请求
String copyAsPythonRequests(HttpRequest request) {
  var sb = StringBuffer();
  sb.writeln("import requests\n");

  String url = request.requestUrl;
  List<String> headers = request.headers.entries
      .where((entry) => entry.key.toLowerCase() != 'content-length')
      .map((entry) => '${entry.key}: ${entry.value}')
      .toList();
  String method = request.method.name.toLowerCase();

  sb.write('url = "${escapeQuotes(url)}"\n');
  bool cookiesExist = processCookies(sb, headers);
  sb.write('headers = {');
  processHeaders(sb, headers);
  sb.writeln('}');

  String? body = processBody(request);
  if (body != null) {
    sb.writeln(body);
  }

  sb.write('\nres = requests.$method(url, headers=headers');
  if (cookiesExist) {
    sb.write(', cookies=cookies');
  }
  if (body != null) {
    sb.write(', data=data');
  }
  sb.writeln(')');
  sb.writeln('print(res.text)');

  return sb.toString();
}

// 转义引号
String escapeQuotes(String input) {
  return input.replaceAll('"', r'\"');
}

// 处理 cookie
bool processCookies(StringBuffer py, List<String> headers) {
  bool cookiesExist = false;
  for (String header in headers) {
    if (header.toLowerCase().startsWith("cookie:")) {
      py.write('cookies = {\n');
      var cookies = header.substring(9, header.length - 1).trim().split(';');
      for (var cookie in cookies) {
        var parts = cookie.split('=');
        if (parts.length == 2) {
          py.writeln('  "${parts[0].trim()}": "${parts[1].trim()}",');
        }
      }
      py.writeln('}\n');
      cookiesExist = true;
      break;
    }
  }
  return cookiesExist;
}

// 处理header
void processHeaders(StringBuffer py, List<String> headers) {
  bool first = true;
  for (String header in headers) {
    if (!header.toLowerCase().startsWith("cookie:")) {
      if (!first) {
        py.write(',\n  ');
      } else {
        py.write('\n  ');
        first = false;
      }
      var parts = header.split(':');
      py.write('"${parts[0].trim()}": "${escapeQuotes(parts[1].substring(2, parts[1].length - 1).trim())}"');
    }
  }
  if (!first) {
    py.write('\n');
  }
}

// 处理body
String? processBody(HttpRequest request) {
  if (request.body!.isNotEmpty) {
    return 'data = """${escapeQuotes(request.bodyAsString)}"""';
  }
  return null;
}
