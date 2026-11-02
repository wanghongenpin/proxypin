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

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:proxypin/network/components/manager/environment_manager.dart';

/// multipart/form-data 模型、构建器与解析器。
///
/// 与 [Curl] 中基于 String 的私有 multipart 解析不同，这里全程按字节处理，
/// 文件内容（可能含任意二进制字节）不会因 utf8/latin1 解码而损坏。
///
/// @author wanghongen
enum FormPartKind { text, file }

class FormPart {
  bool enabled;
  String name;
  FormPartKind kind;

  /// 文本字段值（[kind] == [FormPartKind.text]）
  String value;

  /// 文件名（[kind] == [FormPartKind.file]）
  String? fileName;

  /// 文件内容，选择文件时预读入内存；解析已捕获请求时为原始 part 字节
  List<int>? bytes;

  /// part 级 Content-Type（解析已捕获请求时可能带）
  String? contentType;

  FormPart({
    required this.name,
    this.enabled = true,
    this.kind = FormPartKind.text,
    this.value = '',
    this.fileName,
    this.bytes,
    this.contentType,
  });

  bool get isFile => kind == FormPartKind.file;

  /// 文件大小（字节），未知返回 null
  int? get fileSize => bytes?.length;
}

class FormBody {
  final List<FormPart> parts;

  FormBody({List<FormPart>? parts}) : parts = parts ?? [];

  Iterable<FormPart> get _enabled => parts.where((p) => p.enabled);
}

class Multipart {
  static const _crlf = [0x0d, 0x0a]; // \r\n
  static const _boundaryAlphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  static final _random = Random();

  /// 生成一个新的 boundary，附带时间戳和随机串，尽量避免与 body 内容冲突
  static String newBoundary() {
    final sb = StringBuffer('----ProxyPin')
      ..write(DateTime.now().millisecondsSinceEpoch);
    for (int i = 0; i < 16; i++) {
      sb.write(_boundaryAlphabet[_random.nextInt(_boundaryAlphabet.length)]);
    }
    return sb.toString();
  }

  /// 从 Content-Type 头提取 boundary，兼容带引号: boundary="xxx"
  /// 例: multipart/form-data; boundary=----WebKitFormBoundary7MA
  static String? boundaryFromContentType(String contentType) {
    RegExp regExp = RegExp(r'boundary=(?:"([^"]+)"|([^\s;]+))', caseSensitive: false);
    Match? match = regExp.firstMatch(contentType);
    return match?.group(1) ?? match?.group(2);
  }

  /// 构建 multipart/form-data 二进制 body。
  ///
  /// [render] 用于渲染文本字段值中的环境变量占位符（如 {{name}}），
  /// 默认走 [EnvironmentManager.tryRender]；文件内容原样写入。
  /// 即使没有任何启用的字段也会输出仅含 closing boundary 的合法 body，
  /// 以保证 Content-Type 与 Content-Length 一致。
  static List<int> buildBytes(FormBody form, {required String boundary, String Function(String)? render}) {
    final valueRender = render ?? (String s) => EnvironmentManager.tryRender(s) ?? s;
    final builder = BytesBuilder(copy: false);

    for (final part in form._enabled) {
      builder.add(utf8.encode('--$boundary'));
      builder.add(_crlf);
      if (part.isFile) {
        final filename = _escapeHeaderParam(part.fileName ?? '');
        builder.add(utf8.encode('Content-Disposition: form-data; name="${_escapeHeaderParam(part.name)}"; '
            'filename="$filename"'));
        builder.add(_crlf);
        final mime = part.contentType ?? lookupMimeType(part.fileName ?? '') ?? 'application/octet-stream';
        builder.add(utf8.encode('Content-Type: $mime'));
        builder.add(_crlf);
        builder.add(_crlf);
        final content = part.bytes;
        if (content != null) builder.add(content);
        builder.add(_crlf);
      } else {
        builder.add(utf8.encode('Content-Disposition: form-data; name="${_escapeHeaderParam(part.name)}"'));
        builder.add(_crlf);
        builder.add(_crlf);
        builder.add(utf8.encode(valueRender(part.value)));
        builder.add(_crlf);
      }
    }

    builder.add(utf8.encode('--$boundary--'));
    builder.add(_crlf);
    return builder.toBytes();
  }

  /// 解析 multipart/form-data body 为 [FormBody]，全程按字节操作。
  /// 提取不到 boundary 时返回空表单。
  static FormBody parse(List<int> body, String contentType) {
    final form = FormBody();
    final boundary = boundaryFromContentType(contentType);
    if (boundary == null || body.isEmpty) return form;

    final delimiter = utf8.encode('--$boundary');

    // 定位所有 boundary delimiter 位置
    final positions = <int>[];
    int search = 0;
    while (true) {
      final idx = _indexOf(body, delimiter, search);
      if (idx == -1) break;
      positions.add(idx);
      search = idx + delimiter.length;
    }
    if (positions.isEmpty) return form;

    for (int i = 0; i < positions.length; i++) {
      final partStart = positions[i] + delimiter.length;
      // closing delimiter: "--boundary--"
      if (partStart + 1 < body.length && body[partStart] == 0x2d && body[partStart + 1] == 0x2d) {
        break;
      }

      final partEnd = i + 1 < positions.length ? positions[i + 1] : body.length;
      var part = body.sublist(partStart, partEnd);
      part = _stripLeadingCrlf(part);
      part = _stripTrailingCrlf(part);

      final separator = _indexOf(part, [0x0d, 0x0a, 0x0d, 0x0a], 0);
      final int split;
      final int sepLen;
      if (separator != -1) {
        split = separator;
        sepLen = 4;
      } else {
        final idx = _indexOf(part, [0x0a, 0x0a], 0);
        if (idx == -1) continue; // 不是合法 part，跳过
        split = idx;
        sepLen = 2;
      }

      final headerText = latin1.decode(part.sublist(0, split));
      final content = part.sublist(split + sepLen);
      final headers = _parseHeaders(headerText);

      final disposition = headers['content-disposition'];
      // 头部按 latin1 解码，name/filename 中的非 ASCII（实际为 UTF-8 字节）需修复
      final name = disposition == null ? null : _fixMojibake(_dispositionParam(disposition, 'name'));
      final filename = disposition == null ? null : _fixMojibake(_dispositionParam(disposition, 'filename'));
      final partContentType = headers['content-type'];

      if (name == null) continue;

      if (filename != null) {
        // 已捕获请求中的文件：原路径在本机不可用，直接保留原始字节与文件名
        form.parts.add(FormPart(
          name: name,
          kind: FormPartKind.file,
          fileName: filename,
          bytes: content,
          contentType: partContentType,
        ));
      } else {
        form.parts.add(FormPart(
          name: name,
          value: utf8.decode(content, allowMalformed: true),
          contentType: partContentType,
        ));
      }
    }

    return form;
  }

  /// 转义 Content-Disposition 参数中的特殊字符（RFC 风格）
  static String _escapeHeaderParam(String value) {
    final sb = StringBuffer();
    for (final code in value.codeUnits) {
      if (code == 0x22 || code == 0x5c) {
        // " 或 \
        sb.writeCharCode(0x5c);
      }
      if (code == 0x0d) {
        sb.write(r'\r');
        continue;
      }
      if (code == 0x0a) {
        sb.write(r'\n');
        continue;
      }
      sb.writeCharCode(code);
    }
    return sb.toString();
  }

  /// part 头部按 latin1 解码后，非 ASCII 字符（实际是 UTF-8 字节）会变 Latin-1 乱码，
  /// 把 code units 当字节再用 UTF-8 解一次；null 或已是正常 Unicode 时原样返回。
  static String? _fixMojibake(String? s) {
    if (s == null) return null;
    bool needsFix = false;
    for (int i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c > 0xFF) return s;
      if (c >= 0x80) needsFix = true;
    }
    if (!needsFix) return s;
    try {
      return utf8.decode(s.codeUnits);
    } catch (_) {
      return s;
    }
  }

  /// 从 Content-Disposition 头提取参数，兼容引号与无引号写法
  /// 例: form-data; name="field1"; filename="test.pdf"
  static String? _dispositionParam(String header, String paramName) {
    RegExp regExp = RegExp('(?:^|[;\\s])$paramName="([^"]*)"', caseSensitive: false);
    Match? match = regExp.firstMatch(header);
    if (match != null) return match.group(1);

    regExp = RegExp('(?:^|[;\\s])$paramName=([^\\s;]+)', caseSensitive: false);
    match = regExp.firstMatch(header);
    return match?.group(1);
  }

  /// 解析 part 头部为小写 key → value 的映射
  static Map<String, String> _parseHeaders(String text) {
    final map = <String, String>{};
    for (final line in const LineSplitter().convert(text)) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      map[line.substring(0, idx).trim().toLowerCase()] = line.substring(idx + 1).trim();
    }
    return map;
  }

  static List<int> _stripLeadingCrlf(List<int> bytes) {
    int start = 0;
    if (start < bytes.length && bytes[start] == 0x0d) start++;
    if (start < bytes.length && bytes[start] == 0x0a) start++;
    return start == 0 ? bytes : bytes.sublist(start);
  }

  static List<int> _stripTrailingCrlf(List<int> bytes) {
    int end = bytes.length;
    if (end > 0 && bytes[end - 1] == 0x0a) end--;
    if (end > 0 && bytes[end - 1] == 0x0d) end--;
    return end == bytes.length ? bytes : bytes.sublist(0, end);
  }

  /// 在 [haystack] 中从 [start] 起查找 [needle]，未找到返回 -1
  static int _indexOf(List<int> haystack, List<int> needle, int start) {
    if (needle.isEmpty) return start;
    final limit = haystack.length - needle.length;
    outer:
    for (int i = start; i <= limit; i++) {
      for (int j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
