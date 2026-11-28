import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/ui/component/linux_window_resize_area.dart';

void main() {
  testWidgets('resizes from every edge and corner only in the restored window', (tester) async {
    const channel = MethodChannel('window_manager');
    const codec = StandardMethodCodec();
    final messenger = tester.binding.defaultBinaryMessenger;
    final resizeEdges = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'startResizing') {
        resizeEdges.add(call.arguments['resizeEdge'] as String);
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(const MaterialApp(home: LinuxWindowResizeArea(child: Scaffold())));
    final bounds = tester.getRect(find.byType(Scaffold));
    final zones = {
      'topLeft': bounds.topLeft + const Offset(2, 2),
      'top': bounds.topCenter + const Offset(0, 2),
      'topRight': bounds.topRight + const Offset(-2, 2),
      'left': bounds.centerLeft + const Offset(2, 0),
      'right': bounds.centerRight + const Offset(-2, 0),
      'bottomLeft': bounds.bottomLeft + const Offset(2, -2),
      'bottom': bounds.bottomCenter + const Offset(0, -2),
      'bottomRight': bounds.bottomRight + const Offset(-2, -2),
    };

    Future<void> emitWindowEvent(String eventName) async {
      await messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(MethodCall('onEvent', {'eventName': eventName})),
        null,
      );
      await tester.pump();
    }

    for (final point in zones.values) {
      await tester.dragFrom(point, Offset(30, point.dy > bounds.center.dy ? -30 : 30));
    }
    await tester.dragFrom(bounds.center, const Offset(30, 30));
    expect(resizeEdges, zones.keys);
    resizeEdges.clear();

    await emitWindowEvent('maximize');
    await tester.dragFrom(zones['topLeft']!, const Offset(30, 30));
    await emitWindowEvent('enter-full-screen');
    await emitWindowEvent('unmaximize');
    await tester.dragFrom(zones['topLeft']!, const Offset(30, 30));
    expect(resizeEdges, isEmpty);

    await emitWindowEvent('leave-full-screen');
    await tester.dragFrom(zones['topLeft']!, const Offset(30, 30));
    expect(resizeEdges, ['topLeft']);
    await tester.pump(const Duration(milliseconds: 50));
  });
}
