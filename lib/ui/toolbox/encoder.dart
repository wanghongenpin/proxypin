import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/util/logger.dart';

///编码类型
enum EncoderType {
  url,
  base64,
  unicode,
  md5;

  static EncoderType nameOf(String name) {
    for (var value in values) {
      if (value.name == name) {
        return value;
      }
    }
    return url;
  }
}

class EncoderWidget extends StatefulWidget {
  final EncoderType type;
  final WindowController? windowController;
  final String? text;

  const EncoderWidget({super.key, required this.type, this.windowController, this.text});

  @override
  State<EncoderWidget> createState() => _EncoderState();
}

class _EncoderState extends State<EncoderWidget> with SingleTickerProviderStateMixin {
  var tabs = const [
    Tab(text: 'URL'),
    Tab(text: 'Base64'),
    Tab(text: 'Unicode'),
    Tab(text: 'MD5'),
  ];

  late EncoderType type;
  late TabController tabController;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  String inputText = '';
  TextEditingController outputTextController = TextEditingController();

  @override
  void initState() {
    super.initState();
    type = widget.type;
    inputText = widget.text ?? '';

    tabController = TabController(initialIndex: type.index, length: tabs.length, vsync: this);
    HardwareKeyboard.instance.addHandler(onKeyEvent);
  }

  @override
  void dispose() {
    tabController.dispose();
    HardwareKeyboard.instance.removeHandler(onKeyEvent);
    super.dispose();
  }

  bool onKeyEvent(KeyEvent event) {
    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      HardwareKeyboard.instance.removeHandler(onKeyEvent);
      tabController.dispose();
      widget.windowController?.close();
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
          title: Text('${type.name.toUpperCase()}${localizations.encode}', style: const TextStyle(fontSize: 16)),
          centerTitle: true,
          bottom: TabBar(
            controller: tabController,
            tabs: tabs,
            onTap: (index) {
              setState(() {
                type = EncoderType.values[index];
                outputTextController.clear();
              });
            },
          )),
      body: Container(
        padding: const EdgeInsets.all(10),
        child: ListView(
          children: <Widget>[
            Text(localizations.encodeInput),
            const SizedBox(height: 5),
            TextFormField(
                initialValue: inputText,
                minLines: 5,
                maxLines: 10,
                onChanged: (text) => inputText = text,
                decoration: const InputDecoration(border: OutlineInputBorder())),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                FilledButton(onPressed: encode, child: Text('${type.name.toUpperCase()}${localizations.encode}')),
                const SizedBox(width: 20),
                type == EncoderType.md5
                    ? const SizedBox()
                    : OutlinedButton(
                        onPressed: decode, child: Text('${type.name.toUpperCase()}${localizations.decode}')),
              ],
            ),
            Text(localizations.encodeResult),
            const SizedBox(height: 5),
            TextFormField(
              controller: outputTextController,
              readOnly: true,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: outputTextController.text));
                FlutterToastr.show(localizations.copied, context);
              },
              child: Text(localizations.copy),
            ),
          ],
        ),
      ),
    );
  }

  ///编码
  void encode() {
    var result = '';
    try {
      switch (type) {
        case EncoderType.url:
          result = Uri.encodeFull(inputText);
        case EncoderType.base64:
          result = base64.encode(utf8.encode(inputText));
        case EncoderType.md5:
          result = md5.convert(utf8.encode(inputText)).toString();
        case EncoderType.unicode:
          result = encodeToUnicode(inputText);
      }
    } catch (e) {
      FlutterToastr.show(localizations.encodeFail, context);
    }
    outputTextController.text = result;
  }

  ///解码
  void decode() {
    var result = '';
    try {
      switch (type) {
        case EncoderType.url:
          result = Uri.decodeFull(inputText);
        case EncoderType.base64:
          // base64.
          var text = inputText.replaceAll('.', '');
          if (text.length % 4 != 0) {
            text = text.padRight(text.length + (4 - text.length % 4), '=');
          }
          Uint8List compressed = base64.decode(text);
          try {
            result = utf8.decode(compressed);
          } catch (e) {
            result = String.fromCharCodes(compressed);
          }
        case EncoderType.md5:
        case EncoderType.unicode:
          result = decodeFromUnicode(inputText);
      }
    } catch (e, t) {
      logger.e("$e", error: e, stackTrace: t);
      FlutterToastr.show(localizations.decodeFail, context);
    }
    outputTextController.text = result;
  }

  String encodeToUnicode(String input) {
    return input.runes.map((rune) => '\\u${rune.toRadixString(16).padLeft(4, '0')}').join();
  }

  String decodeFromUnicode(String input) {
    return input.replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'), (match) {
      return String.fromCharCode(int.parse(match.group(1)!, radix: 16));
    });
  }
}
