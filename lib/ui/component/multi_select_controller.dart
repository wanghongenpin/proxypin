import 'package:get/get.dart';
import 'package:proxypin/utils/listenable_list.dart';

class MultiSelectController {
  final ListenableList<String> selectedIds = ListenableList<String>();

  String? _anchorId;
  RxBool selectionMode = false.obs;

  bool get isSelectionMode => selectionMode.value;

  int get selectedCount => selectedIds.length;

  bool contains(String requestId) => selectedIds.contains(requestId);

  void clear() {
    if (selectedIds.isEmpty && !selectionMode.value) {
      return;
    }
    selectedIds.clear();
    _anchorId = null;
    selectionMode.value = false;
  }

  void remove(String requestId) {
    selectedIds.remove(requestId);
  }

  void enterSelectionMode([String? requestId]) {
    selectionMode.value = true;
    if (requestId != null) {
      selectedIds.add(requestId);
      _anchorId = requestId;
    }
  }

  void selectOnly(String requestId) {
    selectionMode.value = true;
    selectedIds
      ..clear()
      ..add(requestId);
    _anchorId = requestId;
  }

  void toggleSelectionMode([String? requestId]) {
    if (selectionMode.value) {
      clear();
    } else {
      enterSelectionMode(requestId);
    }
  }

  void toggle(String requestId) {
    selectionMode.value = true;
    if (selectedIds.contains(requestId)) {
      selectedIds.remove(requestId);
    } else {
      selectedIds.add(requestId);
    }

    if (selectedIds.isEmpty) {
      clear();
      return;
    }

    _anchorId = requestId;
  }

  void selectRange(List<String> orderedIds, String requestId) {
    final targetIndex = orderedIds.indexOf(requestId);
    if (targetIndex < 0) {
      return;
    }

    final anchorIndex = _anchorId == null ? -1 : orderedIds.indexOf(_anchorId!);
    if (anchorIndex < 0) {
      selectOnly(requestId);
      return;
    }

    final start = anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final end = anchorIndex > targetIndex ? anchorIndex : targetIndex;
    selectionMode.value = true;
    selectedIds
      ..clear()
      ..addAll(orderedIds.sublist(start, end + 1));
    _anchorId = requestId;
  }

  void prune(Iterable<String> visibleIds) {
    final visibleIdSet = visibleIds.toSet();
    selectedIds.removeWhere((requestId) => !visibleIdSet.contains(requestId));

    if (selectedIds.isEmpty) {
      clear();
      return;
    }

    selectionMode.value = true;
    if (_anchorId == null || !selectedIds.contains(_anchorId)) {
      _anchorId = selectedIds.last;
    }
  }
}

class MultiSelectListener<T> extends ListenerListEvent<T> {
  final Function(List<T> items) onChange;

  MultiSelectListener(this.onChange);

  @override
  void onAdd(T item) => onChange.call([item]);

  @override
  void onRemove(T item) => onChange.call([item]);

  @override
  void onUpdate(T item) => onChange.call([item]);

  @override
  void onBatchRemove(List<T> items) => onChange.call(items);

  @override
  void clear(List<T> items) => onChange.call(items);
}
