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

  static ColorTheme dark(ColorScheme colorScheme) => ColorTheme(
        background: const Color(0XFF1E1F22),
        propertyKey: const Color(0XFFC77DBB),
        colon: const Color(0XFFBCBEC4),
        string: const Color(0XFF6AAB73),
        number: const Color(0XFF2AACB8),
        keyword: const Color(0XFFCF8E6D),
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
