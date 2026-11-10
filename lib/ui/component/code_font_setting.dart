import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/utils/system_fonts.dart';

/// 「代码字体」列表项：请求体 / 响应体 / 脚本编辑器等代码窗口共用的字体族。
class CodeFontFamilyTile extends StatefulWidget {
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final bool showSubtitle;

  const CodeFontFamilyTile({super.key, this.titleStyle, this.subtitleStyle, this.showSubtitle = true});

  @override
  State<CodeFontFamilyTile> createState() => _CodeFontFamilyTileState();
}

class _CodeFontFamilyTileState extends State<CodeFontFamilyTile> {
  static const String _systemMono = '__system_mono__';
  static const String _custom = '__custom__';

  List<String> _families = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    SystemFonts.monospaceFamilies().then((families) {
      if (!mounted) {
        return;
      }
      setState(() {
        _families = families;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final config = AppConfiguration.current;
    final current = config?.editorFontFamily;

    // 当前值是自定义/不常见字体时也要能显示出来
    final items = <DropdownMenuItem<String?>>[
      DropdownMenuItem(value: null, child: Text(localizations.codeFontFollowUi)),
      DropdownMenuItem(value: _systemMono, child: Text(localizations.codeFontSystemMono)),
      ..._families.map((family) => DropdownMenuItem(value: family, child: Text(family))),
      if (current != null &&
          current.isNotEmpty &&
          current != SystemFonts.systemMonospaceFamily &&
          !_families.contains(current))
        DropdownMenuItem(value: current, child: Text(current)),
      DropdownMenuItem(value: _custom, child: Text(localizations.codeFontCustom)),
    ];

    var value = current == null || current.isEmpty ? null : current;
    if (value == SystemFonts.systemMonospaceFamily) {
      value = _systemMono;
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(localizations.codeFont, style: widget.titleStyle),
      subtitle: widget.showSubtitle
          ? Text(localizations.codeFontSubtitle, style: widget.subtitleStyle ?? const TextStyle(fontSize: 12))
          : null,
      trailing: SizedBox(
        width: 200,
        child: DropdownButton<String?>(
          value: value,
          isExpanded: true,
          focusColor: Colors.transparent,
          hint:
              _loading ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)) : null,
          onChanged: (selected) async {
            if (selected == _custom) {
              final family = await _askFontFamily(context, current);
              if (family == null) {
                return;
              }
              config?.applyDisplaySetting(() => config.editorFontFamily = family.trim().isEmpty ? null : family.trim());
            } else if (selected == _systemMono) {
              config?.applyDisplaySetting(() => config.editorFontFamily = SystemFonts.systemMonospaceFamily);
            } else {
              config?.applyDisplaySetting(() => config.editorFontFamily = selected);
            }
            if (mounted) {
              setState(() {});
            }
          },
          items: items,
        ),
      ),
    );
  }

  Future<String?> _askFontFamily(BuildContext context, String? current) async {
    final localizations = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: current ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(localizations.codeFontCustom),
          content: SizedBox(
            width: 320,
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: localizations.codeFontFamily,
                hintText: 'JetBrains Mono',
              ),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(localizations.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(localizations.confirm)),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }
}

/// 「代码字体」列表项：字号。
class CodeFontSizeTile extends StatelessWidget {
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final bool showSubtitle;

  const CodeFontSizeTile({super.key, this.titleStyle, this.subtitleStyle, this.showSubtitle = true});

  static const List<double> sizes = [10, 11, 12, 12.5, 13, 13.5, 14, 15, 16, 18, 20];

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final config = AppConfiguration.current;
    final current = config?.editorFontSize ?? 13;
    final values = sizes.contains(current) ? sizes : ([...sizes, current]..sort());

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(localizations.codeFontSize, style: titleStyle),
      subtitle: showSubtitle
          ? Text(localizations.codeFontSizeSubtitle, style: subtitleStyle ?? const TextStyle(fontSize: 12))
          : null,
      trailing: SizedBox(
        width: 200,
        child: DropdownButton<double>(
          value: current,
          isExpanded: true,
          focusColor: Colors.transparent,
          onChanged: (size) {
            if (size == null) {
              return;
            }
            config?.applyDisplaySetting(() => config.editorFontSize = size);
          },
          items: values
              .map((size) => DropdownMenuItem<double>(
                  value: size, child: Text(size == size.roundToDouble() ? '${size.toInt()}' : '$size')))
              .toList(),
        ),
      ),
    );
  }
}

/// 「抓包列表密度」列表项（宽松 / 紧凑 / 极紧凑）。
class CaptureDensityTile extends StatelessWidget {
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final bool showSubtitle;

  const CaptureDensityTile({super.key, this.titleStyle, this.subtitleStyle, this.showSubtitle = true});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final config = AppConfiguration.current;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(localizations.captureListDensity, style: titleStyle),
      subtitle: showSubtitle
          ? Text(localizations.captureListDensitySubtitle, style: subtitleStyle ?? const TextStyle(fontSize: 12))
          : null,
      trailing: SizedBox(
        width: 200,
        child: DropdownButton<String>(
          value: config?.captureListDensity ?? 'comfortable',
          isExpanded: true,
          focusColor: Colors.transparent,
          onChanged: (value) {
            if (value == null) {
              return;
            }
            config?.applyDisplaySetting(() => config.captureListDensity = value);
          },
          items: [
            DropdownMenuItem(value: 'comfortable', child: Text(localizations.densityComfortable)),
            DropdownMenuItem(value: 'compact', child: Text(localizations.densityCompact)),
            DropdownMenuItem(value: 'dense', child: Text(localizations.densityDense)),
          ],
        ),
      ),
    );
  }
}
