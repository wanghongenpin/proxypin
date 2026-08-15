/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/request_tree.dart';

/// Builds the row of a request sitting at [style] in the tree. Desktop and
/// mobile pass their own row widget so that every existing behaviour of a
/// request row (context menu, selection, colors) keeps working inside the tree.
typedef RequestTreeLeafBuilder = Widget Function(HttpRequest request, RequestTreeStyle style);

/// Renders the children of a domain as a path tree.
///
/// The domain row itself is drawn by the caller; this widget only draws what
/// lives below it, so it stays usable from both the desktop panel and the
/// mobile page.
class RequestTreeView extends StatelessWidget {
  final RequestTreeNode root;
  final RequestTreeExpansion expansion;
  final RequestTreeLeafBuilder leafBuilder;

  /// Line the keyboard is currently on, null when the tree has no cursor.
  final ValueListenable<String?>? cursor;

  /// Anchor placed right above the line under the cursor, so the caller can
  /// scroll it into view.
  final GlobalKey? cursorAnchor;

  /// Called when a folder line is clicked, so the caller can move the keyboard
  /// cursor onto it.
  final ValueChanged<String>? onFolderTap;

  const RequestTreeView({
    super.key,
    required this.root,
    required this.expansion,
    required this.leafBuilder,
    this.cursor,
    this.cursorAnchor,
    this.onFolderTap,
  });

  @override
  Widget build(BuildContext context) {
    var listenable = cursor == null ? expansion : Listenable.merge([expansion, cursor!]);

    return ListenableBuilder(
        listenable: listenable,
        builder: (context, _) {
          var current = cursor?.value;
          var children = <Widget>[];

          for (var row in RequestTree.visibleRows(root, expansion)) {
            if (cursorAnchor != null && current == row.key) {
              children.add(SizedBox(key: cursorAnchor, height: 0));
            }
            children.add(KeyedSubtree(key: ValueKey(row.key), child: _row(context, row, current == row.key)));
          }

          return Column(mainAxisSize: MainAxisSize.min, children: children);
        });
  }

  Widget _row(BuildContext context, RequestTreeRow row, bool underCursor) {
    if (!row.isFolder) {
      return leafBuilder(row.request!, RequestTreeStyle(label: row.label, depth: row.depth, rowKey: row.key));
    }

    var folder = RequestTreeFolderRow(
        row: row,
        expanded: expansion.isExpanded(row.key),
        onTap: () {
          expansion.toggle(row.key);
          onFolderTap?.call(row.key);
        });

    if (!underCursor) {
      return folder;
    }

    return Container(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12), child: folder);
  }
}

/// Dropdown picking the layout of the captured list, shared by the desktop and
/// mobile preference pages so both stay worded the same.
class RequestViewModeDropdown extends StatelessWidget {
  final ValueNotifier<RequestViewMode> viewMode;

  /// Called after the value changed, so the caller can persist it.
  final VoidCallback? onChanged;

  const RequestViewModeDropdown({super.key, required this.viewMode, this.onChanged});

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    return ValueListenableBuilder<RequestViewMode>(
        valueListenable: viewMode,
        builder: (context, mode, _) => DropdownButton<RequestViewMode>(
              value: mode,
              isDense: true,
              underline: const SizedBox(),
              style: Theme.of(context).textTheme.bodyMedium,
              items: [
                DropdownMenuItem(
                    value: RequestViewMode.list,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.list, size: 16),
                      const SizedBox(width: 6),
                      Text(localizations.requestViewList),
                    ])),
                DropdownMenuItem(
                    value: RequestViewMode.tree,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.account_tree_outlined, size: 16),
                      const SizedBox(width: 6),
                      Text(localizations.requestViewTree),
                    ])),
              ],
              onChanged: (value) {
                if (value == null || value == viewMode.value) {
                  return;
                }
                viewMode.value = value;
                onChanged?.call();
              },
            ));
  }
}

/// A single folder line: disclosure arrow, name, and how many requests the
/// whole subtree below it holds.
class RequestTreeFolderRow extends StatelessWidget {
  final RequestTreeRow row;
  final bool expanded;
  final VoidCallback onTap;

  const RequestTreeFolderRow({super.key, required this.row, required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
        minLeadingWidth: 25,
        leading: Icon(expanded ? Icons.arrow_drop_down : Icons.arrow_right, size: 18),
        dense: true,
        horizontalTitleGap: 0,
        contentPadding: EdgeInsets.only(left: 3 + row.depth * RequestTreeStyle.indentStep, right: 8),
        visualDensity: const VisualDensity(vertical: -4),
        minTileHeight: RequestTreeStyle.rowHeight,
        minVerticalPadding: 0,
        title: Text(row.label,
            textAlign: TextAlign.left,
            style: const TextStyle(fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        //Only the number is shown; hovering spells it out, so the line stays uncluttered
        trailing: Tooltip(
            message: AppLocalizations.of(context)!.treeNodeSubtitle(row.node.requestCount),
            child: Text('${row.node.requestCount}', style: const TextStyle(fontSize: 11, color: Colors.grey))),
        onTap: onTap);
  }
}
