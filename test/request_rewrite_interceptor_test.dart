import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/components/manager/rewrite_rule.dart';
import 'package:proxypin/network/components/request_rewrite.dart';
import 'package:proxypin/network/http/http.dart';

void main() {
  test('responseRewrite applies response replacement rules', () async {
    final manager = await RequestRewriteManager.instance;
    final previousEnabled = manager.enabled;
    final previousRules = List<RequestRewriteRule>.from(manager.rules);
    final previousCache = Map<RequestRewriteRule, List<RewriteItem>>.from(manager.rewriteItemsCache);

    addTearDown(() {
      manager.enabled = previousEnabled;
      manager.rules
        ..clear()
        ..addAll(previousRules);
      manager.rewriteItemsCache
        ..clear()
        ..addAll(previousCache);
    });

    final rule = RequestRewriteRule(
      enabled: true,
      url: 'https://example.com/api',
      type: RuleType.responseReplace,
    );
    final item = RewriteItem(RewriteType.replaceResponseBody, true)..body = '{"ok":true}';

    manager.enabled = true;
    manager.rules
      ..clear()
      ..add(rule);
    manager.rewriteItemsCache
      ..clear()
      ..[rule] = [item];

    final request = HttpRequest(HttpMethod.get, 'https://example.com/api');
    final response = HttpResponse(HttpStatus.badGateway)
      ..request = request
      ..body = utf8.encode('upstream failed');

    final matched = await RequestRewriteInterceptor.instance.responseRewrite(request.requestUrl, response);

    expect(matched, isTrue);
    expect(response.getBodyString(), '{"ok":true}');
  });
}

