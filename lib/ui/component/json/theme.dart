import 'package:flutter/material.dart';

class ColorTheme {
  static ColorTheme light(ColorScheme colorScheme) => ColorTheme(
        background: const Color(0xffffffff),
        propertyKey: const Color(0xff871094),
        colon: Colors.black,
        string: const Color(0xff067d17),
        number: const Color(0xff1750eb),
        keyword: const Color(0xff0033b3),
        searchMatchColor: colorScheme.inversePrimary,
        searchMatchCurrentColor: colorScheme.primary,
      );

  static Color _lighten(Color color, [double amount = 0.2]) {
        final hsl = HSLColor.fromColor(color);
        final hslLight =
            hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0));
        return hslLight.toColor();
  }

  static ColorTheme dark(ColorScheme colorScheme) => ColorTheme(
        background: const Color(0xff2b2b2b),
        propertyKey: _lighten(const Color(0xff9876aa), 0.18),
        colon: _lighten(const Color(0xffcc7832), 0.15),
        string: _lighten(const Color(0xff6a8759), 0.20),
        number: _lighten(const Color(0xff6897bb), 0.20),
        keyword: _lighten(const Color.fromRGBO(204, 120, 50, 1), 0.15),
        searchMatchColor: colorScheme.inversePrimary,
        searchMatchCurrentColor: colorScheme.primary,
      );

  final Color background;
  final Color propertyKey;
  final Color colon;
  final Color string;
  final Color number;
  final Color keyword;
  final Color? searchMatchColor;
  final Color? searchMatchCurrentColor;

  const ColorTheme({
    required this.background,
    required this.propertyKey,
    required this.colon,
    required this.string,
    required this.number,
    required this.keyword,
    required this.searchMatchColor,
    required this.searchMatchCurrentColor,
  });

  static ColorTheme of(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? ColorTheme.dark(colorScheme) : ColorTheme.light(colorScheme);
  }
}
