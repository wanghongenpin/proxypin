import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const EdgeInsetsGeometry _kFindMargin = EdgeInsets.only(right: 10);
const double _kFindPanelWidth = 360;
const double _kFindPanelHeight = 32;
const double _kReplacePanelHeight = _kFindPanelHeight * 2;
const double _kFindIconSize = 16;
const double _kFindIconWidth = 26;
const double _kFindIconHeight = 26;
const double _kFindInputFontSize = 13;
const double _kFindResultFontSize = 12;

class FindPanelView extends StatelessWidget implements PreferredSizeWidget {
  final FindController controller;

  const FindPanelView({super.key, required this.controller});

  @override
  Size get preferredSize => Size(
    double.infinity,
    !controller.isActive
        ? 0
        : (controller.isReplaceMode
        ? _kReplacePanelHeight
        : _kFindPanelHeight + 2) +
        _kFindMargin.vertical,
  );

  @override
  Widget build(BuildContext context) {
    if (!controller.isActive) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: _kFindMargin,
      alignment: Alignment.topRight,
      height: preferredSize.height,

      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (n, e) {
            if (e.logicalKey == LogicalKeyboardKey.escape) {
              controller.isActive = false;
              return KeyEventResult.handled;
            }
            if (e.logicalKey == LogicalKeyboardKey.tab &&
                controller.isReplaceMode &&
                controller.findInputFocusNode.hasFocus) {
              controller.replaceInputFocusNode.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Container(
            width: _kFindPanelWidth,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    controller.isReplaceMode
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                  ),
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(
                    maxWidth: 20,
                    minHeight: preferredSize.height,
                    maxHeight: preferredSize.height,
                  ),
                  tooltip: 'Toggle Replace',
                  onPressed: () {
                    controller.toggleReplaceMode();
                    // if (controller.isReplaceMode) {
                    //   controller.replaceInputFocusNode.requestFocus();
                    // }
                  },
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildFindRow(context),
                      if (controller.isReplaceMode) _buildReplaceRow(context),
                      if (!controller.isReplaceMode) const SizedBox(height: 2),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- FIND ROW ----------------

  Widget _buildFindRow(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: _kFindPanelWidth / 1.75,
          height: _kFindPanelHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _buildTextField(
                focusNode: controller.findInputFocusNode,
                controller: controller.findInputController,
                iconsWidth: _kFindIconWidth * 1.5,
                padding: EdgeInsets.only(left: 3, right: 5, top: 4, bottom: 2),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildCheckText(
                    context: context,
                    text: 'Aa',
                    checked: controller.caseSensitive,
                    onPressed: controller.toggleCaseSensitive,
                  ),
                  _buildCheckText(
                    context: context,
                    text: 'W',
                    checked: controller.matchWholeWord,
                    onPressed: controller.toggleMatchWholeWord,
                  ),
                  _buildCheckText(
                    context: context,
                    text: '.*',
                    checked: controller.isRegex,
                    onPressed: controller.toggleRegex,
                  ),
                ],
              ),
            ],
          ),
        ),
        _buildResultText(),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildIconButton(
                icon: Icons.arrow_upward,
                tooltip: 'Previous',
                onPressed: controller.matchCount == 0
                    ? null
                    : controller.previous,
              ),
              _buildIconButton(
                icon: Icons.arrow_downward,
                tooltip: 'Next',
                onPressed: controller.matchCount == 0 ? null : controller.next,
              ),
              _buildIconButton(
                icon: Icons.close,
                tooltip: 'Close',
                onPressed: controller.toggleActive,
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------- REPLACE ROW ----------------

  Widget _buildReplaceRow(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: _kFindPanelWidth / 1.75,
          height: _kFindPanelHeight,
          child: _buildTextField(
            focusNode: controller.replaceInputFocusNode,
            controller: controller.replaceInputController,
            padding: EdgeInsets.only(left: 3, right: 5, top: 2, bottom: 4),
            onSubmit: (_) {
              controller.replace();
              controller.replaceInputFocusNode.requestFocus();
            },
          ),
        ),
        _buildIconButton(
          icon: Icons.done,
          tooltip: 'Replace',
          onPressed: controller.matchCount == 0 ? null : controller.replace,
        ),
        _buildIconButton(
          icon: Icons.done_all,
          tooltip: 'Replace All',
          onPressed: controller.matchCount == 0 ? null : controller.replaceAll,
        ),
      ],
    );
  }

  // ---------------- WIDGETS ----------------

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    double iconsWidth = 0,
    EdgeInsets padding = EdgeInsets.zero,
    ValueChanged<String>? onSubmit,
  }) {
    return Padding(
      padding: padding,
      child: TextField(
        controller: controller,
        maxLines: 1,
        focusNode: focusNode,
        autofocus: false,
        style: const TextStyle(fontSize: _kFindInputFontSize),
        onSubmitted: onSubmit,
        decoration: InputDecoration(
          filled: true,
          contentPadding: EdgeInsetsGeometry.fromLTRB(4, 5, iconsWidth, 5),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            borderSide: BorderSide(
              width: 0.5,
              color: Color.fromARGB(255, 92, 92, 92),
            ),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            borderSide: BorderSide(
              width: 0.7,
              color: Color.fromARGB(255, 188, 188, 188),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckText({
    required BuildContext context,
    required String text,
    required bool checked,
    required VoidCallback onPressed,
  }) {
    final Color selectedColor = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: _kFindIconWidth * 0.75,
          child: Text(
            text,
            style: TextStyle(
              fontSize: _kFindInputFontSize,
              color: checked ? selectedColor : Colors.grey,
              fontWeight: checked ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    VoidCallback? onPressed,
    String? tooltip,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      padding: EdgeInsetsGeometry.symmetric(horizontal: 4, vertical: 4),
      icon: Icon(icon, size: _kFindIconSize),
      constraints: const BoxConstraints(
        maxWidth: _kFindIconWidth,
        maxHeight: _kFindIconHeight,
      ),
    );
  }

  Widget _buildResultText() {
    final text = controller.matchCount == 0
        ? 'none'
        : '${controller.currentMatchIndex + 1}/${controller.matchCount}';

    return Text(text, style: const TextStyle(fontSize: _kFindResultFontSize));
  }
}