import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/utils/xml_formatter.dart';

void main() {
  test('XML.pretty formats nested document', () {
    const input = '<root><a>1</a><b><c>2</c></b></root>';

    expect(
      XML.pretty(input),
      '<root>\n'
      '  <a>1</a>\n'
      '  <b>\n'
      '    <c>2</c>\n'
      '  </b>\n'
      '</root>',
    );
  });

  test('XML.pretty falls back for malformed XML', () {
    const input = '<root><a></root>';
    expect(XML.pretty(input), input);
  });

  test('xml content types map to ContentType.xml', () {
    final response = HttpResponse(HttpStatus.ok);

    response.headers.set('content-type', 'application/xml; charset=utf-8');
    expect(response.contentType, ContentType.xml);

    response.headers.set('content-type', 'text/xml; charset=utf-8');
    expect(response.contentType, ContentType.xml);

    response.headers.set('content-type', 'application/soap+xml; charset=utf-8');
    expect(response.contentType, ContentType.xml);
  });

  test('xhtml keeps html content type', () {
    final response = HttpResponse(HttpStatus.ok);
    response.headers.set('content-type', 'application/xhtml+xml; charset=utf-8');

    expect(response.contentType, ContentType.html);
  });
}

