import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/utils/html_formatter.dart';

void main() {
  test('HTML.pretty formats nested markup', () {
    const input = '<div><h1>Hello</h1><p>World <strong>!</strong></p></div>';

    expect(
      HTML.pretty(input),
      '<div>\n'
      '  <h1>Hello</h1>\n'
      '  <p>\n'
      '    World\n'
      '    <strong>!</strong>\n'
      '  </p>\n'
      '</div>',
    );
  });

  test('HTML.pretty tolerates malformed HTML', () {
    const input = '<div><span>hello</div>';

    expect(
      HTML.pretty(input),
      '<div>\n'
      '  <span>hello</span>\n'
      '</div>',
    );
  });

  test('HTML.pretty leaves plain text unchanged', () {
    expect(HTML.pretty('plain text body'), 'plain text body');
  });

  test('xhtml content type maps to html', () {
    final response = HttpResponse(HttpStatus.ok);
    response.headers.set('content-type', 'application/xhtml+xml; charset=utf-8');

    expect(response.contentType, ContentType.html);
  });
}
