import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/css_formatter.dart';

void main() {
  group('CSS.pretty', () {
    test('formats simple rule', () {
      var input = 'body{color:red;margin:0;}';
      var result = CSS.pretty(input);
      expect(result, contains('body'));
      expect(result, contains('{'));
      expect(result, contains('color:red;'));
      expect(result, contains('margin:0;'));
      expect(result, contains('}'));
    });

    test('adds newlines after semicolons', () {
      var input = '.a{color:red;font-size:14px;}';
      var result = CSS.pretty(input);
      var lines = result.split('\n').where((l) => l.trim().isNotEmpty).toList();
      expect(lines.length, greaterThan(2));
    });

    test('handles nested blocks (media queries)', () {
      var input = '@media(max-width:600px){.a{color:red;}}';
      var result = CSS.pretty(input);
      expect(result, contains('@media'));
      expect(result, contains('.a'));
    });

    test('returns empty input unchanged', () {
      expect(CSS.pretty(''), '');
      expect(CSS.pretty('   '), '   ');
    });

    test('returns non-CSS input unchanged', () {
      expect(CSS.pretty('just plain text'), 'just plain text');
    });

    test('preserves string literals', () {
      var input = '.a{content:"hello world";color:blue;}';
      var result = CSS.pretty(input);
      expect(result, contains('"hello world"'));
    });

    test('handles comments', () {
      var input = '/* comment */.a{color:red;}';
      var result = CSS.pretty(input);
      expect(result, contains('/* comment */'));
      expect(result, contains('color:red'));
    });
  });
}
