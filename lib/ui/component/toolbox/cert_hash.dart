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

import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/util/cert/x509.dart';
import 'package:proxypin/ui/component/buttons.dart';
import 'package:proxypin/ui/component/text_field.dart';
import 'package:proxypin/utils/platform.dart';

///证书哈希名称查看
///@author Hongen Wang
class CertHashPage extends StatefulWidget {
  final int? windowId;

  const CertHashPage({super.key, this.windowId});

  @override
  State<StatefulWidget> createState() {
    return _CertHashPageState();
  }
}

class _CertHashPageState extends State<CertHashPage> {
  var input = TextEditingController();
  TextEditingController decodeData = TextEditingController();

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    if (Platforms.isDesktop() && widget.windowId != null) {
      HardwareKeyboard.instance.addHandler(onKeyEvent);
    }
  }

  @override
  void dispose() {
    input.dispose();
    decodeData.dispose();
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
    return Scaffold(
        appBar: AppBar(title: Text(localizations.systemCertName, style: TextStyle(fontSize: 16)), centerTitle: true),
        resizeToAvoidBottomInset: false,
        body: ListView(children: [
          Wrap(alignment: WrapAlignment.end, children: [
            ElevatedButton.icon(
                onPressed: () async {
                  FilePickerResult? result = await FilePicker.platform
                      .pickFiles(type: FileType.custom, allowedExtensions: ['crt', 'pem', 'cer', 'der']);
                  if (result == null) return;

                  File file = File(result.files.single.path!);
                  var bytes = await file.readAsBytes();
                  input.text = tryDerFormat(bytes) ?? String.fromCharCodes(bytes);
                  getSubjectName();
                },
                style: Buttons.buttonStyle,
                icon: const Icon(Icons.folder_open),
                label: Text("File")),
            const SizedBox(width: 15),
            ElevatedButton.icon(
                onPressed: () => input.clear(),
                style: Buttons.buttonStyle,
                icon: const Icon(Icons.clear),
                label: const Text("Clear")),
            const SizedBox(width: 15),
            FilledButton.icon(
                onPressed: () {
                  getSubjectName();
                  FocusScope.of(context).unfocus();
                },
                style: Buttons.buttonStyle,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text("Run")),
            const SizedBox(width: 15),
          ]),
          const SizedBox(width: 10),
          Container(
              padding: const EdgeInsets.all(10),
              height: 350,
              child: TextFormField(
                  maxLines: 50,
                  controller: input,
                  onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
                  keyboardType: TextInputType.text,
                  decoration: decoration(context, label: localizations.inputContent))),
          Align(
              alignment: Alignment.bottomLeft,
              child: TextButton(
                  onPressed: () {}, child: Text("${localizations.output}:", style: TextStyle(fontSize: 16)))),
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              height: 150,
              child: TextFormField(
                  maxLines: 30,
                  readOnly: true,
                  controller: decodeData,
                  decoration: decoration(context, label: 'Android ${localizations.systemCertName}'))),
        ]));
  }

  getSubjectName() {
    var content = input.text;
    if (content.isEmpty) return;
    try {
      var caCert = X509Utils.x509CertificateFromPem(content);
      var subject = caCert.subject;
      var subjectHashName = X509Utils.getSubjectHashName(subject);
      decodeData.text = '$subjectHashName.0';
    } catch (e) {
      FlutterToastr.show(localizations.decodeFail, context, duration: 3, backgroundColor: Colors.red);
    }
  }

  String? tryDerFormat(Uint8List data) {
    try {
      final bytes = data.sublist(0, 4);

      // Check if the bytes match the DER format (ASN.1 encoding)
      // DER encoded certificates typically start with 0x30 (SEQUENCE) or 0xA0 (APPLICATION)
      if (bytes[0] == 0x30 || bytes[0] == 0xA0) {
        return X509Utils.crlDerToPem(data);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
