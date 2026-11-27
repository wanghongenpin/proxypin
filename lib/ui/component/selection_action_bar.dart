import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';
import 'package:proxypin/utils/listenable_list.dart';

class SelectionActionBar extends StatelessWidget {
  final MultiSelectController selectionController;
  final VoidCallback? onRepeat;
  final VoidCallback? onExport;
  final VoidCallback? onDelete;

  ///全选/取消全选回调，为 null 时不显示全选按钮
  final VoidCallback? onSelectAll;

  ///当前可见请求条数，用于判断是否已全选
  final ValueGetter<int>? visibleCount;

  const SelectionActionBar(
      {super.key,
      required this.selectionController,
      this.onRepeat,
      this.onExport,
      this.onDelete,
      this.onSelectAll,
      this.visibleCount});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return SizedBox(
        height: 36,
        child: Row(children: [
          const SizedBox(width: 8),
          if (onSelectAll != null)
            _SelectAllButton(
                selectionController: selectionController,
                visibleCount: visibleCount,
                onPressed: onSelectAll!),
          _SelectLabel(selectionController: selectionController),
          const Spacer(),
          if (onRepeat != null)
            IconButton(onPressed: onRepeat, tooltip: localizations?.repeat, icon: const Icon(Icons.repeat, size: 18)),
          if (onExport != null)
            IconButton(
                onPressed: onExport, tooltip: localizations?.export, icon: const Icon(Icons.share_outlined, size: 18)),
          if (onDelete != null)
            IconButton(
                onPressed: onDelete, tooltip: localizations?.delete, icon: const Icon(Icons.delete_outline, size: 18)),
          IconButton(onPressed: _onCancel, tooltip: localizations?.cancel, icon: const Icon(Icons.close, size: 18)),
        ]));
  }

  void _onCancel() {
    selectionController.clear();
  }
}

class _SelectLabel extends StatefulWidget {
  final MultiSelectController selectionController;

  const _SelectLabel({required this.selectionController});

  @override
  State<StatefulWidget> createState() => _SelectLabelState();
}

class _SelectLabelState extends State<_SelectLabel> {
  late final OnchangeListEvent<String> _listener;

  @override
  void initState() {
    super.initState();
    _listener = OnchangeListEvent(_onSelectionChanged);
    widget.selectionController.selectedIds.addListener(_listener);
  }

  @override
  void dispose() {
    widget.selectionController.selectedIds.removeListener(_listener);
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = widget.selectionController.selectedIds.length;
    final label = AppLocalizations.of(context)?.selectedItems(selectedCount) ?? '$selectedCount';

    return Text(label, style: Theme.of(context).textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

class ClearSelectionIntent extends Intent {
  const ClearSelectionIntent();
}

class _SelectAllButton extends StatefulWidget {
  final MultiSelectController selectionController;
  final ValueGetter<int>? visibleCount;
  final VoidCallback onPressed;

  const _SelectAllButton({required this.selectionController, required this.visibleCount, required this.onPressed});

  @override
  State<StatefulWidget> createState() => _SelectAllButtonState();
}

class _SelectAllButtonState extends State<_SelectAllButton> {
  late final OnchangeListEvent<String> _listener;

  @override
  void initState() {
    super.initState();
    _listener = OnchangeListEvent(_onSelectionChanged);
    widget.selectionController.selectedIds.addListener(_listener);
  }

  @override
  void dispose() {
    widget.selectionController.selectedIds.removeListener(_listener);
    super.dispose();
  }

  void _onSelectionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.visibleCount?.call() ?? 0;
    final selectedCount = widget.selectionController.selectedIds.length;
    final allSelected = total > 0 && selectedCount >= total;

    return IconButton(
        onPressed: widget.onPressed,
        tooltip: AppLocalizations.of(context)?.selectAll,
        icon: Icon(allSelected ? Icons.deselect_outlined : Icons.select_all_outlined, size: 18));
  }
}
