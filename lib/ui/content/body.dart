/*
 * Copyright 2023 Hongen Wang All rights reserved.
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
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:image_pickers/image_pickers.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/components/manager/rewrite_rule.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/json/json_viewer.dart';
import 'package:proxypin/ui/component/json/theme.dart';
import 'package:proxypin/ui/component/multi_window.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/desktop/toolbar/setting/request_rewrite.dart';
import 'package:proxypin/ui/mobile/setting/request_rewrite.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/num.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

import '../component/json/json_text.dart';
import '../toolbox/encoder.dart';

///请求响应的body部分
///@Author wanghongen
class HttpBodyWidget extends StatefulWidget {
  final HttpMessage? httpMessage;
  final bool inNewWindow; //是否在新窗口打开
  final WindowController? windowController;
  final ScrollController? scrollController;
  final bool hideRequestRewrite; //是否隐藏请求重写

  const HttpBodyWidget(
      {super.key,
      required this.httpMessage,
      this.inNewWindow = false,
      this.windowController,
      this.scrollController,
      this.hideRequestRewrite = false});

  @override
  State<StatefulWidget> createState() {
    return HttpBodyState();
  }
}

class HttpBodyState extends State<HttpBodyWidget> {
  var bodyKey = GlobalKey<_BodyState>();
  int tabIndex = 0;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    if (widget.windowController != null) {
      HardwareKeyboard.instance.addHandler(onKeyEvent);
    }
  }

  /// 按键事件
  bool onKeyEvent(KeyEvent event) {
    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      HardwareKeyboard.instance.removeHandler(onKeyEvent);
      widget.windowController?.close();
      return true;
    }

    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(onKeyEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.httpMessage == null) {
      return const SizedBox();
    }

    if ((widget.httpMessage?.body == null || widget.httpMessage?.body?.isEmpty == true) &&
        widget.httpMessage?.messages.isNotEmpty == false) {
      return const SizedBox();
    }

    var tabs = Tabs.of(widget.httpMessage?.contentType, isJsonText());

    if (tabIndex > 0 && tabIndex >= tabs.list.length) tabIndex = tabs.list.length - 1;
    bodyKey.currentState?.changeState(widget.httpMessage, tabs.list[tabIndex]);

    //TabBar
    List<Widget> list = [
      widget.inNewWindow ? const SizedBox() : titleWidget(),
      const SizedBox(height: 3),
      SizedBox(
          height: 36,
          child: TabBar(
              labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              labelPadding: const EdgeInsets.only(left: 3, right: 5),
              tabs: tabs.tabList(),
              onTap: (index) {
                tabIndex = index;
                bodyKey.currentState?.changeState(widget.httpMessage, tabs.list[tabIndex]);
              })),
      Padding(
          padding: const EdgeInsets.all(10),
          child: _Body(
              key: bodyKey,
              message: widget.httpMessage,
              viewType: tabs.list[tabIndex],
              scrollController: widget.scrollController)) //body
    ];

    var tabController = DefaultTabController(
        initialIndex: tabIndex,
        length: tabs.list.length,
        child: widget.inNewWindow
            ? ListView(children: list)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: list));

    //在新窗口打开
    if (widget.inNewWindow) {
      return Scaffold(
          appBar: AppBar(title: titleWidget(inNewWindow: true), toolbarHeight: Platform.isWindows ? 36 : null),
          body: tabController);
    }
    return tabController;
  }

  //判断是否是json格式
  bool isJsonText() {
    var bodyString = widget.httpMessage?.bodyAsString;
    return bodyString != null &&
        (bodyString.startsWith('{') && bodyString.endsWith('}') ||
            bodyString.startsWith('[') && bodyString.endsWith(']'));
  }

  /// 标题
  Widget titleWidget({inNewWindow = false}) {
    var type = widget.httpMessage is HttpRequest ? "Request" : "Response";

    bool isImage = widget.httpMessage?.contentType == ContentType.image;

    var list = [
      Text('$type Body', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      const SizedBox(width: 10),
      isImage
          ? downloadImageButton()
          : IconButton(
              icon: Icon(Icons.copy, size: 18),
              tooltip: localizations.copy,
              onPressed: () async {
                var body = await bodyKey.currentState?.getBody();
                if (body == null) {
                  return;
                }
                Clipboard.setData(ClipboardData(text: body)).then((value) {
                  if (mounted) FlutterToastr.show(localizations.copied, context);
                });
              }),
    ];

    if (!widget.hideRequestRewrite) {
      list.add(const SizedBox(width: 3));
      list.add(IconButton(
          icon: const Icon(Icons.edit_document, size: 18),
          tooltip: localizations.requestRewrite,
          onPressed: showRequestRewrite));
    }

    list.add(const SizedBox(width: 3));
    list.add(IconButton(
        icon: const Icon(Icons.text_format, size: 21),
        tooltip: localizations.encode,
        onPressed: () async {
          var body = await bodyKey.currentState?.getBody();
          if (mounted) {
            encodeWindow(EncoderType.base64, context, body);
          }
        }));
    if (!inNewWindow) {
      list.add(const SizedBox(width: 3));
      list.add(IconButton(
          icon: const Icon(Icons.open_in_new, size: 18), tooltip: localizations.newWindow, onPressed: () => openNew()));
    }

    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: list);
  }

  ///下载图片
  Widget downloadImageButton() {
    return IconButton(
        icon: Icon(Icons.download, size: 20),
        tooltip: localizations.saveImage,
        onPressed: () async {
          var body = bodyKey.currentState?.message?.body;
          if (body == null) {
            return;
          }
          var bytes = Uint8List.fromList(body);
          if (Platforms.isMobile()) {
            String? path = await ImagePickers.saveByteDataImageToGallery(bytes);
            if (path != null && mounted) {
              FlutterToastr.show(localizations.saveSuccess, context, duration: 2, rootNavigator: true);
            }
            return;
          }

          if (Platforms.isDesktop()) {
            var fileName = "image_${DateTime.now().millisecondsSinceEpoch}.png";
            String? path = (await FilePicker.platform.saveFile(fileName: fileName));
            if (path == null) return;

            await File(path).writeAsBytes(bytes);
            if (mounted) {
              FlutterToastr.show(localizations.saveSuccess, context, duration: 2);
            }
          }
        });
  }

  ///展示请求重写
  showRequestRewrite() async {
    HttpRequest? request;
    if (widget.httpMessage == null) {
      return;
    }

    bool isRequest = widget.httpMessage is HttpRequest;
    if (widget.httpMessage is HttpRequest) {
      request = widget.httpMessage as HttpRequest;
    } else {
      request = (widget.httpMessage as HttpResponse).request;
    }
    var requestRewrites = await RequestRewriteManager.instance;

    var ruleType = isRequest ? RuleType.requestReplace : RuleType.responseReplace;
    var rule = requestRewrites.getRequestRewriteRule(request!, ruleType);

    var rewriteItems = await requestRewrites.getRewriteItems(rule);

    if (!mounted) return;

    if (Platforms.isMobile()) {
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => RewriteRule(rule: rule, items: rewriteItems, request: request)));
    } else {
      showDialog(
              context: context,
              barrierDismissible: false,
              builder: (BuildContext context) => RewriteRuleEdit(rule: rule, items: rewriteItems, request: request))
          .then((value) {
        if (value is RequestRewriteRule && mounted) {
          FlutterToastr.show(localizations.saveSuccess, context);
        }
      });
    }
  }

  ///打开新窗口
  void openNew() async {
    if (Platforms.isDesktop()) {
      var size = MediaQuery.of(context).size;
      var ratio = 1.0;
      if (Platform.isWindows) {
        ratio = WindowManager.instance.getDevicePixelRatio();
      }
      final window = await DesktopMultiWindow.createWindow(jsonEncode(
        {'name': 'HttpBodyWidget', 'httpMessage': widget.httpMessage, 'inNewWindow': true},
      ));
      window
        ..setTitle(widget.httpMessage is HttpRequest ? localizations.requestBody : localizations.responseBody)
        ..setFrame(const Offset(100, 100) & Size(800 * ratio, size.height * ratio))
        ..center()
        ..show();
      return;
    }

    Navigator.push(
        context, MaterialPageRoute(builder: (_) => HttpBodyWidget(httpMessage: widget.httpMessage, inNewWindow: true)));
  }
}

class _Body extends StatefulWidget {
  final HttpMessage? message;
  final ViewType viewType;
  final ScrollController? scrollController;

  const _Body({super.key, this.message, required this.viewType, this.scrollController});

  @override
  State<StatefulWidget> createState() {
    return _BodyState();
  }
}

class _BodyState extends State<_Body> {
  late ViewType viewType;
  HttpMessage? message;

  @override
  void initState() {
    super.initState();
    viewType = widget.viewType;
    message = widget.message;
  }

  changeState(HttpMessage? message, ViewType viewType) {
    setState(() {
      this.message = message;
      this.viewType = viewType;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _getBody(viewType);
  }

  Future<String?> getBody() async {
    if (message?.isWebSocket == true) {
      return message?.messages.map((e) => e.payloadDataAsString).join("\n");
    }

    if (message == null || message?.body == null) {
      return null;
    }

    if (viewType == ViewType.hex) {
      return (await message!.decodeBody()).map(intToHex).join(" ");
    }

    if (viewType == ViewType.base64) {
      return base64.encode(await message!.decodeBody());
    }

    try {
      if (viewType == ViewType.formUrl) {
        return Uri.decodeFull(message!.bodyAsString);
      }

      if (viewType == ViewType.jsonText || viewType == ViewType.json) {
        //json格式化
        var jsonObject = json.decode(await message!.decodeBodyString());
        return const JsonEncoder.withIndent("  ").convert(jsonObject);
      }
    } catch (_) {}
    return message!.decodeBodyString();
  }

  Widget _getBody(ViewType type) {
    if (message?.isWebSocket == true) {
      List<Widget>? list = message?.messages
          .map((e) => Container(
              margin: const EdgeInsets.only(top: 2, bottom: 2),
              child: Row(
                children: [
                  Expanded(child: Text(e.payloadDataAsString)),
                  const SizedBox(width: 5),
                  SizedBox(
                      width: 130,
                      child: SelectionContainer.disabled(
                          child: Text(e.time.format(), style: const TextStyle(fontSize: 12, color: Colors.grey))))
                ],
              )))
          .toList();
      return Column(
        children: [
          const SelectionContainer.disabled(
              child: Row(children: [
            Expanded(child: Text("Data")),
            SizedBox(width: 130, child: Text("Time")),
          ])),
          Divider(height: 5, thickness: 1, color: Colors.grey[300]),
          ...list ?? []
        ],
      );
    }

    if (message == null || message?.body == null) {
      return const SizedBox();
    }

    if (type == ViewType.image) {
      return Center(child: Image.memory(Uint8List.fromList(message?.body ?? []), fit: BoxFit.scaleDown));
    }
    if (type == ViewType.video) {
      return const Center(child: Text("video not support preview"));
    }
    if (type == ViewType.formUrl) {
      return SelectableText(Uri.decodeFull(message!.getBodyString()), contextMenuBuilder: contextMenu);
    }

    if (type == ViewType.hex) {
      return futureWidget(
        message!.decodeBody(),
        initialData: message!.body!,
        (body) {
          try {
            return SelectableText(body.map(intToHex).join(" "), contextMenuBuilder: contextMenu);
          } catch (e, stackTrace) {
            logger.e(e, stackTrace: stackTrace);
            return SelectableText(message!.body!.map(intToHex).join(" "), contextMenuBuilder: contextMenu);
          }
        },
     );
    }

    if (type == ViewType.base64) {
      return futureWidget(
        message!.decodeBody(),
        initialData: message!.body!,
        (body) {
          try {
            return SelectableText(base64.encode(body), contextMenuBuilder: contextMenu);
          } catch (e, stackTrace) {
            logger.e(e, stackTrace: stackTrace);
            return SelectableText("Unsupported body type: ${body.runtimeType}", contextMenuBuilder: contextMenu);
          }
        },
     );
    }

    return futureWidget(message!.decodeBodyString(), initialData: message!.getBodyString(), (body) {
      try {
        if (type == ViewType.jsonText) {
          var jsonObject = json.decode(body);
          return JsonText(
              json: jsonObject,
              indent: Platforms.isDesktop() ? '    ' : '  ',
              colorTheme: ColorTheme.of(Theme.of(context).brightness),
              scrollController: widget.scrollController);
        }

        if (type == ViewType.json) {
          return JsonViewer(json.decode(body), colorTheme: ColorTheme.of(Theme.of(context).brightness));
        }
      } catch (e) {
        logger.e(e, stackTrace: StackTrace.current);
      }

      return SelectableText.rich(showCursor: true, TextSpan(text: body), contextMenuBuilder: contextMenu);
    });
  }
}

class Tabs {
  final List<ViewType> list = [];

  static Tabs of(ContentType? contentType, bool isJsonText) {
    var tabs = Tabs();
    if (contentType == null) {
      return tabs;
    }

    if (contentType == ContentType.video) {
      tabs.list.add(ViewType.video);
      tabs.list.add(ViewType.hex);
      return tabs;
    }

    if (contentType == ContentType.json) {
      tabs.list.add(ViewType.jsonText);
    }

    tabs.list.add(ViewType.of(contentType) ?? ViewType.text);

    //为json时，增加json格式化
    if (isJsonText && !tabs.list.contains(ViewType.jsonText)) {
      tabs.list.add(ViewType.jsonText);
      tabs.list.add(ViewType.json);
    }

    if (contentType == ContentType.formUrl || contentType == ContentType.json) {
      tabs.list.add(ViewType.text);
    }

    tabs.list.add(ViewType.hex);
    tabs.list.add(ViewType.base64);
    return tabs;
  }

  List<Tab> tabList() {
    return list.map((e) => Tab(text: e.title)).toList();
  }
}

enum ViewType {
  text("Text"),
  formUrl("URL Decode"),
  json("JSON"),
  jsonText("JSON Text"),
  html("HTML"),
  image("Image"),
  video("Video"),
  css("CSS"),
  js("JavaScript"),
  hex("Hex"),
  base64("Base64"),
  ;

  final String title;

  const ViewType(this.title);

  static ViewType? of(ContentType contentType) {
    for (var value in values) {
      if (value.name == contentType.name) {
        return value;
      }
    }
    return null;
  }
}
