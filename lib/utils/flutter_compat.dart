import 'package:flutter/material.dart';

/// Compatibility helpers for small Flutter API differences used in this project.
///
/// Provides:
/// - Color/MaterialColor.withValues({double? alpha, Map<int, Color>? values})
///   to emulate older/newer helper methods used in the codebase.
/// - BuildContext.colorScheme getter as a convenience.

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

