import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:highlight/highlight.dart' show Node, highlight;

import 'search_controller.dart';

class HighlightTextDocument {
  final String text;
  final TextStyle? rootStyle;
  final List<HighlightStyledSegment> segments;
  final List<HighlightSearchMatch> matches;
  final List<HighlightDocumentLine> lines;
  final List<List<HighlightSearchMatch>> lineMatches;
  final List<int> matchLineIndexes;
  final int currentMatchIndex;

  const HighlightTextDocument._({
    required this.text,
    required this.rootStyle,
    required this.segments,
    required this.matches,
    required this.lines,
    required this.lineMatches,
    required this.matchLineIndexes,
    required this.currentMatchIndex,
  });

  factory HighlightTextDocument.create(
    BuildContext context, {
    required String text,
    String? language,
    TextStyle? style,
    required SearchTextController searchController,
  }) {
    final rootStyle = highlightRootStyle(context, style);
    final segments = buildHighlightBaseSegments(context, text, language: language, style: style);
    final matches = buildSearchMatches(text, searchController);
    final lines = buildHighlightDocumentLines(segments);
    final groupedMatches = _groupMatchesByLine(lines, matches);
    final currentMatchIndex = matches.isEmpty ? -1 : searchController.currentMatchIndex.value.clamp(0, matches.length - 1);
    final matchLineIndexes = _buildMatchLineIndexes(groupedMatches, matches.length);

    return HighlightTextDocument._(
      text: text,
      rootStyle: rootStyle,
      segments: segments,
      matches: matches,
      lines: lines,
      lineMatches: groupedMatches,
      matchLineIndexes: matchLineIndexes,
      currentMatchIndex: currentMatchIndex,
    );
  }

  int get totalMatchCount => matches.length;

  int? lineIndexForMatch(int matchIndex) {
    if (matchIndex < 0 || matchIndex >= matchLineIndexes.length) {
      return null;
    }
    return matchLineIndexes[matchIndex];
  }

  List<InlineSpan> buildAllSpans(BuildContext context) {
    final spans = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      spans.addAll(buildSpansForLine(context, i));
      if (i != lines.length - 1) {
        spans.add(TextSpan(text: '\n', style: rootStyle));
      }
    }
    return spans;
  }

  List<InlineSpan> buildSpansForLine(BuildContext context, int lineIndex) {
    final line = lines[lineIndex];
    final matchesForLine = lineMatches[lineIndex];
    if (matchesForLine.isEmpty) {
      return _plainLineSpans(line);
    }

    final spans = <InlineSpan>[];
    final colorScheme = ColorScheme.of(context);
    var matchIndex = 0;
    var consumed = 0;

    for (final segment in line.segments) {
      final segmentStart = line.start + consumed;
      final segmentEnd = segmentStart + segment.text.length;
      var localStart = 0;

      while (localStart < segment.text.length) {
        while (matchIndex < matchesForLine.length && matchesForLine[matchIndex].end <= segmentStart + localStart) {
          matchIndex++;
        }

        if (matchIndex >= matchesForLine.length || matchesForLine[matchIndex].start >= segmentEnd) {
          _appendTextSpan(spans, segment.text.substring(localStart), segment.style);
          break;
        }

        final match = matchesForLine[matchIndex];
        final absoluteStart = segmentStart + localStart;

        if (match.start > absoluteStart) {
          final plainEnd = match.start - segmentStart;
          _appendTextSpan(spans, segment.text.substring(localStart, plainEnd), segment.style);
          localStart = plainEnd;
          continue;
        }

        final overlapEnd = match.end < segmentEnd ? match.end : segmentEnd;
        final matchText = segment.text.substring(localStart, overlapEnd - segmentStart);
        final isCurrentMatch = match.index == currentMatchIndex;

        // 复用样式计算，减少对象创建
        final baseStyle = segment.style ?? const TextStyle();
        final highlightedStyle = baseStyle.copyWith(
          backgroundColor: isCurrentMatch ? colorScheme.primary : colorScheme.inversePrimary,
          color: isCurrentMatch ? colorScheme.onPrimary : baseStyle.color,
        );

        _appendTextSpan(spans, matchText, highlightedStyle);

        localStart = overlapEnd - segmentStart;
      }

      consumed += segment.text.length;
    }

    return spans;
  }

  List<InlineSpan> _plainLineSpans(HighlightDocumentLine line) {
    if (line.segments.isEmpty) {
      return [const TextSpan(text: '', style: TextStyle(color: Colors.transparent))];
    }

    return [for (final segment in line.segments) TextSpan(text: segment.text, style: segment.style)];
  }
}

TextStyle highlightRootStyle(BuildContext context, [TextStyle? style]) {
  final theme = Theme.brightnessOf(context) == Brightness.light ? atomOneLightTheme : atomOneDarkTheme;
  return _stripBackground((theme['root'] ?? const TextStyle(fontFamily: 'monospace', fontSize: 14.5)).merge(style)) ??
      const TextStyle(fontFamily: 'monospace', fontSize: 14.5);
}

List<HighlightStyledSegment> buildHighlightBaseSegments(
  BuildContext context,
  String text, {
  String? language,
  TextStyle? style,
}) {
  if (!(language?.isNotEmpty ?? false)) {
    return [HighlightStyledSegment(text: text, style: _stripBackground(style))];
  }

  try {
    final parsed = highlight.parse(text, language: language).nodes ?? const <Node>[];
    final theme = Theme.brightnessOf(context) == Brightness.light ? atomOneLightTheme : atomOneDarkTheme;

    List<HighlightStyledSegment> convert(List<Node> nodes, [TextStyle? inheritedStyle]) {
      final spans = <HighlightStyledSegment>[];
      for (final node in nodes) {
        final nodeStyle = node.className == null ? null : _stripBackground(theme[node.className!]);
        final mergedStyle = _stripBackground(inheritedStyle?.merge(nodeStyle) ?? nodeStyle);

        if (node.value != null) {
          spans.add(HighlightStyledSegment(text: node.value!, style: mergedStyle));
          continue;
        }

        if (node.children != null && node.children!.isNotEmpty) {
          spans.addAll(convert(node.children!, mergedStyle));
        }
      }
      return spans;
    }

    final result = convert(parsed);
    if (result.isNotEmpty) {
      return result;
    }
  } catch (_) {}

  return [HighlightStyledSegment(text: text, style: _stripBackground(style))];
}

List<HighlightSearchMatch> buildSearchMatches(String text, SearchTextController searchController) {
  if (!searchController.shouldSearch()) {
    return const [];
  }

  final pattern = searchController.value.pattern;
  if (pattern.isEmpty) {
    return const [];
  }

  try {
    final regex = searchController.value.isRegExp
        ? RegExp(pattern, caseSensitive: searchController.value.isCaseSensitive)
        : RegExp(RegExp.escape(pattern), caseSensitive: searchController.value.isCaseSensitive);

    final matches = <HighlightSearchMatch>[];
    var index = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start == match.end) {
        continue;
      }
      matches.add(HighlightSearchMatch(index: index, start: match.start, end: match.end));
      index++;
    }
    return matches;
  } catch (_) {
    return const [];
  }
}

List<HighlightDocumentLine> buildHighlightDocumentLines(List<HighlightStyledSegment> segments) {
  final lines = <HighlightDocumentLine>[];
  final currentSegments = <HighlightStyledSegment>[];
  var lineStart = 0;
  var offset = 0;
  var lineNumber = 0;

  void pushLine() {
    lines.add(HighlightDocumentLine(
      index: lineNumber++,
      start: lineStart,
      end: offset,
      segments: List<HighlightStyledSegment>.from(currentSegments),
    ));
    currentSegments.clear();
  }

  for (final segment in segments) {
    final parts = segment.text.split('\n');
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isNotEmpty) {
        currentSegments.add(HighlightStyledSegment(text: part, style: segment.style));
      }
      offset += part.length;

      if (i != parts.length - 1) {
        pushLine();
        offset += 1;
        lineStart = offset;
      }
    }
  }

  if (lines.isEmpty || lineStart <= offset) {
    pushLine();
  }

  return lines;
}

void _appendTextSpan(List<InlineSpan> spans, String value, TextStyle? textStyle) {
  if (value.isEmpty) {
    return;
  }
  spans.add(TextSpan(text: value, style: textStyle));
}

List<List<HighlightSearchMatch>> _groupMatchesByLine(
  List<HighlightDocumentLine> lines,
  List<HighlightSearchMatch> matches,
) {
  final grouped = List.generate(lines.length, (_) => <HighlightSearchMatch>[]);
  if (matches.isEmpty || lines.isEmpty) {
    return grouped;
  }

  var lineIndex = 0;
  for (final match in matches) {
    while (lineIndex < lines.length && lines[lineIndex].end <= match.start) {
      lineIndex++;
    }

    for (var i = lineIndex; i < lines.length; i++) {
      final line = lines[i];
      if (line.start >= match.end) {
        break;
      }
      if (line.end > match.start) {
        grouped[i].add(match);
      }
    }
  }

  return grouped;
}

List<int> _buildMatchLineIndexes(List<List<HighlightSearchMatch>> groupedMatches, int matchCount) {
  final indexes = List.filled(matchCount, 0);
  for (var lineIndex = 0; lineIndex < groupedMatches.length; lineIndex++) {
    for (final match in groupedMatches[lineIndex]) {
      if (match.index < indexes.length && indexes[match.index] == 0) {
        indexes[match.index] = lineIndex;
      }
    }
  }
  return indexes;
}

class HighlightStyledSegment {
  final String text;
  final TextStyle? style;

  const HighlightStyledSegment({required this.text, this.style});
}

class HighlightSearchMatch {
  final int index;
  final int start;
  final int end;

  const HighlightSearchMatch({required this.index, required this.start, required this.end});
}

class HighlightDocumentLine {
  final int index;
  final int start;
  final int end;
  final List<HighlightStyledSegment> segments;

  const HighlightDocumentLine({
    required this.index,
    required this.start,
    required this.end,
    required this.segments,
  });

  String get text => segments.map((segment) => segment.text).join();
}

TextStyle? _stripBackground(TextStyle? style) {
  if (style == null) {
    return null;
  }
  return style.copyWith(backgroundColor: null, background: null);
}
