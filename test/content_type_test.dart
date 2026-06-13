import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/http/content_type.dart';

void main() {
  group('ContentType enum', () {
    test('valueOf returns correct enum for known name', () {
      expect(ContentType.valueOf('json'), ContentType.json);
      expect(ContentType.valueOf('html'), ContentType.html);
      expect(ContentType.valueOf('image'), ContentType.image);
    });

    test('valueOf defaults to http for unknown name', () {
      expect(ContentType.valueOf('unknown'), ContentType.http);
    });

    test('isBinary for image, font, video', () {
      expect(ContentType.image.isBinary, true);
      expect(ContentType.font.isBinary, true);
      expect(ContentType.video.isBinary, true);
      expect(ContentType.json.isBinary, false);
      expect(ContentType.html.isBinary, false);
    });

    test('isImage only for image', () {
      expect(ContentType.image.isImage, true);
      expect(ContentType.video.isImage, false);
    });
  });

  group('MediaType.valueOf', () {
    test('parses simple media type', () {
      var mt = MediaType.valueOf('application/json');
      expect(mt, isNotNull);
      expect(mt!.type, 'application');
      expect(mt.subtype, 'json');
    });

    test('parses media type with charset', () {
      var mt = MediaType.valueOf('text/html; charset=utf-8');
      expect(mt, isNotNull);
      expect(mt!.type, 'text');
      expect(mt.subtype, 'html');
      expect(mt.charset, 'utf-8');
    });

    test('parses media type with multiple parameters', () {
      var mt = MediaType.valueOf('multipart/form-data; boundary=abc123');
      expect(mt, isNotNull);
      expect(mt!.type, 'multipart');
      expect(mt.subtype, 'form-data');
      expect(mt.parameters['boundary'], 'abc123');
    });

    test('returns null for empty string', () {
      expect(() => MediaType.valueOf(''), throwsA(isA<InvalidMediaTypeException>()));
    });

    test('returns null for invalid media type without slash', () {
      var mt = MediaType.valueOf('textplain');
      expect(mt, null);
    });

    test('handles wildcard type', () {
      var mt = MediaType.valueOf('*/*');
      expect(mt, isNotNull);
      expect(mt!.type, '*');
      expect(mt.subtype, '*');
    });
  });

  group('MediaType equality', () {
    test('equalsTypeAndSubtype ignores parameters', () {
      var a = MediaType('text', 'html', charset: 'utf-8');
      var b = MediaType('text', 'html');
      expect(a.equalsTypeAndSubtype(b), true);
    });

    test('equalsTypeAndSubtype is case-insensitive', () {
      var a = MediaType('Text', 'HTML');
      var b = MediaType('text', 'html');
      expect(a.equalsTypeAndSubtype(b), true);
    });

    test('different type/subtype means not equal', () {
      var a = MediaType('text', 'html');
      var b = MediaType('text', 'plain');
      expect(a == b, false);
    });
  });

  group('MediaType.defaultCharset', () {
    test('returns utf-8 for text/html', () {
      var mt = MediaType('text', 'html');
      expect(MediaType.defaultCharset(mt), 'utf-8');
    });

    test('returns utf-8 for application/json', () {
      var mt = MediaType('application', 'json');
      expect(MediaType.defaultCharset(mt), 'utf-8');
    });

    test('returns null for unknown type', () {
      var mt = MediaType('custom', 'binary');
      expect(MediaType.defaultCharset(mt), null);
    });
  });
}
