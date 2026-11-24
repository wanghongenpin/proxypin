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

  ///选中当前可见的全部请求。空列表不处理。
  void selectAll(Iterable<String> ids) {
    final idList = ids.toList();
    if (idList.isEmpty) {
      return;
    }

    selectionMode.value = true;
    selectedIds
      ..clear()
      ..addAll(idList);
    _anchorId = idList.last;
  }

  ///清空选中但保留多选模式，便于取消全选后继续手动勾选
  void clearSelection() {
    selectedIds.clear();
    _anchorId = null;
    selectionMode.value = true;
  }

  ///全选/取消全选切换：当前可见项已全部选中时仅清空勾选（保留多选模式），否则全选。
  void toggleSelectAll(Iterable<String> ids) {
    final idList = ids.toList();
    if (idList.isEmpty) {
      return;
    }

    final selectedSet = selectedIds.toSet();
    if (idList.every(selectedSet.contains)) {
      clearSelection();
    } else {
      selectAll(idList);
    }
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
