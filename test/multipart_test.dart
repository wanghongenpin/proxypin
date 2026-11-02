import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/multipart.dart';

void main() {
  group('boundaryFromContentType', () {
    test('unquoted boundary', () {
      expect(Multipart.boundaryFromContentType('multipart/form-data; boundary=----abc123'), '----abc123');
    });

    test('quoted boundary', () {
      expect(Multipart.boundaryFromContentType('multipart/form-data; boundary="a b c"'), 'a b c');
    });

    test('missing boundary', () {
      expect(Multipart.boundaryFromContentType('multipart/form-data'), isNull);
    });
  });

  group('buildBytes', () {
    test('empty form produces only closing boundary', () {
      final form = FormBody();
      final bytes = Multipart.buildBytes(form, boundary: 'bnd');
      expect(utf8.decode(bytes), '--bnd--\r\n');
    });

    test('text and file parts well-formed', () {
      final form = FormBody(parts: [
        FormPart(name: 'field1', value: 'value1'),
        FormPart(name: 'file1', kind: FormPartKind.file, fileName: 'a.txt', bytes: utf8.encode('hello')),
      ]);
      final bytes = Multipart.buildBytes(form, boundary: 'bnd');
      final text = utf8.decode(bytes);

      expect(text, contains('--bnd\r\n'));
      expect(text, contains('Content-Disposition: form-data; name="field1"'));
      expect(text, contains('\r\n\r\nvalue1\r\n'));
      expect(text, contains('Content-Disposition: form-data; name="file1"; filename="a.txt"'));
      expect(text, contains('Content-Type: text/plain'));
      expect(text, contains('\r\n\r\nhello\r\n'));
      expect(text.endsWith('--bnd--\r\n'), isTrue);
    });

    test('unknown file type falls back to octet-stream', () {
      final form = FormBody(parts: [
        FormPart(name: 'f', kind: FormPartKind.file, fileName: 'x.zzznotreal', bytes: [1]),
      ]);
      final text = utf8.decode(Multipart.buildBytes(form, boundary: 'bnd'));
      expect(text, contains('Content-Type: application/octet-stream'));
    });

    test('disabled parts are skipped', () {
      final form = FormBody(parts: [
        FormPart(name: 'on', value: '1'),
        FormPart(name: 'off', value: '2', enabled: false),
      ]);
      final text = utf8.decode(Multipart.buildBytes(form, boundary: 'bnd'));
      expect(text, contains('name="on"'));
      expect(text, isNot(contains('name="off"')));
    });

    test('render callback applies to text values', () {
      final form = FormBody(parts: [FormPart(name: 'f', value: '{{x}}')]);
      final bytes = Multipart.buildBytes(form, boundary: 'bnd', render: (s) => s.replaceAll('{{x}}', 'resolved'));
      expect(utf8.decode(bytes), contains('\r\n\r\nresolved\r\n'));
    });

    test('utf8 text value round-trips', () {
      final form = FormBody(parts: [FormPart(name: '你好', value: '中文🎉')]);
      final bytes = Multipart.buildBytes(form, boundary: 'bnd');
      final parsed = Multipart.parse(Uint8List.fromList(bytes), 'multipart/form-data; boundary=bnd');
      expect(parsed.parts.single.name, '你好');
      expect(parsed.parts.single.value, '中文🎉');
    });
  });

  group('parse', () {
    test('round-trips text and file parts', () {
      final form = FormBody(parts: [
        FormPart(name: 'f1', value: 'v1'),
        FormPart(name: 'f2', value: 'v2'),
        FormPart(name: 'up', kind: FormPartKind.file, fileName: 'a.bin', bytes: utf8.encode('file-bytes')),
      ]);
      final bytes = Multipart.buildBytes(form, boundary: 'bnd');
      final parsed = Multipart.parse(Uint8List.fromList(bytes), 'multipart/form-data; boundary=bnd');

      expect(parsed.parts, hasLength(3));
      expect(parsed.parts[0].name, 'f1');
      expect(parsed.parts[0].value, 'v1');
      expect(parsed.parts[0].isFile, isFalse);
      expect(parsed.parts[2].isFile, isTrue);
      expect(parsed.parts[2].fileName, 'a.bin');
      expect(utf8.decode(parsed.parts[2].bytes!), 'file-bytes');
    });

    test('binary bytes including 0x00 and 0xFF survive', () {
      final content = Uint8List.fromList([0x00, 0x01, 0xfe, 0xff, 0x0d, 0x0a, 0x80]);
      final form = FormBody(parts: [
        FormPart(name: 'up', kind: FormPartKind.file, fileName: 'blob', bytes: content),
      ]);
      final bytes = Multipart.buildBytes(form, boundary: 'bnd');
      final parsed = Multipart.parse(Uint8List.fromList(bytes), 'multipart/form-data; boundary=bnd');

      expect(parsed.parts.single.bytes, content);
    });

    test('returns empty form when boundary missing', () {
      final parsed = Multipart.parse(utf8.encode('whatever'), 'text/plain');
      expect(parsed.parts, isEmpty);
    });
  });
}
