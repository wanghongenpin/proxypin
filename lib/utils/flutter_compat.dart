import 'package:flutter/material.dart';

/// Compatibility helpers for small Flutter API differences used in this project.
///
/// Provides:
/// - Color/MaterialColor.withValues({double? alpha, Map<int, Color>? values})
///   to emulate older/newer helper methods used in the codebase.
/// - BuildContext.colorScheme getter as a convenience.

/// Provide a small set of ColorScheme getters that may be referenced in code
/// compiled against newer Flutter SDKs. These return reasonable fallbacks so
/// code can compile against older SDKs as well.
extension ColorSchemeCompat on ColorScheme {
  /// A lightweight surface color variant used throughout the app. If the
  /// newer `surfaceContainerLow` semantic is available in the SDK it would be
  /// preferred; here we emulate it with a slightly transparent surface color.
  Color get surfaceContainerLow => surface.withOpacity(0.05);

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

