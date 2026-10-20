/// 自定义快捷工具栏弹框视觉预览（非测试）：flutter run -d macos -t test/quick_tools_preview_main.dart
/// 只读取本地配置用于展示，不要在预览里点击固定/排序（会 flushConfig 写入真实配置）
import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/desktop/toolbar/quick_tools.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var appConfiguration = await AppConfiguration.instance;

  runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
          brightness: Brightness.light,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue, primary: Colors.blue, surface: Colors.white)),
      home: Scaffold(
          backgroundColor: const Color(0xFFF5F6F8),
          body: Center(child: CustomizeToolbarDialog(appConfiguration: appConfiguration)))));
}
