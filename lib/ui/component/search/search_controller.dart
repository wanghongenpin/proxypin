import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/search/search_field.dart';

class SearchTextController extends ValueNotifier<SearchSettings> with WidgetsBindingObserver {
  SearchTextController() : super(SearchSettings.empty) {
    patternController.addListener(_onPatternControllerChanged);
    WidgetsBinding.instance.addObserver(this); // 添加监听器
  }

  final patternController = TextEditingController();
  RxInt currentMatchIndex = RxInt(0);
  RxInt totalMatchCount = RxInt(0);

  OverlayEntry? _searchPopup;
  double? overlayTop;
  double? overlayRight;

  bool shouldSearch() {
    return isSearchOverlayVisible && patternController.text.isNotEmpty;
  }

  void toggleCaseSensitivity() {
    value = value.copyWith(isCaseSensitive: !value.isCaseSensitive);
  }

  void toggleIsRegExp() {
    value = value.copyWith(isRegExp: !value.isRegExp);
  }

  void _onPatternControllerChanged() {
    value = value.copyWith(pattern: patternController.text, currentMatchIndex: 0);
    if (value.pattern.isEmpty) {
      currentMatchIndex.value = 0;
      totalMatchCount.value = 0;
    }
  }

  void updateMatchCount(int count) {
    totalMatchCount.value = count;
    if (currentMatchIndex.value > count) {
      currentMatchIndex.value = count;
    }
  }

  void movePrevious() {
    if (totalMatchCount.value == 0) return;
    if (currentMatchIndex.value == 0) {
      currentMatchIndex.value = totalMatchCount.value - 1;
    } else {
      currentMatchIndex.value--;
    }
    value = value.copyWith(currentMatchIndex: currentMatchIndex.value);
  }

  void moveNext() {
    if (totalMatchCount.value == 0) return;
    if (currentMatchIndex.value >= totalMatchCount.value - 1) {
      currentMatchIndex.value = 0;
    } else {
      currentMatchIndex.value++;
    }
    value = value.copyWith(currentMatchIndex: currentMatchIndex.value);
  }

  void closeSearch() {
    removeSearchOverlay();
  }

  void updateOverlayPosition(double top, double right) {
    overlayTop = top;
    overlayRight = right;
    if (_searchPopup != null) {
      _searchPopup!.markNeedsBuild();
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!isSearchOverlayVisible) {
      return;
    }

    // 检测键盘弹出并调整位置
    var view = WidgetsBinding.instance.platformDispatcher.views.first;
    final bottomInset = MediaQueryData.fromView(view).viewInsets.bottom;
    if (bottomInset == 0 || overlayTop == null) {
      // 键盘收起
      return;
    }

    var screenHeight = MediaQueryData.fromView(view).size.height;
    final currentHeight = screenHeight - bottomInset;
    if (overlayTop! + 50 > currentHeight) {
      // 如果被键盘遮挡
      updateOverlayPosition(max(currentHeight - 120, 120), overlayRight!); // 移动到键��上方
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 移除监听器
    logger.d('Disposing SearchTextController');
    super.didChangeMetrics();
    removeSearchOverlay();
    patternController.dispose();
    totalMatchCount.close();
    currentMatchIndex.close();
    super.dispose();
  }

  bool get isSearchOverlayVisible => _searchPopup != null;

  void showSearchOverlay(BuildContext context, {double? top, double? right}) {
    if (_searchPopup != null) {
      return;
    }

    _searchPopup = _buildSearchOverlay(context, top: top, right: right);
    Overlay.of(context).insert(_searchPopup!);
  }

  void removeSearchOverlay() {
    _searchPopup?.remove();
    _searchPopup = null;
  }

  OverlayEntry _buildSearchOverlay(BuildContext context, {double? top, double? right}) {
    overlayTop = top ?? overlayTop;
    overlayRight = right ?? overlayRight;
    return OverlayEntry(
      builder: (context) {
        return Positioned(
          top: overlayTop,
          right: overlayRight,
          child: Actions(actions: {
            DismissIntent: CallbackAction<DismissIntent>(onInvoke: (intent) {
              closeSearch();
              return null;
            }),
          }, child: SearchField(searchController: this)),
        );
      },
    );
  }
}

class SearchSettings {
  const SearchSettings({
    required this.isCaseSensitive,
    required this.isRegExp,
    required this.pattern,
    this.currentMatchIndex = 0,
  });

  final bool isCaseSensitive;
  final bool isRegExp;
  final String pattern;
  final int currentMatchIndex;

  static const empty = SearchSettings(
    isCaseSensitive: false,
    isRegExp: false,
    pattern: '',
  );

  SearchSettings copyWith({
    bool? isCaseSensitive,
    bool? isRegExp,
    String? pattern,
    int? currentMatchIndex,
  }) {
    return SearchSettings(
      isCaseSensitive: isCaseSensitive ?? this.isCaseSensitive,
      isRegExp: isRegExp ?? this.isRegExp,
      pattern: pattern ?? this.pattern,
      currentMatchIndex: currentMatchIndex ?? this.currentMatchIndex,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchSettings &&
          runtimeType == other.runtimeType &&
          isCaseSensitive == other.isCaseSensitive &&
          isRegExp == other.isRegExp &&
          pattern == other.pattern &&
          currentMatchIndex == other.currentMatchIndex;

  @override
  int get hashCode => isCaseSensitive.hashCode ^ isRegExp.hashCode ^ pattern.hashCode ^ currentMatchIndex.hashCode;
}
