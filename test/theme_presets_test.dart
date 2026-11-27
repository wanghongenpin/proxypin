import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/ui/component/json/theme.dart';
import 'package:proxypin/ui/component/search/search_controller.dart';
import 'package:proxypin/ui/component/search/virtualized_highlight_text.dart';
import 'package:proxypin/ui/component/theme_presets.dart';

void main() {
  test('saved bright and dark editor variants resolve to their palette families', () {
    expect(EditorColorScheme.fromConfig('atomOneLight'), EditorColorScheme.atomOne);
    expect(EditorColorScheme.fromConfig('atomOneDark'), EditorColorScheme.atomOne);
    expect(EditorColorScheme.fromConfig('catppuccinLatte'), EditorColorScheme.catppuccin);
    expect(EditorColorScheme.fromConfig('catppuccinMocha'), EditorColorScheme.catppuccin);
    expect(EditorColorScheme.fromConfig('unknown'), EditorColorScheme.followTheme);
  });

  testWidgets('virtualized tokens update with the editor palette on the first frame', (tester) async {
    final controller = SearchTextController();
    final text = List.filled(200, 'const value = "preview";').join('\n');

    Future<Color?> render(Brightness brightness, EditorColorScheme editor) async {
      final colors = ThemePreset.rosePine.colorScheme(brightness)!;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          colorScheme: colors,
          extensions: [ActiveThemePreset(ThemePreset.rosePine, editor)],
        ),
        themeAnimationDuration: Duration.zero,
        home: Scaffold(
          body: VirtualizedHighlightText(text: text, language: 'javascript', searchController: controller),
        ),
      ));
      final viewer = find.byType(VirtualizedHighlightText);
      final code = tester.widget<Text>(find.descendant(of: viewer, matching: find.byType(Text)).first);
      Color? keyword;
      code.textSpan!.visitChildren((span) {
        if (span is TextSpan && span.text == 'const') keyword = span.style?.color;
        return keyword == null;
      });
      final expected = codeEditorTheme(tester.element(viewer), useAppSurface: true)['keyword']!.color;
      expect(keyword, expected);
      return keyword;
    }

    final dark = await render(Brightness.dark, EditorColorScheme.atomOne);
    final light = await render(Brightness.light, EditorColorScheme.atomOne);
    final alternate = await render(Brightness.light, EditorColorScheme.catppuccin);
    expect(dark, isNot(light));
    expect(alternate, isNot(light));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  for (final preset in ThemePreset.values) {
    testWidgets('${preset.name} syntax surfaces agree with app brightness', (tester) async {
      for (final brightness in Brightness.values) {
        final colors =
            preset.colorScheme(brightness) ?? ColorScheme.fromSeed(seedColor: Colors.blue, brightness: brightness);
        for (final editor in EditorColorScheme.values) {
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(colorScheme: colors, extensions: [ActiveThemePreset(preset, editor)]),
            themeAnimationDuration: Duration.zero,
            home: Builder(builder: (context) {
              final syntax = codeEditorTheme(context);
              final root = syntax['root']!;
              final surface = root.backgroundColor!;
              expect(ThemeData.estimateBrightnessForColor(surface), brightness, reason: editor.name);
              expect(surface, editor.preset?.colorScheme(brightness)?.surface ?? colors.surface);
              final inlineSyntax = codeEditorTheme(context, useAppSurface: true);
              expect(inlineSyntax['root']!.backgroundColor, colors.surface);
              for (final palette in [syntax, inlineSyntax]) {
                for (final MapEntry(key: token, value: style) in palette.entries) {
                  final foreground = style.color;
                  if (foreground == null) continue;
                  final text = foreground.computeLuminance();
                  final background =
                      (identical(palette, inlineSyntax) ? colors.surface : style.backgroundColor ?? surface)
                          .computeLuminance();
                  expect((max(text, background) + .05) / (min(text, background) + .05), greaterThanOrEqualTo(4.5),
                      reason: '${editor.name} $token');
                }
              }
              expect(ColorTheme.of(context).background, colors.surface);
              return const SizedBox();
            }),
          ));
        }
      }
    });
  }
}
