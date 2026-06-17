import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/http.dart';
import 'package:highlight/languages/yaml.dart';
import 'package:highlight/languages/markdown.dart';
import 'package:highlight/languages/bash.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/sql.dart';

import 'package:proxypin/network/http/content_type.dart';

/// Language constants for code_editor compatibility
final Mode langJavascript = javascript;
final Mode langJson = json;
final Mode langXml = xml;
final Mode langCss = css;
final Mode langHttp = http;
final Mode langYaml = yaml;
final Mode langMarkdown = markdown;
final Mode langBash = bash;
final Mode langPython = python;
final Mode langJava = java;
final Mode langGo = go;
final Mode langDart = dart;
final Mode langTypescript = typescript;
final Mode langSql = sql;

class HighlightLanguages {

  static Map<ContentType, Mode?> languages = {
    ContentType.json: langJson,
    ContentType.js: langJavascript,
    ContentType.html: langXml,
    ContentType.xml: langXml,
    ContentType.css: langCss,
    ContentType.formUrl: langHttp,
  };

  static Mode? getLanguage(ContentType contentType) {
    return languages[contentType];
  }
}
