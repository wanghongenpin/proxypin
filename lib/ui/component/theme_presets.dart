import 'package:flutter/material.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

abstract class ThemePreset {
  const ThemePreset();

  static const ThemePreset custom = _BuiltInTheme('custom', '', '');
  static const ThemePreset atomOne =
      _BuiltInTheme('atomOne', 'Atom One Light', 'Atom One Dark', _atomOneLight, _atomOneDark);
  static const ThemePreset catppuccin =
      _BuiltInTheme('catppuccin', 'Catppuccin Latte', 'Catppuccin Mocha', _catppuccinLatte, _catppuccinMocha);
  static const ThemePreset rosePine =
      _BuiltInTheme('rosePine', 'Rosé Pine Dawn', 'Rosé Pine', _rosePineDawn, _rosePine);
  static const ThemePreset claudeCode =
      _BuiltInTheme('claudeCode', 'Claude Code Light', 'Claude Code Dark', _claudeLight, _claudeDark);
  static const ThemePreset apple = _BuiltInTheme('apple', 'Apple Light', 'Apple Dark', _appleLight, _appleDark);
  static const ThemePreset gmail = _BuiltInTheme('gmail', 'Gmail Light', 'Gmail Dark', _gmailLight, _gmailDark);
  static const ThemePreset figma = _BuiltInTheme('figma', 'Figma Light', 'Figma Dark', _figmaLight, _figmaDark);

  static const List<ThemePreset> values = [custom, atomOne, catppuccin, rosePine, claudeCode, apple, gmail, figma];

  String get name;
  String label(Brightness brightness);
  ColorScheme? colorScheme(Brightness brightness);
  Color stringColor(Brightness brightness);

  bool get usesDefaultSyntax => false;

  List<Color> swatches(Brightness brightness) => [
        if (colorScheme(brightness) case final scheme?) ...[
          scheme.surface,
          scheme.primary,
          scheme.secondary,
          scheme.tertiary,
        ],
      ];

  Map<String, TextStyle> syntax(Brightness brightness, {ColorScheme? scheme}) {
    final base = brightness == Brightness.dark ? atomOneDarkTheme : atomOneLightTheme;
    if (usesDefaultSyntax) return base;
    final colors = scheme ?? colorScheme(brightness)!;
    Color readable(Color color) {
      final text = color.computeLuminance();
      final background = colors.surface.computeLuminance();
      final contrast = text > background ? (text + .05) / (background + .05) : (background + .05) / (text + .05);
      return contrast >= 4.5 ? color : colors.onSurface;
    }

    return {
      ...base,
      'root': base['root']!.copyWith(color: colors.onSurface, backgroundColor: colors.surface),
      for (final token in ['comment', 'quote']) token: base[token]!.copyWith(color: readable(colors.onSurfaceVariant)),
      for (final token in ['keyword', 'selector-tag', 'literal', 'type'])
        token: TextStyle(color: readable(colors.primary)),
      for (final token in ['attr', 'attribute', 'property', 'title', 'name', 'built_in'])
        token: TextStyle(color: readable(colors.secondary)),
      for (final token in ['number', 'symbol', 'variable', 'params'])
        token: TextStyle(color: readable(colors.tertiary)),
      for (final token in ['string', 'regexp', 'addition']) token: TextStyle(color: readable(stringColor(brightness))),
      'deletion': TextStyle(color: readable(colors.error)),
    };
  }
}

class _BuiltInTheme extends ThemePreset {
  static final Map<(_BuiltInTheme, Brightness), ColorScheme> _schemes = {};

  @override
  final String name;
  final String _lightLabel;
  final String _darkLabel;
  final _PresetPalette? _light;
  final _PresetPalette? _dark;

  const _BuiltInTheme(this.name, this._lightLabel, this._darkLabel, [this._light, this._dark]);

  _PresetPalette? _palette(Brightness brightness) => brightness == Brightness.dark ? _dark : _light;

  @override
  bool get usesDefaultSyntax => _light == null;

  @override
  String label(Brightness brightness) => brightness == Brightness.dark ? _darkLabel : _lightLabel;

  @override
  ColorScheme? colorScheme(Brightness brightness) {
    final palette = _palette(brightness);
    return palette == null ? null : _schemes.putIfAbsent((this, brightness), () => palette.colorScheme(brightness));
  }

  @override
  List<Color> swatches(Brightness brightness) => [
        if (_palette(brightness) case final palette?)
          for (final color in [palette.surface, palette.primary, palette.secondary, palette.tertiary]) Color(color),
      ];

  @override
  Color stringColor(Brightness brightness) {
    if (_palette(brightness) case final palette?) return Color(palette.string);
    final base = brightness == Brightness.dark ? atomOneDarkTheme : atomOneLightTheme;
    return base['string']!.color!;
  }
}

class ActiveThemePreset extends ThemeExtension<ActiveThemePreset> {
  final ThemePreset preset;
  final EditorColorScheme editorScheme;

  const ActiveThemePreset(this.preset, [this.editorScheme = EditorColorScheme.followTheme]);

  static ThemePreset of(BuildContext context) =>
      Theme.of(context).extension<ActiveThemePreset>()?.preset ?? ThemePreset.custom;

  @override
  ActiveThemePreset copyWith({ThemePreset? preset, EditorColorScheme? editorScheme}) =>
      ActiveThemePreset(preset ?? this.preset, editorScheme ?? this.editorScheme);

  @override
  ActiveThemePreset lerp(ActiveThemePreset? other, double t) => t < .5 ? this : other ?? this;
}

enum EditorColorScheme {
  followTheme(),
  atomOne(ThemePreset.atomOne, 'Atom One'),
  catppuccin(ThemePreset.catppuccin, 'Catppuccin');

  final ThemePreset? preset;
  final String? paletteLabel;

  const EditorColorScheme([this.preset, this.paletteLabel]);

  static EditorColorScheme fromConfig(Object? value) => switch (value) {
        'atomOne' || 'atomOneDark' || 'atomOneLight' => atomOne,
        'catppuccin' || 'catppuccinMocha' || 'catppuccinLatte' => catppuccin,
        _ => followTheme,
      };
}

Map<String, TextStyle> codeEditorTheme(
  BuildContext context, {
  bool followAppPalette = false,
  bool useAppSurface = false,
}) {
  final theme = Theme.of(context);
  final active = theme.extension<ActiveThemePreset>();
  final preference = followAppPalette ? null : active?.editorScheme.preset;
  final preset = preference ?? active?.preset ?? ThemePreset.custom;
  final brightness = theme.brightness;
  final colors = preference?.colorScheme(brightness) ?? theme.colorScheme;
  final syntax = preset.syntax(brightness, scheme: colors);
  final root = syntax['root']!;
  final surface = useAppSurface ? theme.colorScheme.surface : colors.surface;
  final foreground = _editorReadableColor(root.color!, theme.colorScheme.onSurface, surface);

  return {
    for (final entry in syntax.entries)
      if (entry.key == 'root')
        'root': root.copyWith(color: foreground, backgroundColor: surface)
      else
        entry.key: entry.value.color == null
            ? entry.value
            : entry.value.copyWith(
                color: _editorReadableColor(
                  entry.value.color!,
                  foreground,
                  useAppSurface ? surface : entry.value.backgroundColor ?? surface,
                ),
              ),
  };
}

ValueKey<(Object?, int)> codeEditorThemeKey(Object? identity, Map<String, TextStyle> styles) =>
    ValueKey((identity, Object.hashAllUnordered(styles.entries.map((entry) => Object.hash(entry.key, entry.value)))));

Color _editorReadableColor(Color color, Color fallback, Color background) {
  final luminance = background.computeLuminance();
  bool readable(Color foreground) {
    final text = foreground.computeLuminance();
    return (text > luminance ? (text + .05) / (luminance + .05) : (luminance + .05) / (text + .05)) >= 4.5;
  }

  if (readable(color)) return color;
  if (readable(fallback)) return fallback;
  return luminance > .179 ? Colors.black : Colors.white;
}

class _PresetPalette {
  final int surface;
  final int chrome;
  final int raised;
  final int border;
  final int text;
  final int muted;
  final int primary;
  final int secondary;
  final int tertiary;
  final int string;
  final int error;

  const _PresetPalette({
    required this.surface,
    required this.chrome,
    required this.raised,
    required this.border,
    required this.text,
    required this.muted,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.string,
    required this.error,
  });

  ColorScheme colorScheme(Brightness brightness) {
    final base = Color(surface);
    final foreground = Color(text);
    final primaryColor = Color(primary);
    final secondaryColor = Color(secondary);
    final tertiaryColor = Color(tertiary);
    final errorColor = Color(error);
    final dark = brightness == Brightness.dark;
    Color tint(Color color) => Color.alphaBlend(color.withValues(alpha: dark ? .16 : .09), base);
    Color onAccent(Color color) => color.computeLuminance() > .179 ? Colors.black : Colors.white;

    return ColorScheme.fromSeed(seedColor: primaryColor, brightness: brightness).copyWith(
      primary: primaryColor,
      onPrimary: onAccent(primaryColor),
      primaryContainer: tint(primaryColor),
      onPrimaryContainer: foreground,
      secondary: secondaryColor,
      onSecondary: onAccent(secondaryColor),
      secondaryContainer: tint(secondaryColor),
      onSecondaryContainer: foreground,
      tertiary: tertiaryColor,
      onTertiary: onAccent(tertiaryColor),
      tertiaryContainer: tint(tertiaryColor),
      onTertiaryContainer: foreground,
      error: errorColor,
      onError: onAccent(errorColor),
      errorContainer: tint(errorColor),
      onErrorContainer: foreground,
      surface: base,
      surfaceTint: Colors.transparent,
      surfaceDim: Color(chrome),
      surfaceBright: dark ? Color(raised) : base,
      surfaceContainerLowest: dark ? Color(chrome) : base,
      surfaceContainerLow: Color(chrome),
      surfaceContainer: Color(raised),
      surfaceContainerHigh: Color.lerp(Color(raised), Color(border), .35),
      surfaceContainerHighest: Color(border),
      onSurface: foreground,
      onSurfaceVariant: Color(muted),
      outline: Color(muted),
      outlineVariant: Color(border),
    );
  }
}

const _atomOneDark = _PresetPalette(
  surface: 0xFF282C34,
  chrome: 0xFF21252B,
  raised: 0xFF2A2F38,
  border: 0xFF3B414D,
  text: 0xFFABB2BF,
  muted: 0xFF98A1B1,
  primary: 0xFFC678DD,
  secondary: 0xFF61AFEF,
  tertiary: 0xFFE5C07B,
  string: 0xFF98C379,
  error: 0xFFE87982,
);

const _atomOneLight = _PresetPalette(
  surface: 0xFFFAFAFA,
  chrome: 0xFFF0F0F1,
  raised: 0xFFF5F5F6,
  border: 0xFFDFE1E5,
  text: 0xFF383A42,
  muted: 0xFF62656F,
  primary: 0xFFA626A4,
  secondary: 0xFF2754B5,
  tertiary: 0xFF8A5D00,
  string: 0xFF397531,
  error: 0xFFCA1243,
);

const _catppuccinMocha = _PresetPalette(
  surface: 0xFF1E1E2E,
  chrome: 0xFF181825,
  raised: 0xFF252536,
  border: 0xFF45475A,
  text: 0xFFCDD6F4,
  muted: 0xFFA6ADC8,
  primary: 0xFFB4BEFE,
  secondary: 0xFF94E2D5,
  tertiary: 0xFFFAB387,
  string: 0xFFA6E3A1,
  error: 0xFFF38BA8,
);

const _catppuccinLatte = _PresetPalette(
  surface: 0xFFEFF1F5,
  chrome: 0xFFE6E9EF,
  raised: 0xFFE9EBF1,
  border: 0xFFCCD0DA,
  text: 0xFF4C4F69,
  muted: 0xFF5C5F77,
  primary: 0xFF7629D0,
  secondary: 0xFF167178,
  tertiary: 0xFF9D5315,
  string: 0xFF347225,
  error: 0xFFC20E34,
);

const _rosePine = _PresetPalette(
  surface: 0xFF191724,
  chrome: 0xFF14121E,
  raised: 0xFF1F1D2E,
  border: 0xFF403D52,
  text: 0xFFE0DEF4,
  muted: 0xFFA09BB8,
  primary: 0xFFC4A7E7,
  secondary: 0xFF9CCFD8,
  tertiary: 0xFFEBBCBA,
  string: 0xFFF6C177,
  error: 0xFFEB6F92,
);

const _rosePineDawn = _PresetPalette(
  surface: 0xFFFAF4ED,
  chrome: 0xFFF2E9E1,
  raised: 0xFFF6EFE8,
  border: 0xFFDFDAD9,
  text: 0xFF575279,
  muted: 0xFF68627E,
  primary: 0xFF82558F,
  secondary: 0xFF286983,
  tertiary: 0xFF96534B,
  string: 0xFF816022,
  error: 0xFF944A64,
);

const _claudeLight = _PresetPalette(
  surface: 0xFFF4F3EE,
  chrome: 0xFFEBE8DF,
  raised: 0xFFF0EDE5,
  border: 0xFFDED8CA,
  text: 0xFF302923,
  muted: 0xFF63594E,
  primary: 0xFF963F27,
  secondary: 0xFF59513F,
  tertiary: 0xFF795400,
  string: 0xFF42602D,
  error: 0xFF9F3033,
);

const _claudeDark = _PresetPalette(
  surface: 0xFF26201B,
  chrome: 0xFF1D1815,
  raised: 0xFF2D2620,
  border: 0xFF43362C,
  text: 0xFFF4F3EE,
  muted: 0xFFB1ADA1,
  primary: 0xFFF29672,
  secondary: 0xFFC8BBA5,
  tertiary: 0xFFE4BE7E,
  string: 0xFFB0C68C,
  error: 0xFFF19895,
);

const _appleLight = _PresetPalette(
  surface: 0xFFFFFFFF,
  chrome: 0xFFF5F5F7,
  raised: 0xFFF8F8FA,
  border: 0xFFDEE0E5,
  text: 0xFF1D1D1F,
  muted: 0xFF51535A,
  primary: 0xFF005BB8,
  secondary: 0xFF46556D,
  tertiary: 0xFF4D5368,
  string: 0xFF31603E,
  error: 0xFFA02435,
);

const _appleDark = _PresetPalette(
  surface: 0xFF1D1D1F,
  chrome: 0xFF151517,
  raised: 0xFF252527,
  border: 0xFF36363B,
  text: 0xFFF5F5F7,
  muted: 0xFFB6B6BF,
  primary: 0xFF72B5FF,
  secondary: 0xFFB5C3D9,
  tertiary: 0xFFCAC4DC,
  string: 0xFFA8D1B4,
  error: 0xFFFFA3AB,
);

const _gmailLight = _PresetPalette(
  surface: 0xFFFFF8F8,
  chrome: 0xFFF8ECEE,
  raised: 0xFFFDF0F1,
  border: 0xFFF1DADE,
  text: 0xFF321E22,
  muted: 0xFF665056,
  primary: 0xFFA51F1D,
  secondary: 0xFF1B51A7,
  tertiary: 0xFF785400,
  string: 0xFF206A39,
  error: 0xFF891847,
);

const _gmailDark = _PresetPalette(
  surface: 0xFF2A1B20,
  chrome: 0xFF21151A,
  raised: 0xFF332229,
  border: 0xFF4A303B,
  text: 0xFFFFEFF1,
  muted: 0xFFCAB1BA,
  primary: 0xFFFFA29B,
  secondary: 0xFFA5C5FF,
  tertiary: 0xFFFBBC04,
  string: 0xFF8FD6A6,
  error: 0xFFFFA7D0,
);

const _figmaLight = _PresetPalette(
  surface: 0xFFFAF7FF,
  chrome: 0xFFF0E9FD,
  raised: 0xFFF5EEFF,
  border: 0xFFE3D6F6,
  text: 0xFF271E38,
  muted: 0xFF5B4D70,
  primary: 0xFF12633A,
  secondary: 0xFF5930A5,
  tertiary: 0xFF974114,
  string: 0xFF005D9A,
  error: 0xFFA22839,
);

const _figmaDark = _PresetPalette(
  surface: 0xFF211D2B,
  chrome: 0xFF18151F,
  raised: 0xFF2A2437,
  border: 0xFF3E334D,
  text: 0xFFF9F3FF,
  muted: 0xFFC2B5D6,
  primary: 0xFF24CB71,
  secondary: 0xFFC7A8FF,
  tertiary: 0xFFFFA47D,
  string: 0xFF78C8FF,
  error: 0xFFFF9BA2,
);
