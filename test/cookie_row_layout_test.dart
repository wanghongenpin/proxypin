import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/ui/content/panel.dart';

void main() {
  testWidgets('long cookie key wraps without overlapping its value', (tester) async {
    const cookieKey = 'a_very_long_cookie_key_that_must_wrap_instead_of_overlapping_the_value';
    const cookieValue = 'cookie-value';

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: Builder(builder: (context) => overviewRow(context, cookieKey, cookieValue)),
          ),
        ),
      ),
    ));

    final keyFinder = find.text(cookieKey);
    final valueFinder = find.text(cookieValue);
    final keyRect = tester.getRect(keyFinder);
    final valueRect = tester.getRect(valueFinder);

    expect(keyRect.height, greaterThan(13 * 1.5));
    expect(keyRect.right, lessThanOrEqualTo(valueRect.left));
    expect(keyRect.top, valueRect.top);
    expect(tester.takeException(), isNull);
  });
}
