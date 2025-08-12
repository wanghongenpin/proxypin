/*
 * Copyright 2024 Hongen Wang All rights reserved.
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

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_qr_reader/flutter_qr_reader.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:image_pickers/image_pickers.dart';
import 'package:proxypin/ui/component/app_dialog.dart';
import 'package:proxypin/ui/component/qrcode/qr_scan_view.dart';
import 'package:proxypin/ui/component/text_field.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/app_localizations.dart';

///二维码
///@author Hongen Wang
class QrCodePage extends StatefulWidget {
  final int? windowId;

  const QrCodePage({super.key, this.windowId});

  @override
  State<StatefulWidget> createState() {
    return _QrCodePageState();
  }
}

class _QrCodePageState extends State<QrCodePage> with SingleTickerProviderStateMixin {
  TabController? tabController;

  late List<Tab> tabs = [
    Tab(text: 'Encode'),
    Tab(text: 'Decode'),
  ];

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    if (Platforms.isMobile()) {
      tabController = TabController(initialIndex: 0, length: tabs.length, vsync: this);
    }

    if (Platforms.isDesktop() && widget.windowId != null) {
      HardwareKeyboard.instance.addHandler(onKeyEvent);
    }
  }

  @override
  void dispose() {
    tabController?.dispose();
    HardwareKeyboard.instance.removeHandler(onKeyEvent);
    super.dispose();
  }

  bool onKeyEvent(KeyEvent event) {
    if (widget.windowId == null) return false;
    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      HardwareKeyboard.instance.removeHandler(onKeyEvent);
      WindowController.fromWindowId(widget.windowId!).close();
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (Platforms.isDesktop()) {
      return Scaffold(
          appBar: AppBar(title: Text(localizations.qrCode, style: const TextStyle(fontSize: 16)), centerTitle: true),
          body: _QrEncode(windowId: widget.windowId));
    }

    tabs = [
      Tab(text: localizations.encode),
      Tab(text: localizations.decode),
    ];

    return Scaffold(
        appBar: AppBar(
            title: Text(localizations.qrCode, style: const TextStyle(fontSize: 16)),
            centerTitle: true,
            bottom: TabBar(tabs: tabs, controller: tabController)),
        resizeToAvoidBottomInset: false,
        body: TabBarView(
          controller: tabController,
          children: [_QrEncode(windowId: widget.windowId), _QrDecode(windowId: widget.windowId)],
        ));
  }
}

class _QrDecode extends StatefulWidget {
  final int? windowId;

  const _QrDecode({this.windowId});

  @override
  State<StatefulWidget> createState() {
    return _QrDecodeState();
  }
}

class _QrDecodeState extends State<_QrDecode> with AutomaticKeepAliveClientMixin {
  TextEditingController decodeData = TextEditingController();

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void dispose() {
    decodeData.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ListView(children: [
      SizedBox(height: 15),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 10),
          FilledButton.icon(
              onPressed: () async {
                String? path = await selectImage();
                if (path == null) return;
                var result = await FlutterQrReader.imgScan(path);
                if (result.isEmpty) {
                  if (context.mounted) FlutterToastr.show(localizations.decodeFail, context, duration: 2);
                  return;
                }
                decodeData.text = result;
              },
              icon: const Icon(Icons.photo, size: 18),
              style: ButtonStyle(
                  padding: MaterialStateProperty.all<EdgeInsets>(const EdgeInsets.symmetric(horizontal: 15, vertical: 8)),
                  shape: MaterialStateProperty.all<RoundedRectangleBorder>(
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
              label: Text(localizations.selectImage)),
          const SizedBox(width: 10),
          if (Platforms.isMobile())
            FilledButton.icon(
                onPressed: () async {
                  var scanRes = await QrCodeScanner.scan(context);
                  if (scanRes == null) return;

                  if (scanRes == "-1") {
                    if (context.mounted) FlutterToastr.show(localizations.invalidQRCode, context, duration: 2);
                    return;
                  }
                  decodeData.text = scanRes;
                },
                style: ButtonStyle(
                    padding: MaterialStateProperty.all<EdgeInsets>(const EdgeInsets.symmetric(horizontal: 15, vertical: 8)),
                    shape: MaterialStateProperty.all<RoundedRectangleBorder>(
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
                icon: const Icon(Icons.qr_code_scanner_outlined, size: 18),
                label: Text(localizations.scanQrCode, style: const TextStyle(fontSize: 14))),
          const SizedBox(width: 10),
        ],
      ),
      const SizedBox(height: 20),
      Container(
          padding: const EdgeInsets.all(10),
          height: 300,
          child: Column(children: [
            TextField(
              controller: decodeData,
              maxLines: 7,
              minLines: 7,
              readOnly: true,
              decoration: decoration(context, label: localizations.encodeResult),
            ),
            SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.copy_rounded),
              onPressed: () {
                if (decodeData.text.isEmpty) return;
                Clipboard.setData(ClipboardData(text: decodeData.text));
                FlutterToastr.show(localizations.copied, context);
              },
              label: Text(localizations.copy),
            ),
          ])),
      SizedBox(height: 10),
    ]);
  }

  //选择照片
  Future<String?> selectImage() async {
    if (Platforms.isMobile()) {
      List<Media> listImagePaths = await ImagePickers.pickerPaths(showCamera: true);
      if (listImagePaths.isEmpty) return null;
      return listImagePaths[0].path;
    }

    if (Platforms.isDesktop()) {
      //<String>['jpg', 'png', 'jpeg']
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result == null || result.files.isEmpty) return null;
      return result.files.single.path;
    }

    return null;
  }
}

class _QrEncode extends StatefulWidget {
  final int? windowId;

  const _QrEncode({this.windowId});

  @override
  State<StatefulWidget> createState() => _QrEncodeState();
}

//生成二维码
class _QrEncodeState extends State<_QrEncode> with AutomaticKeepAliveClientMixin {
  var errorCorrectLevel = QrErrorCorrectLevel.M;
  String? data;
  TextEditingController inputData = TextEditingController();
  final GlobalKey imageKey = GlobalKey();

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void dispose() {
    inputData.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ListView(children: [
      Container(
          padding: const EdgeInsets.all(10),
          height: 180,
          child: TextField(
              controller: inputData,
              maxLines: 8,
              onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
              decoration: decoration(context, label: localizations.inputContent))),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 10),
          Row(children: [
            Text("${localizations.errorCorrectLevel}: "),
            DropdownButton<int>(
                value: errorCorrectLevel,
                items: QrErrorCorrectLevel.levels
                    .map((e) => DropdownMenuItem<int>(value: e, child: Text(QrErrorCorrectLevel.getName(e))))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    errorCorrectLevel = value!;
                  });
                }),
          ]),
          const SizedBox(width: 15),
          FilledButton.icon(
              onPressed: () {
                setState(() {
                  data = inputData.text;
                });
              },
              style: ButtonStyle(
                  padding: MaterialStateProperty.all<EdgeInsets>(const EdgeInsets.symmetric(horizontal: 15, vertical: 8)),
                  shape: MaterialStateProperty.all<RoundedRectangleBorder>(
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
              icon: const Icon(Icons.qr_code, size: 18),
              label: Text(localizations.generateQrCode, style: TextStyle(fontSize: 14))),
          const SizedBox(width: 10),
        ],
      ),
      const SizedBox(height: 10),
      if (data != null && data?.isNotEmpty == true)
        Column(
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton.icon(
                  onPressed: () async {
                    await saveImage();
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: Text(localizations.saveImage)),
              SizedBox(width: 20),
            ]),
            SizedBox(height: 5),
            Center(
                child: RepaintBoundary(
                    key: imageKey,
                    child: QrImageView(
                        size: 300,
                        data: inputData.text,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: errorCorrectLevel))),
          ],
        ),
      SizedBox(height: 15),
    ]);
  }

  //保存相册
  saveImage() async {
    if (data == null || data!.isEmpty) {
      return;
    }

    if (Platforms.isMobile()) {
      var imageBytes = await toImageBytes();
      if (imageBytes == null) return;
      String? path = await ImagePickers.saveByteDataImageToGallery(imageBytes);
      if (path != null && mounted) {
        FlutterToastr.show(localizations.saveSuccess, context, duration: 2, rootNavigator: true);
      }
      return;
    }

    String? path;
    if (Platform.isMacOS) {
      path = await DesktopMultiWindow.invokeMethod(0, "saveFile", {"fileName": "qrcode.png"});
      WindowController.fromWindowId(widget.windowId!).show();
    } else {
      path = (await FilePicker.platform.saveFile(fileName: "qrcode.png", initialDirectory: "~/Downloads"));
    }

    if (path == null) return;

    var imageBytes = await toImageBytes();
    if (imageBytes == null) return;

    await File(path).writeAsBytes(imageBytes);
    if (mounted) {
      CustomToast.success(localizations.saveSuccess).show(context);
    }
  }

  Future<Uint8List?> toImageBytes() async {
    RenderRepaintBoundary render = imageKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    ui.Image image = await render.toImage();
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }
}
