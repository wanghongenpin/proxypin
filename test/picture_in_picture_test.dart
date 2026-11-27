import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/native/pip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.proxy/pictureInPicture');
  MethodCall? methodCall;

  setUp(() {
    methodCall = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      methodCall = call;
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('enter picture-in-picture preserves disabled system proxy', () async {
    final entered = await PictureInPicture.enterPictureInPictureMode('192.168.1.2', 9099,
        appList: const [], disallowApps: const [], setSystemProxy: false);

    expect(entered, isTrue);
    expect(methodCall?.method, 'enterPictureInPictureMode');
    expect(methodCall?.arguments, {
      'proxyHost': '192.168.1.2',
      'proxyPort': 9099,
      'allowApps': <String>[],
      'disallowApps': <String>[],
      'setSystemProxy': false,
    });
  });
}
