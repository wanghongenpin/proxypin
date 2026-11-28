import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/query/query.dart';

void main() {
  test('tokenSpans keeps source positions incl. quotes and regex', () {
    const s = 'method:POST  body:"a b" url:/v\\d+ x/ | -host:*.ads.com';
    final spans = Query.tokenSpans(s);
    expect(spans.map((e) => e.source(s)).toList(),
        ['method:POST', 'body:"a b"', 'url:/v\\d+ x/', '|', '-host:*.ads.com']);
    expect(spans[1].value, 'body:a b');
    expect(Query.tokenize(s), spans.map((e) => e.value).toList());
  });

  test('removeToken tidies OR and whitespace', () {
    const s = 'a  b | c';
    expect(Query.removeToken(s, 0), 'b | c');
    expect(Query.removeToken(s, 3), 'a b');
    expect(Query.removeToken('a | b', 0), 'b');
    expect(Query.removeToken('a | | b', 3), 'a');
    expect(Query.removeToken('a', 5), 'a');
  });
}
