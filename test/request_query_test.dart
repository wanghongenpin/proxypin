import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/model/request_query.dart';
import 'package:proxypin/ui/component/model/search_model.dart';
import 'package:proxypin/utils/query/query.dart';

HttpRequest req(String method, String url,
    {int? status, String? resType, String? resBody, int costMs = 10, Map<String, String> headers = const {}}) {
  final r = HttpRequest(HttpMethod.valueOf(method), url);
  r.hostAndPort = HostAndPort.of(url);
  headers.forEach(r.headers.set);
  if (status != null) {
    final res = HttpResponse(HttpStatus.valueOf(status));
    if (resType != null) res.headers.set('Content-Type', resType);
    if (resBody != null) res.body = utf8.encode(resBody);
    res.request = r;
    res.responseTime = r.requestTime.add(Duration(milliseconds: costMs));
    r.response = res;
  }
  return r;
}

bool q(String query, HttpRequest r) => RequestQuery.parse(query).matches(RequestQueryItem(r, r.response));

void main() {
  final getJson = req('GET', 'https://api.example.com/v1/users?page=2',
      status: 200, resType: 'application/json', resBody: '{"name":"tom"}', costMs: 1200);
  final postErr = req('POST', 'http://shop.test.com/order',
      status: 502, resType: 'text/html', resBody: 'bad gateway', headers: {'Authorization': 'Bearer x'});
  final pending = req('GET', 'https://ads.tracker.com/pixel.gif');
  final image = req('GET', 'https://cdn.example.com/a.png', status: 200, resType: 'image/png', resBody: 'x' * 20000);

  group('tokenize/parse', () {
    test('quotes and regex keep spaces', () {
      expect(Query.tokenize('body:"hello world" url:/a b/ x'), ['body:hello world', 'url:/a b/', 'x']);
    });

    test('unknown field is plain text (urls still work)', () {
      final query = RequestQuery.parse('https://api.example.com');
      expect(query.hasFieldTerms, isFalse);
      expect(query.terms.single.value, 'https://api.example.com');
    });

    test('!= becomes negated eq', () {
      final t = RequestQuery.parse('status!=200').terms.single;
      expect(t.negate, isTrue);
      expect(t.op, QueryOp.eq);
    });
  });

  group('fields', () {
    test('method / multi values', () {
      expect(q('method:post', postErr), isTrue);
      expect(q('m:GET,PUT', postErr), isFalse);
      expect(q('m:GET,PUT', getJson), isTrue);
    });

    test('host wildcard and negation', () {
      expect(q('host:*.example.com', getJson), isTrue);
      expect(q('host:*.example.com', postErr), isFalse);
      expect(q('-host:tracker', pending), isFalse);
      expect(q('-host:tracker', getJson), isTrue);
    });

    test('status class, range, compare', () {
      expect(q('status:5xx', postErr), isTrue);
      expect(q('status:2xx', postErr), isFalse);
      expect(q('status:500-599', postErr), isTrue);
      expect(q('status>=400', getJson), isFalse);
      expect(q('status:>=400', postErr), isTrue);
      expect(q('status!=200', getJson), isFalse);
      expect(q('status!=200', postErr), isTrue);
    });

    test('type aliases and content-type fallback', () {
      expect(q('type:json', getJson), isTrue);
      expect(q('type:img', image), isTrue);
      expect(q('-type:image', image), isFalse);
      expect(q('type:png', image), isTrue);
    });

    test('size and time units', () {
      expect(q('size>10k', image), isTrue);
      expect(q('size<1k', getJson), isTrue);
      expect(q('time>1s', getJson), isTrue);
      expect(q('time:100-500', getJson), isFalse);
    });

    test('headers and body', () {
      expect(q('header:authorization', postErr), isTrue);
      expect(q('header:authorization=bearer*', postErr), isTrue);
      expect(q('header:authorization=basic*', postErr), isFalse);
      expect(q('resbody:tom', getJson), isTrue);
      expect(q('body:"bad gateway"', postErr), isTrue);
    });

    test('query params', () {
      expect(q('query:page=2', getJson), isTrue);
      expect(q('query:page=3', getJson), isFalse);
    });

    test('is: states', () {
      expect(q('is:pending', pending), isTrue);
      expect(q('is:error', postErr), isTrue);
      expect(q('is:slow', getJson), isTrue);
      expect(q('is:https', postErr), isFalse);
    });

    test('regex value', () {
      expect(q(r'url:/v\d+/users/', getJson), isTrue);
      expect(q(r'path:/^\/order$/', postErr), isTrue);
    });
  });

  group('boolean logic', () {
    test('AND within group, OR across groups', () {
      expect(q('method:GET status:5xx', postErr), isFalse);
      expect(q('method:GET status:5xx | method:POST', postErr), isTrue);
      expect(q('type:json OR type:image', image), isTrue);
    });

    test('plain text mixed with fields', () {
      expect(q('users method:GET', getJson), isTrue);
      expect(q('orders method:GET', getJson), isFalse);
    });
  });

  group('SearchModel integration', () {
    test('plain keyword keeps legacy whole-string matching', () {
      final model = SearchModel('example.com/v1');
      expect(model.query, isNull);
      expect(model.filter(getJson, getJson.response), isTrue);
    });

    test('advanced keyword uses query syntax', () {
      final model = SearchModel('status:5xx -host:ads');
      expect(model.query, isNotNull);
      expect(model.filter(postErr, postErr.response), isTrue);
      expect(model.filter(getJson, getJson.response), isFalse);
    });

    test('regex mode disables query syntax', () {
      final model = SearchModel(r'status:\d');
      model.isRegExp.value = true;
      expect(model.query, isNull);
    });
  });
}
