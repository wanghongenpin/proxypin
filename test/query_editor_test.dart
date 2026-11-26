import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/ui/component/model/request_query.dart';
import 'package:proxypin/ui/component/query_syntax_help.dart';

void main() {
  testWidgets('editor lists long query as chips, delete/insert/clear sync to search box', (tester) async {
    final controller = TextEditingController(
        text: 'method:POST status:4xx -host:*.ads.com size>100k | app:chrome time>1s');
    final changes = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            appBar: AppBar(
                title: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                        suffixIcon: QueryFilterButton(
                            schema: RequestQuery.schema,
                            controller: controller,
                            onChanged: changes.add,
                            quickFilters: quickRequestFilters)))))));

    // 角标显示 6 个条件
    expect(find.text('6'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsNWidgets(6));
    expect(find.text('OR'), findsOneWidget);

    // 删除 -host 条件
    final chip = find.widgetWithText(InputChip, '-host:*.ads.com');
    await tester.tap(find.descendant(of: chip, matching: find.byIcon(Icons.clear)));
    await tester.pumpAndSettle();
    expect(controller.text, 'method:POST status:4xx size>100k | app:chrome time>1s');
    expect(changes.last, controller.text);

    // 点示例追加，弹层不关闭
    await tester.tap(find.widgetWithText(ActionChip, 'is:error').first);
    await tester.pumpAndSettle();
    expect(controller.text, endsWith(' is:error'));
    expect(find.byType(InputChip), findsNWidgets(6));

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(controller.text, '');
    expect(find.byType(InputChip), findsNothing);
  });
}
