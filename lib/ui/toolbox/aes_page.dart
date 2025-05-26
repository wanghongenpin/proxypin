import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/util/logger.dart';

import '../component/buttons.dart';
import '../component/text_field.dart';
import '../../utils/aes.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class AesPage extends StatefulWidget {
  const AesPage({super.key});

  @override
  State<AesPage> createState() => _AesWidgetState();
}

class _AesWidgetState extends State<AesPage> {
  final TextEditingController inputController = TextEditingController();
  final TextEditingController outputController = TextEditingController();
  final TextEditingController keyController = TextEditingController();
  final TextEditingController ivController = TextEditingController();

  String selectedMode = 'ECB';
  String selectedPadding = 'PKCS7';
  int selectedKeyLength = 128;
  final List<String> modes = ['ECB', 'CBC'];
  final List<String> paddingModes = ['PKCS7', 'ZeroPadding'];
  final List<int> keyLengths = [128, 192, 256];

  void encryptText() {
    try {
      final input = Uint8List.fromList(utf8.encode(inputController.text));
      final encrypted = AesUtils.encrypt(input,
          key: keyController.text,
          mode: selectedMode,
          iv: ivController.text,
          keyLength: selectedKeyLength,
          padding: selectedPadding);
      outputController.text = base64.encode(encrypted);
    } catch (e) {
      logger.e("Encryption error: $e");
      FlutterToastr.show("Encryption failed", context, duration: 3, backgroundColor: Colors.red);
    }
  }

  void decryptText() {
    try {
      final input = base64.decode(inputController.text);
      final decrypted = AesUtils.decrypt(input,
          key: keyController.text,
          mode: selectedMode,
          iv: ivController.text,
          keyLength: selectedKeyLength,
          padding: selectedPadding);
      outputController.text = utf8.decode(decrypted);
    } catch (e) {
      outputController.text = "";
      logger.e("Decryption error: $e");
      FlutterToastr.show("Decryption failed", context, duration: 3, backgroundColor: Colors.red);
    }
  }

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("AES", style: TextStyle(fontSize: 16)), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(15),
        child: ListView(children: [
          const SizedBox(height: 5),
          SizedBox(
              height: 150,
              child: TextField(
                  controller: inputController,
                  maxLines: 8,
                  onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: decoration(context, label: localizations.inputContent))),
          const SizedBox(height: 15),
          Wrap(spacing: 18, runSpacing: 5, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
                width: 120,
                child: Row(children: [
                  Text("Mode"),
                  const SizedBox(width: 15),
                  DropdownButton<String>(
                    value: selectedMode,
                    items: modes.map((mode) {
                      return DropdownMenuItem(value: mode, child: Text(mode));
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedMode = value!;
                      });
                    },
                  ),
                ])),
            SizedBox(
                width: 195,
                child: Row(children: [
                  Text("Padding"),
                  const SizedBox(width: 15),
                  DropdownButton<String>(
                    value: selectedPadding,
                    items: paddingModes.map((mode) {
                      return DropdownMenuItem(value: mode, child: Text(mode));
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedPadding = value!;
                      });
                    },
                  ),
                ])),
            SizedBox(
                width: 190,
                child: Row(children: [
                  Text("Key Length"),
                  const SizedBox(width: 15),
                  DropdownButton<int>(
                    value: selectedKeyLength,
                    items: keyLengths.map((length) {
                      return DropdownMenuItem(value: length, child: Text("$length bits"));
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedKeyLength = value!;
                      });
                    },
                  ),
                ]))
          ]),
          const SizedBox(height: 15),
          Wrap(
              spacing: 18.0, // 主轴方向子组件的间距
              runSpacing: 10.0, // 交叉轴方向子组件的间距
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                    width: 230,
                    child: Row(children: [
                      const SizedBox(width: 25, child: Text("Key")),
                      const SizedBox(width: 15),
                      SizedBox(
                          width: 180,
                          height: 45,
                          child: TextField(
                              controller: keyController,
                              maxLength: 32,
                              onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
                              style: TextStyle(fontSize: 14),
                              decoration: InputDecoration(
                                  border: const OutlineInputBorder(),
                                  counterText: "",
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 6)))),
                    ])),
                SizedBox(
                    width: 260,
                    child: Row(children: [
                      const SizedBox(width: 25, child: Text("IV")),
                      const SizedBox(width: 15),
                      SizedBox(
                          width: 180,
                          height: 45,
                          child: TextField(
                              controller: ivController,
                              maxLength: 32,
                              onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
                              style: TextStyle(fontSize: 14),
                              decoration: InputDecoration(
                                  border: const OutlineInputBorder(),
                                  counterText: "",
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 6)))),
                    ])),
              ]),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton(
                  style: ButtonStyle(
                      shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
                  onPressed: encryptText,
                  child: Text(localizations.encrypt)),
              const SizedBox(width: 60),
              FilledButton(
                  style: ButtonStyle(
                      shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
                  onPressed: decryptText,
                  child: Text(localizations.decrypt)),
            ],
          ),
          const SizedBox(height: 5),
          Text(localizations.output),
          const SizedBox(height: 5),
          TextFormField(
            controller: outputController,
            readOnly: true,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            style: Buttons.buttonStyle,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: outputController.text));
              FlutterToastr.show(localizations.copied, context);
            },
            icon: const Icon(Icons.copy),
            label: Text(localizations.copy),
          ),
        ]),
      ),
    );
  }
}
