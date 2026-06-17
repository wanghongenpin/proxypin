import 'package:flutter/material.dart';

/// Compatibility helpers for small Flutter API differences used in this project.
///
/// Provides:
/// - Color/MaterialColor.withValues({double? alpha, Map<int, Color>? values})
///   to emulate older/newer helper methods used in the codebase.
/// - BuildContext.colorScheme getter as a convenience.
/// - ThemeCompat.brightnessOf compatibility wrapper.
/// - ColorSchemeCompatStatic.of compatibility wrapper.
/// - EdgeInsetsGeometry.fromLTRB/symmetric compatibility.

/// Provide a small set of ColorScheme getters that may be referenced in code
/// compiled against newer Flutter SDKs. These return reasonable fallbacks so
/// code can compile against older SDKs as well.
extension ColorSchemeCompat on ColorScheme {
  /// A lightweight surface color variant used throughout the app. If the
  /// newer `surfaceContainerLow` semantic is available in the SDK it would be
  /// preferred; here we emulate it with a slightly transparent surface color.
  Color get surfaceContainerLow => surface.withOpacity(0.05);

  /// A higher-emphasis surface color variant.
  Color get surfaceContainerHighest => surface.withOpacity(0.25);

  /// A mild outline-like color. Emulated from onSurface with low opacity.
  Color get outlineVariant => onSurface.withOpacity(0.12);
}

extension ColorWithValues on Color {
  /// If [alpha] is provided, return this color with that opacity.
  /// If [values] is provided, return a MaterialColor constructed from this color value.
  /// Otherwise return `this`.
  Color withValues({double? alpha, Map<int, Color>? values}) {
    if (alpha != null) return withOpacity(alpha);
    if (values != null) return MaterialColor(value, values);
    return this;
  }
}

extension MaterialColorWithValues on MaterialColor {
  /// Mirror above semantics for MaterialColor.
  Color withValues({double? alpha, Map<int, Color>? values}) {
    if (values != null) return MaterialColor(this.value, values);
    if (alpha != null) return Color(this.value).withOpacity(alpha);
    return this;
  }
}

extension BuildContextColorScheme on BuildContext {
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
}

/// Theme compatibility wrapper
class ThemeCompat {
  static Brightness brightnessOf(BuildContext context) {
    return Theme.of(context).brightness;
  }
}

/// ColorScheme compatibility wrapper
class ColorSchemeCompatStatic {
  static ColorScheme of(BuildContext context) {
    return Theme.of(context).colorScheme;
  }
}

/// EdgeInsetsGeometry compatibility extension
extension EdgeInsetsGeometryCompat on EdgeInsetsGeometry {
  static EdgeInsets fromLTRB(double left, double top, double right, double bottom) {
    return EdgeInsets.fromLTRB(left, top, right, bottom);
  }

  static EdgeInsets symmetric({double vertical = 0.0, double horizontal = 0.0}) {
    return EdgeInsets.symmetric(vertical: vertical, horizontal: horizontal);
  }
}

