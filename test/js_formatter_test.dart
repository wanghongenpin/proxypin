import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/js_formatter.dart';

void main() {
  group('JS.pretty', () {
    test('formats simple function', () {
      var input = 'function foo(){return 1;}';
      var result = JS.pretty(input);
      expect(result, contains('function foo'));
      expect(result, contains('{'));
      expect(result, contains('return 1;'));
      expect(result, contains('}'));
    });

    test('adds newlines after semicolons', () {
      var input = 'var a=1;var b=2;var c=3;';
      var result = JS.pretty(input);
      var lines = result.split('\n').where((l) => l.trim().isNotEmpty).toList();
      expect(lines.length, greaterThanOrEqualTo(3));
    });

    test('handles nested braces', () {
      var input = 'if(x){if(y){z();}}';
      var result = JS.pretty(input);
      expect(result, contains('if(x)'));
      expect(result, contains('if(y)'));
      expect(result, contains('z()'));
    });

    test('returns empty input unchanged', () {
      expect(JS.pretty(''), '');
      expect(JS.pretty('   '), '   ');
    });

    test('preserves string literals', () {
      var input = 'var s="hello {world}";';
      var result = JS.pretty(input);
      expect(result, contains('"hello {world}"'));
    });

    test('preserves single-quoted strings', () {
      var input = "var s='test;string';";
      var result = JS.pretty(input);
      expect(result, contains("'test;string'"));
    });

    test('handles template literals', () {
      var input = 'var s=`hello \${name}`;';
      var result = JS.pretty(input);
      expect(result, contains('`hello \${name}`'));
    });

    test('handles line comments', () {
      var input = '// comment\nvar x=1;';
      var result = JS.pretty(input);
      expect(result, contains('// comment'));
      expect(result, contains('var x=1'));
    });

    test('handles block comments', () {
      var input = '/* block */var x=1;';
      var result = JS.pretty(input);
      expect(result, contains('/* block */'));
    });

    test('normalizes commas with space', () {
      var input = 'foo(a,b,c);';
      var result = JS.pretty(input);
      expect(result, contains('a, b, c'));
    });
  });
}
