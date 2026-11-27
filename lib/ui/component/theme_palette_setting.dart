import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/component/theme_presets.dart';
import 'package:proxypin/ui/configuration.dart';

class ThemePaletteSetting extends StatelessWidget {
  final AppConfiguration configuration;

  const ThemePaletteSetting(this.configuration, {super.key});

  @override
  Widget build(BuildContext context) {
    final labels = AppLocalizations.of(context)!;
    final brightness = Theme.brightnessOf(context);
    return ListenableBuilder(
      listenable: configuration.globalChange,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<ThemePreset>(
            initialValue: configuration.themePreset,
            isExpanded: true,
            decoration: InputDecoration(labelText: labels.themePalette),
            items: [
              for (final preset in ThemePreset.values)
                DropdownMenuItem(
                  value: preset,
                  child: Row(children: [
                    Flexible(
                      child: Text(
                        preset == ThemePreset.custom ? labels.themePaletteDefault : preset.label(brightness),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    for (final color in preset.swatches(brightness))
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 4),
                        child: CircleAvatar(radius: 4, backgroundColor: color),
                      ),
                  ]),
                ),
            ],
            onChanged: (preset) {
              if (preset != null) configuration.themePreset = preset;
            },
          ),
          DropdownButtonFormField<EditorColorScheme>(
            initialValue: configuration.editorColorScheme,
            isExpanded: true,
            decoration: InputDecoration(labelText: labels.editorColorScheme),
            items: [
              for (final scheme in EditorColorScheme.values)
                DropdownMenuItem(
                  value: scheme,
                  child:
                      Text(scheme.paletteLabel ?? labels.editorColorSchemeFollowTheme, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (scheme) {
              if (scheme != null) configuration.editorColorScheme = scheme;
            },
          ),
        ],
      ),
    );
  }
}
