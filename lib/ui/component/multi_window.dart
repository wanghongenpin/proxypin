/*
 * Copyright 2023 Hongen Wang
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/components/rewrite/request_rewrite_manager.dart';
import 'package:proxypin/network/components/rewrite/rewrite_rule.dart';
import 'package:proxypin/network/components/script_manager.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/cert_hash.dart';
import 'package:proxypin/ui/component/device.dart';
import 'package:proxypin/ui/component/encoder.dart';
import 'package:proxypin/ui/component/js_run.dart';
import 'package:proxypin/ui/component/qr_code_page.dart';
import 'package:proxypin/ui/component/regexp.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/content/body.dart';
import 'package:proxypin/ui/desktop/request/request_editor.dart';
import 'package:proxypin/ui/desktop/toolbar/setting/request_rewrite.dart';
import 'package:proxypin/ui/desktop/toolbar/setting/script.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

bool isMultiWindow = false;

///多窗口
Widget multiWindow(int windowId, Map<dynamic, dynamic> argument) {
  isMultiWindow = true;
  //请求编辑器
  if (argument['name'] == 'RequestEditor') {
    return RequestEditor(
        windowController: WindowController.fromWindowId(windowId),
        request: argument['request'] == null ? null : HttpRequest.fromJson(argument['request']));
  }
  //请求体
  if (argument['name'] == 'HttpBodyWidget') {
    return HttpBodyWidget(
        windowController: WindowController.fromWindowId(windowId),
        httpMessage: HttpMessage.fromJson(argument['httpMessage']),
        inNewWindow: true,
        hideRequestRewrite: true);
  }
  //编码
  if (argument['name'] == 'EncoderWidget') {
    return EncoderWidget(
        type: EncoderType.nameOf(argument['type']),
        text: argument['text'],
        windowController: WindowController.fromWindowId(windowId));
  }
  //脚本
  if (argument['name'] == 'ScriptWidget') {
    return ScriptWidget(windowId: windowId);
  }
  //请求重写
  if (argument['name'] == 'RequestRewriteWidget') {
    return futureWidget(
        RequestRewriteManager.instance, (data) => RequestRewriteWidget(windowId: windowId, requestRewrites: data));
  }

  if (argument['name'] == 'QrCodePage') {
    return QrCodePage(windowId: windowId);
  }

  if (argument['name'] == 'CertHashPage') {
    return CertHashPage();
  }

  if (argument['name'] == 'JavaScript') {
    return const JavaScript();
  }

  if (argument['name'] == 'RegExpPage') {
    return const RegExpPage();
  }
  //脚本日志
  if (argument['name'] == 'ScriptConsoleWidget') {
    return ScriptConsoleWidget(windowId: windowId);
  }
  return const SizedBox();
}

enum Operation {
  add,
  update,
  delete,
  enabled,
  refresh;

  static Operation of(String name) {
    return values.firstWhere((element) => element.name == name);
  }
}

class MultiWindow {
  /// 刷新请求重写
  static Future<void> invokeRefreshRewrite(Operation operation,
      {int? index, RequestRewriteRule? rule, List<RewriteItem>? items, bool? enabled}) async {
    await DesktopMultiWindow.invokeMethod(0, "refreshRequestRewrite", {
      "enabled": enabled,
      "operation": operation.name,
      'index': index,
      'rule': rule?.toJson(),
      'items': items?.map((e) => e.toJson()).toList()
    });
  }

  static Future<WindowController> openWindow(String title, String widgetName,
      {Size size = const Size(800, 680)}) async {
    var ratio = 1.0;
    if (Platform.isWindows) {
      ratio = WindowManager.instance.getDevicePixelRatio();
    }
    registerMethodHandler();
    final window = await DesktopMultiWindow.createWindow(jsonEncode(
      {'name': widgetName},
    ));
    window.setTitle(title);
    window
      ..setFrame(const Offset(50, -10) & Size(size.width * ratio, size.height * ratio))
      ..center();
    window.show();

    return window;
  }

  static bool _refreshRewrite = false;

  static Future<void> _handleRefreshRewrite(Operation operation, Map<dynamic, dynamic> arguments) async {
    RequestRewriteManager requestRewrites = await RequestRewriteManager.instance;

    switch (operation) {
      case Operation.add:
      case Operation.update:
        var rule = RequestRewriteRule.formJson(arguments['rule']);
        List<dynamic>? list = arguments['items'] as List<dynamic>?;
        List<RewriteItem>? items = list?.map((e) => RewriteItem.fromJson(e)).toList();

        if (operation == Operation.add) {
          await requestRewrites.addRule(rule, items!);
        } else {
          await requestRewrites.updateRule(arguments['index'], rule, items);
        }
        break;
      case Operation.delete:
        var rule = requestRewrites.rules.removeAt(arguments['index']);
        requestRewrites.rewriteItemsCache.remove(rule); //删除缓存
        break;
      case Operation.enabled:
        requestRewrites.enabled = arguments['enabled'];
        break;
      default:
        break;
    }

    if (_refreshRewrite) return;
    _refreshRewrite = true;
    Future.delayed(const Duration(milliseconds: 1000), () async {
      _refreshRewrite = false;
      requestRewrites.flushRequestRewriteConfig();
    });
  }
}

bool _registerHandler = false;

/// 桌面端多窗口 注册方法处理器
void registerMethodHandler() {
  if (_registerHandler) {
    return;
  }
  _registerHandler = true;
  DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
    logger.d('${call.method} $fromWindowId ${call.arguments}');

    if (call.method == 'getProxyInfo') {
      return ProxyServer.current?.isRunning == true ? {'host': '127.0.0.1', 'port': ProxyServer.current!.port} : null;
    }

    if (call.method == 'refreshScript') {
      await ScriptManager.instance.then((value) {
        return value.reloadScript();
      });
      return 'done';
    }

    if (call.method == 'refreshRequestRewrite') {
      await MultiWindow._handleRefreshRewrite(Operation.of(call.arguments['operation']), call.arguments);
      return 'done';
    }

    if (call.method == 'getApplicationSupportDirectory') {
      return getApplicationSupportDirectory().then((it) => it.path);
    }

    if (call.method == 'launchUrl') {
      return launchUrl(Uri.parse(call.arguments));
    }

    if (call.method == 'registerConsoleLog') {
      ScriptManager.registerConsoleLog(fromWindowId);
      return "done";
    }

    if (call.method == 'deviceId') {
      return await DeviceUtils.desktopDeviceId();
    }

    return 'done';
  });
}

///打开编码窗口
encodeWindow(EncoderType type, BuildContext context, [String? text]) async {
  if (Platforms.isMobile()) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => EncoderWidget(type: type, text: text)));
    return;
  }

  var ratio = 1.0;
  if (Platform.isWindows) {
    ratio = WindowManager.instance.getDevicePixelRatio();
  }
  final window = await DesktopMultiWindow.createWindow(jsonEncode(
    {'name': 'EncoderWidget', 'type': type.name, 'text': text},
  ));
  if (!context.mounted) return;
  window.setTitle(AppLocalizations.of(context)!.encode);
  window
    ..setFrame(const Offset(80, 80) & Size(900 * ratio, 600 * ratio))
    ..center()
    ..show();
}

openScriptConsoleWindow() async {
  var ratio = 1.0;
  if (Platform.isWindows) {
    ratio = WindowManager.instance.getDevicePixelRatio();
  }
  final window = await DesktopMultiWindow.createWindow(jsonEncode(
    {'name': 'ScriptConsoleWidget'},
  ));
  window.setTitle('Script Console');
  window
    ..setFrame(const Offset(50, 0) & Size(900 * ratio, 650 * ratio))
    ..center();
  window.show();
}
