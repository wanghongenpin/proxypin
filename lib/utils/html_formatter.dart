import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

class HTML {
  static final RegExp _documentTagPattern = RegExp(r'^\s*<(?:!doctype|html|head|body)\b', caseSensitive: false);

  /// 格式化 HTML
  static String pretty(String htmlString) {
    if (htmlString.trim().isEmpty || !htmlString.contains('<')) {
      return htmlString;
    }

    try {
      final root = _documentTagPattern.hasMatch(htmlString)
          ? html_parser.parse(htmlString)
          : html_parser.parseFragment(htmlString);
      final buffer = StringBuffer();

      for (final node in root.nodes) {
        _HtmlPrettyPrinter.writeNode(node, buffer, 0);
      }

      final formatted = buffer.toString().trimRight();
      return formatted.isEmpty ? htmlString : formatted;
    } catch (_) {
      return htmlString;
    }
  }
}

class _HtmlPrettyPrinter {
  static const String _indent = '  ';
  static const Set<String> _voidElements = {
    'area',
    'base',
    'br',
    'col',
    'embed',
    'hr',
    'img',
    'input',
    'link',
    'meta',
    'param',
    'source',
    'track',
    'wbr',
  };
  static const Set<String> _preserveContentElements = {'pre', 'script', 'style', 'textarea'};
  static const HtmlEscape _attributeEscaper = HtmlEscape(HtmlEscapeMode.attribute);

  static void writeNode(dom.Node node, StringBuffer buffer, int depth) {
    if (node is dom.Text) {
      final text = _normalizeText(node.text);
      if (text.isNotEmpty) {
        _writeLine(buffer, depth, text);
      }
      return;
    }

    if (node is dom.Comment) {
      _writeLine(buffer, depth, node.toString().trim());
      return;
    }

    if (node is dom.DocumentType) {
      _writeLine(buffer, depth, node.toString().trim());
      return;
    }

    if (node is dom.Element) {
      _writeElement(node, buffer, depth);
      return;
    }

    for (final child in node.nodes) {
      writeNode(child, buffer, depth);
    }
  }

  static void _writeElement(dom.Element element, StringBuffer buffer, int depth) {
    final tag = (element.localName ?? '').toLowerCase();
    if (tag.isEmpty) {
      for (final child in element.nodes) {
        writeNode(child, buffer, depth);
      }
      return;
    }

    final openTag = _openTag(element, tag);

    if (_voidElements.contains(tag)) {
      _writeLine(buffer, depth, openTag);
      return;
    }

    if (_preserveContentElements.contains(tag)) {
      _writeLine(buffer, depth, openTag);
      final content = element.innerHtml.trimRight();
      if (content.isNotEmpty) {
        for (final line in content.split('\n')) {
          _writeLine(buffer, depth + 1, line.trimRight());
        }
      }
      _writeLine(buffer, depth, '</$tag>');
      return;
    }

    final children = element.nodes.where(_hasVisibleContent).toList();
    if (children.isEmpty) {
      _writeLine(buffer, depth, '$openTag</$tag>');
      return;
    }

    final inlineText = _inlineText(children);
    if (inlineText != null) {
      _writeLine(buffer, depth, '$openTag$inlineText</$tag>');
      return;
    }

    _writeLine(buffer, depth, openTag);
    for (final child in children) {
      writeNode(child, buffer, depth + 1);
    }
    _writeLine(buffer, depth, '</$tag>');
  }

  static bool _hasVisibleContent(dom.Node node) {
    if (node is dom.Text) {
      return _normalizeText(node.text).isNotEmpty;
    }
    return true;
  }

  static String? _inlineText(List<dom.Node> children) {
    if (children.length != 1 || children.first is! dom.Text) {
      return null;
    }

    final text = _normalizeText((children.first as dom.Text).text);
    return text.isEmpty ? null : text;
  }

  static String _openTag(dom.Element element, String tag) {
    if (element.attributes.isEmpty) {
      return '<$tag>';
    }

    final attributes =
        element.attributes.entries.map((entry) => '${entry.key}="${_attributeEscaper.convert(entry.value)}"').join(' ');
    return '<$tag $attributes>';
  }

  static String _normalizeText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static void _writeLine(StringBuffer buffer, int depth, String line) {
    buffer
      ..write(_indent * depth)
      ..writeln(line);
  }
}

