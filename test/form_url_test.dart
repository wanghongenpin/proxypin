import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/form_url.dart';
import 'package:proxypin/utils/multipart.dart';

void main() {
  group('FormUrl.buildBytes', () {
    test('encodes key/value pairs', () {
      final form = FormBody(parts: [
        FormPart(name: 'name', value: '张三'),
        FormPart(name: 'q', value: 'a b&c'),
      ]);
      final text = utf8.decode(FormUrl.buildBytes(form));
      expect(text, 'name=${Uri.encodeQueryComponent('张三')}&q=${Uri.encodeQueryComponent('a b&c')}');
    });

    test('empty form produces empty body', () {
      expect(FormUrl.buildBytes(FormBody()), isEmpty);
    });

    test('skips disabled and empty-name parts', () {
      final form = FormBody(parts: [
        FormPart(name: 'on', value: '1'),
        FormPart(name: 'off', value: '2', enabled: false),
        FormPart(name: '', value: '3'),
      ]);
      expect(utf8.decode(FormUrl.buildBytes(form)), 'on=1');
    });
  });

  group('FormUrl.parse', () {
    test('decodes key/value pairs', () {
      final body = utf8.encode('name=${Uri.encodeQueryComponent('张三')}&q=hello');
      final form = FormUrl.parse(body);
      expect(form.parts[0].name, 'name');
      expect(form.parts[0].value, '张三');
      expect(form.parts[1].name, 'q');
      expect(form.parts[1].value, 'hello');
    });

    test('round-trips through build', () {
      final original = FormBody(parts: [
        FormPart(name: 'a', value: '1'),
        FormPart(name: 'b', value: '2'),
      ]);
      final parsed = FormUrl.parse(FormUrl.buildBytes(original));
      expect(parsed.parts.map((p) => [p.name, p.value]), [
        ['a', '1'],
        ['b', '2'],
      ]);
    });

    test('empty body produces empty form', () {
      expect(FormUrl.parse([]).parts, isEmpty);
    });
  });
}
