import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/network/util/logger.dart';

abstract interface class LifecycleListener {
  void onUserLeaveHint() {}

  void onPictureInPictureModeChanged(bool isInPictureInPictureMode) {}
}

class AppLifecycleBinding {
  static const MethodChannel _methodChannel = MethodChannel('com.proxy/appLifecycle');

  //单例对象
  static AppLifecycleBinding get instance {
    _instance ??= AppLifecycleBinding._();
    return _instance!;
  }

  final List<LifecycleListener> _listeners = <LifecycleListener>[];

  static AppLifecycleBinding? _instance;

  AppLifecycleBinding._() {
    //注册方法
    _methodChannel.setMethodCallHandler(_methodCallHandler);
  }

  static AppLifecycleBinding ensureInitialized() {
    return AppLifecycleBinding.instance;
  }

  void addListener(LifecycleListener listener) {
    if (_listeners.contains(listener)) return;
    _listeners.add(listener);
  }

  void removeListener(LifecycleListener listener) {
    _listeners.remove(listener);
  }

  Future<void> _methodCallHandler(MethodCall call) async {
    logger.d("AppLifecycle methodCallHandler ${call.method}");
    switch (call.method) {
      case 'appDetached':
        await WidgetsBinding.instance.handleRequestAppExit();
        break;
      case 'onUserLeaveHint':
        for (var listener in _listeners) {
          listener.onUserLeaveHint();
        }
        break;
      case 'onPictureInPictureModeChanged':
        for (var listener in _listeners) {
          listener.onPictureInPictureModeChanged(call.arguments);
        }
        break;
    }
    return Future.value();
  }
}
