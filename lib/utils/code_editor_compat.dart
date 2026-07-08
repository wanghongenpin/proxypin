import 'package:flutter/widgets.dart';
import 'package:flutter_code_editor/src/search/controller.dart';

export 'package:flutter_code_editor/src/search/controller.dart' show CodeSearchController;
export 'package:flutter_code_editor/src/search/result.dart' show SearchResult;
export 'package:flutter_code_editor/src/search/search_navigation_controller.dart' show SearchNavigationController;
export 'package:flutter_code_editor/src/search/settings_controller.dart' show SearchSettingsController;
export 'package:flutter_code_editor/src/search/widget/search_widget.dart' show SearchWidget;

/// Extension to make CodeSearchController compatible with old FindController API
extension CodeSearchControllerCompat on CodeSearchController {
  /// Show/hide search panel
  void toggleActive() {
    if (shouldShow) {
      hideSearch(returnFocusToCodeField: true);
    } else {
      showSearch();
    }
  }

  /// Is search panel visible
  bool get isActive => shouldShow;

  /// Number of matches
  int get matchCount => navigationController.value.totalMatchCount;

  /// Go to next match
  void next() => navigationController.moveNext();

  /// Go to previous match
  void previous() => navigationController.movePrevious();

  /// Regex toggle
  bool get isRegex => settingsController.value.isRegExp;

  set isRegex(bool value) {
    settingsController.value = settingsController.value.copyWith(isRegExp: value);
  }

  void toggleRegex() {
    settingsController.value = settingsController.value.copyWith(isRegExp: !isRegex);
  }

  /// Case sensitivity toggle
  bool get caseSensitive => settingsController.value.isCaseSensitive;

  void toggleCaseSensitivity() {
    settingsController.value = settingsController.value.copyWith(isCaseSensitive: !caseSensitive);
  }

  /// Pattern input controller (for compatibility)
  TextEditingController get findInputController => settingsController.patternController;

  /// Pattern focus node (for compatibility)
  FocusNode get findInputFocusNode => patternFocusNode;

  /// Pattern input controller (alias)
  TextEditingController get inputController => settingsController.patternController;

  /// Pattern focus node (alias)
  FocusNode get focusNode => patternFocusNode;

  /// Current match index
  int get currentMatchIndex => navigationController.value.currentMatchIndex ?? 0;

  /// isActive setter
  set isActive(bool value) {
    if (value) {
      showSearch();
    } else {
      hideSearch(returnFocusToCodeField: true);
    }
  }

  /// Toggle replace mode (noop for compatibility)
  void toggleReplaceMode() {}

  /// Match whole word (always false for compatibility)
  bool get matchWholeWord => false;

  /// Toggle match whole word (noop for compatibility)
  void toggleMatchWholeWord() {}

  // Note: Replace functionality is not available in this version of flutter_code_editor
  // These are no-op stubs for compatibility
  bool get isReplaceMode => false;

  TextEditingController get replaceInputController => TextEditingController();

  FocusNode get replaceInputFocusNode => FocusNode();

  void replace() {}

  void replaceAll() {}

  bool get selectWholeDefault => false;

  bool get selectWhole => false;

  set selectWhole(bool value) {}
}
