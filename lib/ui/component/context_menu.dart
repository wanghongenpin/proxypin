/*
 * Copyright 2023 Hongen Wang
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


/// Type of a [ContextMenuItem] entry.
enum ContextMenuItemType { normal, separator, checkbox, submenu }

/// A DTO for context menu entries. Used to build the right-click menu shown
/// on the request list and domain list.
///
/// Replaces the third-party `flutter_desktop_context_menu` plugin's [MenuItem].
/// That plugin's Windows implementation crashed because it kept the
/// [MethodChannel] in a file-level global that every plugin registration
/// overwrote — fatal in this app, which registers the plugin once per
/// `desktop_multi_window` window — and because it never called `DestroyMenu`
/// on the `HMENU` it allocated per popup.
class ContextMenuItem {
  final String? label;
  final ContextMenuItemType type;
  final bool disabled;
  final bool? checked;
  final List<ContextMenuItem>? submenu;
  final VoidCallback? onClick;

  const ContextMenuItem._({
    this.label,
    required this.type,
    this.disabled = false,
    this.checked,
    this.submenu,
    this.onClick,
  });

  /// A normal clickable item.
  const ContextMenuItem.normal({
    required String label,
    bool disabled = false,
    VoidCallback? onClick,
  }) : this._(
          label: label,
          type: ContextMenuItemType.normal,
          disabled: disabled,
          onClick: onClick,
        );

  /// A visual divider.
  const ContextMenuItem.separator()
      : this._(type: ContextMenuItemType.separator, disabled: true);

  /// A checkbox item whose [checked] state is rendered with a leading checkmark.
  const ContextMenuItem.checkbox({
    required String label,
    required bool checked,
    bool disabled = false,
    VoidCallback? onClick,
  }) : this._(
          label: label,
          type: ContextMenuItemType.checkbox,
          disabled: disabled,
          checked: checked,
          onClick: onClick,
        );

  /// An item that opens a nested submenu. The submenu opens automatically when
  /// the pointer hovers over the item, matching native menu behaviour.
  const ContextMenuItem.submenu({
    required String label,
    required List<ContextMenuItem> submenu,
    bool disabled = false,
  }) : this._(
          label: label,
          type: ContextMenuItemType.submenu,
          disabled: disabled,
          submenu: submenu,
        );
}

// Dimensions follow a Windows menu flyout, tightened a little for a denser
// list: 28dp rows (Fluent specifies 32, which felt airy here), 13px label,
// 8dp flyout corner radius, 4dp item corner radius, and items inset 4dp from
// the flyout edge so the hover highlight is a rounded pill rather than a
// full-bleed band.
const double _itemHeight = 28.0;
const double _fontSize = 13.0;
const double _iconColumn = 16.0;
const double _menuRadius = 8.0;
const double _itemRadius = 4.0;
const double _separatorHeight = 7.0;
const EdgeInsets _itemPadding = EdgeInsets.symmetric(horizontal: 12);
const EdgeInsets _menuPadding =
    EdgeInsets.symmetric(horizontal: 4, vertical: 3);

/// Show a context menu at [position] (global coordinates) built from [items].
///
/// Implemented with Flutter's built-in [MenuAnchor] / [SubmenuButton], so
/// submenus open on hover, arrow keys traverse the menu, and the menu flips
/// itself away from screen edges — all handled by Flutter.
///
/// A single [MenuAnchor] is kept mounted per [Overlay] and reused for every
/// showing. Inserting and removing an anchor per right-click instead makes the
/// engine's incremental accessibility merge fail ("Failed to update ui::AXTree
/// … will not be in the tree and is not the new root"), because the anchor's
/// [OverlayPortal] subtree comes and goes underneath it.
Future<void> showCustomContextMenu(
  BuildContext context,
  Offset position,
  List<ContextMenuItem> items,
) async {
  if (items.isEmpty) return;

  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _ContextMenuHost.of(overlay).show(position, items);
}

/// A persistent per-[Overlay] host for the context menu.
///
/// The host installs one [OverlayEntry] the first time a menu is shown in a
/// given overlay and then leaves it in place, so repeated right-clicks only
/// toggle the menu rather than rebuilding the anchor.
class _ContextMenuHost {
  _ContextMenuHost._();

  static final Map<OverlayState, _ContextMenuHost> _hosts =
      <OverlayState, _ContextMenuHost>{};

  static _ContextMenuHost of(OverlayState overlay) {
    return _hosts.putIfAbsent(overlay, () {
      final host = _ContextMenuHost._();
      host._install(overlay);
      return host;
    });
  }

  final GlobalKey<_ContextMenuAnchorState> _anchorKey =
      GlobalKey<_ContextMenuAnchorState>();
  OverlayEntry? _entry;

  void _install(OverlayState overlay) {
    _entry =
        OverlayEntry(builder: (context) => _ContextMenuAnchor(key: _anchorKey));
    overlay.insert(_entry!);
  }

  void show(Offset position, List<ContextMenuItem> items) {
    final state = _anchorKey.currentState;
    if (state != null) {
      state.show(position, items);
      return;
    }
    // The entry was inserted this frame and has not built yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorKey.currentState?.show(position, items);
    });
  }
}

/// The always-mounted anchor that positions and owns the menu.
class _ContextMenuAnchor extends StatefulWidget {
  const _ContextMenuAnchor({super.key});

  @override
  State<_ContextMenuAnchor> createState() => _ContextMenuAnchorState();
}

class _ContextMenuAnchorState extends State<_ContextMenuAnchor> {
  final MenuController _controller = MenuController();
  final FocusNode _anchorFocusNode =
      FocusNode(debugLabel: 'ContextMenu anchor');

  Offset _position = Offset.zero;
  List<ContextMenuItem> _items = const [];

  void show(Offset position, List<ContextMenuItem> items) {
    if (_controller.isOpen) _controller.close();
    setState(() {
      _position = position;
      _items = items;
    });
    // Let the anchor settle at its new position before the menu measures it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.open();
      // The anchor is always mounted, so it does not gain focus by itself the
      // way a freshly-inserted one would. Focus it explicitly, otherwise the
      // Escape handler below never sees the key event.
      _anchorFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _anchorFocusNode.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_controller.isOpen) _controller.close();
  }

  /// Escape must be handled here rather than relying on the menu's own
  /// [DismissMenuAction]: that lives inside the menu panel's focus scope, and
  /// opening the menu programmatically does not move focus into it.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _dismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      // A zero-sized anchor: the menu's default `topEnd` alignment then
      // resolves exactly to the cursor. Anchoring (rather than passing a
      // position to `open`) is what lets Flutter's menu layout apply its
      // screen-edge avoidance.
      child: MenuAnchor(
        controller: _controller,
        childFocusNode: _anchorFocusNode,
        consumeOutsideTap: true,
        style: _menuStyleOf(context),
        menuChildren: _buildMenuChildren(context, _items, _dismiss),
        // The anchor exists only to position the menu and to catch Escape.
        //
        // It must have a non-empty size: a zero-area anchor makes the engine's
        // incremental accessibility merge fail every time the menu opens
        // ("Failed to update ui::AXTree … will not be in the tree and is not
        // the new root"). Keep it tiny and out of the semantics tree instead.
        child: ExcludeSemantics(
          child: Focus(
            focusNode: _anchorFocusNode,
            onKeyEvent: _onKeyEvent,
            child: const SizedBox(width: 1, height: 1),
          ),
        ),
      ),
    );
  }
}

/// The flyout surface. Windows menus use a small corner radius, a hairline
/// border, and a soft shadow.
MenuStyle _menuStyleOf(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return MenuStyle(
    padding: MaterialStateProperty.all(_menuPadding),
    visualDensity: VisualDensity.compact,
    elevation: MaterialStateProperty.all(8),
    surfaceTintColor: MaterialStateProperty.all(Colors.transparent),
    backgroundColor: MaterialStateProperty.all(scheme.surface),
    shape: MaterialStateProperty.all(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_menuRadius),
        side: BorderSide(color: scheme.outlineVariant.withOpacity(0.6)),
      ),
    ),
  );
}

ButtonStyle _itemStyle(BuildContext context) {
  return MenuItemButton.styleFrom(
    // Pin the row height exactly. Three things fight this otherwise:
    //  - the ambient desktop VisualDensity shifts min/max sizes, so density is
    //    zeroed out here;
    //  - MaterialTapTargetSize.padded (the Material default) wraps each row in
    //    a 48dp minimum tap target, which spaced rows 48dp apart even though
    //    each row measured 28dp — shrinkWrap removes that padding;
    //  - minimumSize alone is not authoritative, so fixed/min/max all agree.
    fixedSize: const Size.fromHeight(_itemHeight),
    minimumSize: const Size(0, _itemHeight),
    maximumSize: const Size(double.infinity, _itemHeight),
    padding: _itemPadding,
    textStyle: const TextStyle(fontSize: _fontSize),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_itemRadius)),
  );
}

List<Widget> _buildMenuChildren(
  BuildContext context,
  List<ContextMenuItem> items,
  VoidCallback dismiss,
) {
  // Only reserve the leading checkmark gutter when this menu actually has a
  // checkbox item. Reserving it unconditionally would leave a blank column on
  // the left of menus that have nothing to check.
  final bool reserveGutter =
      items.any((i) => i.type == ContextMenuItemType.checkbox);
  return items
      .map((item) => _buildMenuChild(context, item, dismiss, reserveGutter))
      .toList();
}

Widget _buildMenuChild(
  BuildContext context,
  ContextMenuItem item,
  VoidCallback dismiss,
  bool reserveGutter,
) {
  switch (item.type) {
    case ContextMenuItemType.separator:
      // A bare Divider would collapse to zero width: the menu panel lays its
      // children out with loose width constraints and Divider's intrinsic
      // width is 0. Wrapping it in an Expanded inside a Row makes it fill the
      // panel width without widening the panel itself.
      return const Row(
          children: [Expanded(child: Divider(height: _separatorHeight))]);

    case ContextMenuItemType.checkbox:
      return MenuItemButton(
        style: _itemStyle(context),
        // Close before invoking the action ourselves, rather than letting
        // MenuItemButton do it: its own path defers onPressed to a post-frame
        // callback that reads `widget`, which throws once we have torn the
        // overlay down.
        closeOnActivate: false,
        onPressed: item.disabled
            ? null
            : () {
                dismiss();
                item.onClick?.call();
              },
        leadingIcon: _leading(reserveGutter, checked: item.checked ?? false),
        child: _label(item.label),
      );

    case ContextMenuItemType.submenu:
      return SubmenuButton(
        style: _itemStyle(context),
        menuStyle: _menuStyleOf(context),
        leadingIcon: _leading(reserveGutter),
        menuChildren: item.disabled
            ? const []
            : _buildMenuChildren(context, item.submenu ?? const [], dismiss),
        child: _label(item.label),
      );

    case ContextMenuItemType.normal:
      return MenuItemButton(
        style: _itemStyle(context),
        closeOnActivate: false,
        onPressed: item.disabled
            ? null
            : () {
                dismiss();
                item.onClick?.call();
              },
        leadingIcon: _leading(reserveGutter),
        child: _label(item.label),
      );
  }
}

/// The fixed-width leading gutter, holding a checkmark when [checked].
///
/// Returns null when [reserve] is false, i.e. when no item in this menu is a
/// checkbox — otherwise every label would be pushed right by an empty column.
/// When it is reserved, it is present on *every* item of the menu so that all
/// labels share one left edge.
Widget? _leading(bool reserve, {bool checked = false}) {
  if (!reserve) return null;
  return SizedBox(
    width: _iconColumn,
    child: checked ? const Icon(Icons.check, size: _iconColumn) : null,
  );
}

Widget _label(String? label) {
  return Text(label ?? '', overflow: TextOverflow.ellipsis, maxLines: 1);
}
