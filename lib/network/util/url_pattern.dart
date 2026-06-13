/// Shared URL wildcard-to-regex conversion utilities.
///
/// Many rule classes (rewrite, map, block, hosts, script, report-server, host-filter)
/// convert user-facing wildcard patterns (`*`, `?`) into [RegExp].
/// This file centralises that logic so changes to escaping or expansion
/// only need to happen in one place.
class UrlPattern {
  UrlPattern._();

  /// Convert a user-facing wildcard [pattern] to a [RegExp].
  ///
  /// `*` is expanded to `.*` and the first literal `?` is escaped to `\?`.
  static RegExp toRegExp(String pattern) {
    return RegExp(toRegExpString(pattern));
  }

  /// Return the regex source string for a wildcard [pattern]
  /// without wrapping it in [RegExp] — useful when callers
  /// need to cache or compare the raw string.
  static String toRegExpString(String pattern) {
    return pattern.replaceAll("*", ".*").replaceFirst('?', '\\?');
  }

  /// Simpler variant used by host / domain matching where only
  /// `*` → `.*` expansion is needed (no `?` escaping).
  static RegExp toHostRegExp(String pattern) {
    return RegExp(pattern.replaceAll("*", ".*"));
  }
}
