import 'package:xml/xml.dart';

class XML {
  /// 格式化 XML
  static String pretty(String xmlString) {
    if (xmlString.trim().isEmpty || !xmlString.contains('<')) {
      return xmlString;
    }

    try {
      final document = XmlDocument.parse(xmlString);
      return document.toXmlString(pretty: true, indent: '  ');
    } catch (_) {
      return xmlString;
    }
  }
}

