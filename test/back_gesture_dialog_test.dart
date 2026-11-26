import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/main.dart' show pageTransitionsTheme;
import 'package:proxypin/utils/navigator.dart';

void main() {
  for (final root in [true, false]) {
    testWidgets('back with dialog open (useRootNavigator=$root)', (tester) async {
      final key = GlobalKey<NavigatorState>();
      final page = NavigatorPage(navigatorKey: key, child: const Text('home'));
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(pageTransitionsTheme: pageTransitionsTheme),
          home: PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) page.onPopInvoked();
              },
              child: Scaffold(body: page))));
      key.currentState!.push(MaterialPageRoute(
          builder: (ctx) => Scaffold(
              body: Builder(
                  builder: (ctx) => TextButton(
                      onPressed: () => showDialog(
                          context: ctx, useRootNavigator: root, builder: (_) => const AlertDialog(title: Text('DLG'))),
                      child: const Text('open'))))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('DLG'), findsOneWidget);
      // 模拟 Android 预测性返回手势（targetSdk 36 / Android 16 默认启用）
      Future<void> send(String method, [Object? args]) => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/backgesture', const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)), (_) {});
      final ev = {'touchOffset': [5.0, 300.0], 'progress': 0.0, 'swipeEdge': 0};
      await send('startBackGesture', ev);
      await tester.pump();
      await send('updateBackGestureProgress', {...ev, 'progress': 0.8});
      await tester.pump();
      await send('commitBackGesture');
      await tester.pumpAndSettle();
      // 返回只关闭弹窗，下面的页面保留
      expect(find.text('DLG'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  }
}
