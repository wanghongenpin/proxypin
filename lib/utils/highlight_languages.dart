import 'package:proxypin/network/http/content_type.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/css.dart';

import 'package:re_highlight/re_highlight.dart';

class HighlightLanguages {

  static Map<ContentType, Mode?> languages = {
    ContentType.json: langJson,
    ContentType.js: langJavascript,
    ContentType.html: langXml,
    ContentType.xml: langXml,
    ContentType.css: langCss,
  };

  static Mode? getLanguage(ContentType contentType) {
    return languages[contentType];
  }
}
