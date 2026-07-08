import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';

class Platforms {
  /// 判断是否是桌面端
  static bool isDesktop() {
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// 判断是否是移动端
  static bool isMobile() {
    return Platform.isAndroid || Platform.isIOS;
  }

  /// 判断是否是ipad
  static Future<bool> isIpad() async {
    if (Platform.isIOS) {
      final deviceInfo = DeviceInfoPlugin();
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.model.toLowerCase().contains('ipad');
    }
    return false;
  }

  /// 桌面端保存文件：只弹对话框选路径并返回，不自动写入。
  /// 调用方拿到路径后自行转换 bytes 并写入，避免用户取消时浪费性能。
  /// 移动端请直接使用 FilePicker.saveFile。
  static Future<String?> saveFileAdaptive({
    required String fileName,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    String? dialogTitle,
  }) async {
    return FilePicker.platform.saveFile(
      fileName: fileName,
      bytes: Uint8List(0),
      type: type,
      allowedExtensions: allowedExtensions,
      dialogTitle: dialogTitle,
    );
  }
}
