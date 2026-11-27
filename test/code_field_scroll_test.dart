import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/ui/desktop/setting/request_map/map_scipt.dart';

void main() {
  testWidgets('bounded desktop code editor scrolls long content', (tester) async {
    final script = List.generate(100, (i) => 'line $i').join('\n');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 850,
            child: DesktopMapScript(script: script),
          ),
        ),
      ),
    ));
    await tester.pump();

    final field = tester.widget<CodeField>(find.byType(CodeField));
    expect(field.expands, isTrue);
    expect(tester.takeException(), isNull);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(CodeField)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
    await tester.pump();

    final verticalScrollables = tester.stateList<ScrollableState>(find.descendant(
      of: find.byType(CodeField),
      matching: find.byType(Scrollable),
    )).where((state) => state.position.axis == Axis.vertical);

    expect(verticalScrollables.any((state) => state.position.pixels > 0), isTrue);
  });
}
