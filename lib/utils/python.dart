import 'dart:convert';

import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/utils/multipart.dart';

/// 复制为 Python Requests 请求
String copyAsPythonRequests(HttpRequest request) {
  final sb = StringBuffer();
  sb.writeln('import requests\n');

  // body 先解析，决定是否要去掉 Content-Type（json/data/files 时 requests 会自动生成）
  final body = _buildBody(request);

  final cookies = _extractCookies(request);
  // requests 的 headers 值只接受字符串；同名多值 header 按 RFC 7230 用逗号合并
  final headers = <String, String>{};
  request.headers.forEach((name, values) {
    final lower = name.toLowerCase();
    if (lower == 'content-length') return;
    if (lower == 'cookie') return;
    if (body.dropContentType && lower == 'content-type') return;
    headers[name] = values.join(', ');
  });

  sb.writeln("url = '${_pyStr(request.requestUrl)}'\n");

  if (cookies.isNotEmpty) {
    sb.writeln('cookies = {');
    cookies.forEach((name, value) {
      sb.writeln("    '${_pyStr(name)}': '${_pyStr(value)}',");
    });
    sb.writeln('}\n');
  }

  if (headers.isNotEmpty) {
    sb.writeln('headers = {');
    headers.forEach((name, value) {
      sb.writeln("    '${_pyStr(name)}': '${_pyStr(value)}',");
    });
    sb.writeln('}\n');
  }

  if (body.assignment != null) {
    sb.writeln('${body.assignment}\n');
  }

  final methodName = request.method.name;
  final methodLower = methodName.toLowerCase();
  final callArgs = <String>['url'];
  if (headers.isNotEmpty) callArgs.add('headers=headers');
  if (cookies.isNotEmpty) callArgs.add('cookies=cookies');
  if (body.callArg != null) callArgs.add(body.callArg!);

  sb.write('response = ');
  // requests 只为常见动词提供便捷方法；PROPFIND/REPORT 等走通用 request()
  if (_requestsShortcuts.contains(methodLower)) {
    sb.write('requests.$methodLower(');
  } else {
    sb.write("requests.request('$methodName', ");
  }
  sb.write(callArgs.join(', '));
  sb.writeln(')');
  sb.writeln('print(response.text)');

  return sb.toString();
}

const _requestsShortcuts = {'get', 'post', 'put', 'patch', 'delete', 'head', 'options'};

/// 从 Cookie 头中解析出所有 cookie。
Map<String, String> _extractCookies(HttpRequest request) {
  final cookies = <String, String>{};
  for (final header in request.headers.getList('Cookie') ?? const <String>[]) {
    for (final pair in header.split(';')) {
      final idx = pair.indexOf('=');
      if (idx <= 0) continue;
      final name = pair.substring(0, idx).trim();
      final value = pair.substring(idx + 1).trim();
      if (name.isNotEmpty) cookies[name] = value;
    }
  }
  return cookies;
}

/// 根据 Content-Type 把请求体转换成清晰的 Python 变量。
_PyBody _buildBody(HttpRequest request) {
  if (request.body?.isEmpty ?? true) return const _PyBody();

  final contentType = request.headers.contentType.toLowerCase();

  // JSON：解析后重新格式化为缩进的 Python 字面量
  if (contentType.contains('application/json') || contentType.contains('+json')) {
    final decoded = _tryJsonDecode(request.bodyAsString);
    if (decoded != null) {
      return _PyBody(
        assignment: 'json_data = ${_pyLiteral(decoded, 0)}',
        callArg: 'json=json_data',
        dropContentType: true,
      );
    }
  }

  // 表单：application/x-www-form-urlencoded
  if (contentType.contains('application/x-www-form-urlencoded')) {
    final form = <String, String>{};
    for (final pair in request.bodyAsString.split('&')) {
      if (pair.isEmpty) continue;
      final idx = pair.indexOf('=');
      final name = Uri.decodeQueryComponent(idx < 0 ? pair : pair.substring(0, idx));
      final value = Uri.decodeQueryComponent(idx < 0 ? '' : pair.substring(idx + 1));
      form[name] = value;
    }
    if (form.isNotEmpty) {
      return _PyBody(
        assignment: 'data = ${_pyLiteral(form, 0)}',
        callArg: 'data=data',
        dropContentType: true,
      );
    }
  }

  // multipart/form-data
  if (contentType.contains('multipart/form-data')) {
    final assignment = _buildMultipart(request);
    if (assignment != null) {
      return _PyBody(assignment: assignment, callArg: 'files=files', dropContentType: true);
    }
  }

  // 其他类型：能按 UTF-8 解码的当文本，否则按原始 bytes，避免二进制内容损坏
  final raw = request.body!;
  try {
    utf8.decode(raw); // 仅用于判断
    return _PyBody(assignment: "data = '${_pyStr(request.bodyAsString)}'", callArg: 'data=data');
  } catch (_) {
    return _PyBody(assignment: 'data = ${_pyBytes(raw)}', callArg: 'data=data');
  }
}

/// 用 [Multipart.parse] 解析 body 为 requests 的 files 字典；无法解析时返回 null。
String? _buildMultipart(HttpRequest request) {
  final rawBytes = request.body;
  if (rawBytes == null || rawBytes.isEmpty) return null;

  final form = Multipart.parse(rawBytes, request.headers.contentType);
  final fields = <String>[];
  for (final part in form.parts) {
    if (!part.enabled) continue;
    if (part.isFile) {
      final bytes = part.bytes ?? const <int>[];
      fields.add("    '${_pyStr(part.name)}': ('${_pyStr(part.fileName ?? '')}', ${_pyBytes(bytes)}),");
    } else {
      fields.add("    '${_pyStr(part.name)}': (None, '${_pyStr(part.value)}'),");
    }
  }

  if (fields.isEmpty) return null;
  return 'files = {\n${fields.join('\n')}\n}';
}

Object? _tryJsonDecode(String text) {
  try {
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}

/// 把 Dart 对象（来自 JSON）格式化为缩进的 Python 字面量。
String _pyLiteral(Object? value, int indent) {
  final pad = '    ' * indent;
  final childPad = '    ' * (indent + 1);

  if (value == null) return 'None';
  if (value is bool) return value ? 'True' : 'False';
  if (value is num) return value.toString();
  if (value is String) return "'${_pyStr(value)}'";

  if (value is List) {
    if (value.isEmpty) return '[]';
    final items = value.map((e) => '$childPad${_pyLiteral(e, indent + 1)}').join(',\n');
    return '[\n$items,\n$pad]';
  }

  if (value is Map) {
    if (value.isEmpty) return '{}';
    final entries = value.entries.map((e) {
      return "$childPad'${_pyStr(e.key.toString())}': ${_pyLiteral(e.value, indent + 1)}";
    }).join(',\n');
    return '{\n$entries,\n$pad}';
  }

  return "'${_pyStr(value.toString())}'";
}

/// 转义为单引号 Python 字符串内容（不含外层引号）。
String _pyStr(String input) {
  final buffer = StringBuffer();
  for (final code in input.runes) {
    switch (code) {
      case 0x5C:
        buffer.write(r'\\');
      case 0x27:
        buffer.write(r"\'");
      case 0x0A:
        buffer.write(r'\n');
      case 0x0D:
        buffer.write(r'\r');
      case 0x09:
        buffer.write(r'\t');
      default:
        if (code < 0x20) {
          buffer.write('\\x${code.toRadixString(16).padLeft(2, '0')}');
        } else {
          buffer.writeCharCode(code);
        }
    }
  }
  return buffer.toString();
}

/// 构造 Python bytes 字面量 b'...'。
String _pyBytes(List<int> bytes) {
  final buffer = StringBuffer("b'");
  for (final b in bytes) {
    switch (b) {
      case 0x5C:
        buffer.write(r'\\');
      case 0x27:
        buffer.write(r"\'");
      case 0x0A:
        buffer.write(r'\n');
      case 0x0D:
        buffer.write(r'\r');
      case 0x09:
        buffer.write(r'\t');
      default:
        if (b >= 0x20 && b < 0x7F) {
          buffer.writeCharCode(b);
        } else {
          buffer.write('\\x${b.toRadixString(16).padLeft(2, '0')}');
        }
    }
  }
  buffer.write("'");
  return buffer.toString();
}

class _PyBody {
  /// 变量定义，例如 `json_data = {...}`
  final String? assignment;

  /// requests 调用参数，例如 `json=json_data`
  final String? callArg;

  /// 是否需要从 headers 中移除 Content-Type
  final bool dropContentType;

  const _PyBody({this.assignment, this.callArg, this.dropContentType = false});
}
