import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/util/file_read.dart';

void main() {
  test('concurrent initialization returns the same manager instance', () async {
    final home = Directory.systemTemp.createTempSync('proxypin_rewrite_manager_test');
    final previousHome = FileRead.userHome;
    FileRead.userHome = home.path;
    addTearDown(() {
      FileRead.userHome = previousHome;
      home.deleteSync(recursive: true);
    });

    final managers = await Future.wait(List.generate(20, (_) => RequestRewriteManager.instance));

    for (final manager in managers.skip(1)) {
      expect(identical(manager, managers.first), isTrue);
    }
  });
}
