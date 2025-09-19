import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:proxypin/ui/component/search/search_controller.dart';

import '../../../utils/platform.dart';

const _hintText = 'Search…';

class SearchField extends StatefulWidget {
  final SearchTextController searchController;

  const SearchField({
    super.key,
    required this.searchController,
  });

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final FocusNode focusNode = FocusNode();
  final RxBool caseSensitive = RxBool(false);
  final RxBool isRegExp = RxBool(false);

  @override
  initState() {
    super.initState();
    if (Platforms.isDesktop()) {
      focusNode.requestFocus();
    }
    caseSensitive.value = widget.searchController.value.isCaseSensitive;
    isRegExp.value = widget.searchController.value.isRegExp;
  }

  @override
  dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double searchBoxWidth = min(450, MediaQuery.of(context).size.width - 20);

    final searchBox = SizedBox(
      width: searchBoxWidth,
      child: Material(
          elevation: 1,
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [
            SizedBox(
              width: Platforms.isDesktop() ? 260 : 220,
              child: TextField(
                autofocus: true,
                focusNode: focusNode,
                controller: widget.searchController.patternController,
                onEditingComplete: () {
                  widget.searchController.moveNext();
                },
                decoration: InputDecoration(
                    hintText: _hintText,
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    suffixIcon: Obx(() {
                      return ToggleButtons(
                        constraints: const BoxConstraints(minWidth: 30, minHeight: 43),
                        onPressed: (index) {
                          switch (index) {
                            case 0:
                              widget.searchController.toggleCaseSensitivity();
                              caseSensitive.value = !caseSensitive.value;
                              break;
                            case 1:
                              widget.searchController.toggleIsRegExp();
                              isRegExp.value = !isRegExp.value;
                              break;
                          }
                        },
                        isSelected: [
                          caseSensitive.value,
                          isRegExp.value,
                        ],
                        children: const [
                          Text('Aa'),
                          Text('.*'),
                        ],
                      );
                    })),
              ),
            ),
            if (Platforms.isDesktop()) SizedBox(width: 85, child: _getText()),
            if (Platforms.isMobile()) SizedBox(width: 10),
            InkWell(
              onTap: widget.searchController.movePrevious,
              child: const Icon(Icons.north, size: 17),
            ),
            SizedBox(width: 10),
            InkWell(
              onTap: widget.searchController.moveNext,
              child: const Icon(Icons.south, size: 17),
            ),
            const SizedBox(width: 3),
            IconButton(
              iconSize: 19,
              icon: const Icon(Icons.close),
              onPressed: () => widget.searchController.closeSearch(),
            ),
            const SizedBox(width: 10),
          ])),
    );

    return Draggable<Offset>(
      feedback: searchBox,
      childWhenDragging: SizedBox(width: searchBoxWidth, height: 56),
      onDragEnd: (details) {
        final offset = details.offset;
        final screenSize = MediaQuery.of(context).size;
        double newTop = offset.dy;
        double newRight = screenSize.width - offset.dx - searchBoxWidth;
        widget.searchController.updateOverlayPosition(newTop, newRight);
      },
      child: searchBox,
    );
  }

  Text _getText() {
    if (widget.searchController.totalMatchCount.value == 0) {
      return Text("0 results",
          textAlign: TextAlign.center,
          style: TextStyle(color: widget.searchController.patternController.text.isNotEmpty ? Colors.red : null));
    }

    final currentMatchIndex = widget.searchController.currentMatchIndex.value + 1;
    final totalMatchCount = widget.searchController.totalMatchCount.value;

    return Text(
      '$currentMatchIndex / $totalMatchCount',
      textAlign: TextAlign.center,
    );
  }
}
