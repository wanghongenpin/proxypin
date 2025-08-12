import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/ui/component/buttons.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/platform.dart';

import '../component/text_field.dart';


/// Timestamp page
/// @author Hongen Wang
class TimestampPage extends StatefulWidget {
  final int? windowId;

  const TimestampPage({super.key, this.windowId});

  @override
  State<StatefulWidget> createState() {
    return _TimestampPageState();
  }
}

class _TimestampPageState extends State<TimestampPage> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  TextEditingController nowTimestamp = TextEditingController();
  TextEditingController timestamp = TextEditingController();
  TextEditingController dateTime = TextEditingController();

  TextEditingController timestampOut = TextEditingController();
  TextEditingController dateTimeOut = TextEditingController();

  @override
  void initState() {
    super.initState();

    nowTimestamp.text = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    timestamp.text = nowTimestamp.text;
    dateTime.text = DateTime.now().format();
    //定时器
    Timer.periodic(Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      nowTimestamp.text = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    });

    if (Platforms.isDesktop() && widget.windowId != null) {
      HardwareKeyboard.instance.addHandler(onKeyEvent);
    }
  }

  @override
  void dispose() {
    nowTimestamp.dispose();
    timestamp.dispose();
    dateTime.dispose();
    timestampOut.dispose();
    dateTimeOut.dispose();
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

  TextStyle? get textStyle => Theme.of(context).textTheme.titleMedium;

  bool get isCN => Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(localizations.timestamp, style: TextStyle(fontSize: 16)), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
        children: [
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${localizations.nowTimestamp}:', style: textStyle),
            const SizedBox(width: 6),
            SizedBox(
                width: 100,
                child: TextField(
                    controller: nowTimestamp, readOnly: true, decoration: InputDecoration(border: InputBorder.none))),
            IconButton(
                icon: Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: nowTimestamp.text));
                  FlutterToastr.show(localizations.copied, context);
                })
          ]),
          SizedBox(height: 15),
          if (Platforms.isDesktop())
            Wrap(spacing: 10.0, runSpacing: 10.0, crossAxisAlignment: WrapCrossAlignment.center, children: [
              timestampLabel(),
              SizedBox(width: 220, child: timestampField()),
              timestampButton(),
              SizedBox(width: 210, child: timestampOutField()),
            ]),
          if (Platforms.isMobile())
            Row(children: [
              timestampLabel(),
              SizedBox(width: 8),
              Expanded(
                  child: Column(children: [
                timestampField(),
                SizedBox(height: 5),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [timestampButton(), timestampOutCopyButton()]),
                SizedBox(height: 5),
                timestampOutField()
              ])),
            ]),
          SizedBox(height: 35),
          if (Platforms.isDesktop())
            Wrap(spacing: 10.0, runSpacing: 10.0, crossAxisAlignment: WrapCrossAlignment.center, children: [
              timeLabel(),
              SizedBox(width: 220, child: timeField()),
              timeButton(),
              SizedBox(width: 210, child: timeOutField())
            ]),
          if (Platforms.isMobile())
            Row(children: [
              timeLabel(),
              SizedBox(width: 8),
              Expanded(
                  child: Column(children: [
                timeField(),
                SizedBox(height: 5),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [timeButton(), timeOutCopyButton()]),
                SizedBox(height: 5),
                timeOutField()
              ])),
            ]),
        ],
      ),
    );
  }

  Widget timestampLabel() {
    return SizedBox(width: isCN ? 60 : 93, child: Text('${localizations.timestamp}:', style: textStyle));
  }

  Widget timestampButton() {
    return SizedBox(
        height: 40,
        child: FilledButton.icon(
            icon: Icon(Icons.play_arrow_rounded, size: 20),
            style: Buttons.buttonStyle,
            label: Text(localizations.convert),
            onPressed: () => timestampConvert(timestamp.text)));
  }

  Widget timestampField() {
    return TextFormField(
        controller: timestamp,
        onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: decoration(context,
            hintText: 'timestamp',
            suffixIcon: IconButton(icon: Icon(Icons.clear, size: 20), onPressed: () => timestamp.clear())));
  }

  Widget timestampOutField() {
    return TextFormField(
        controller: timestampOut, readOnly: true, decoration: InputDecoration(border: OutlineInputBorder()));
  }

  Widget timestampOutCopyButton() {
    return IconButton(
        icon: Icon(Icons.copy, size: 22),
        onPressed: () {
          if (timestampOut.text.isEmpty) return;
          Clipboard.setData(ClipboardData(text: timestampOut.text));
          FlutterToastr.show(localizations.copied, context);
        });
  }

  Widget timeLabel() {
    return SizedBox(width: isCN ? 60 : 93, child: Text('${localizations.time}:', style: textStyle));
  }

  Widget timeField() {
    return TextFormField(
        controller: dateTime,
        onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: decoration(context,
            hintText: 'yyyy-MM-dd HH:mm:ss',
            suffixIcon: IconButton(icon: Icon(Icons.clear, size: 20), onPressed: () => dateTime.clear())));
  }

  Widget timeButton() {
    return SizedBox(
        height: 40,
        child: FilledButton.icon(
            icon: Icon(Icons.play_arrow_rounded, size: 20),
            style: Buttons.buttonStyle,
            label: Text(localizations.convert),
            onPressed: () => timeConvert(dateTime.text)));
  }

  Widget timeOutField() {
    return TextFormField(
        controller: dateTimeOut, readOnly: true, decoration: InputDecoration(border: OutlineInputBorder()));
  }

  Widget timeOutCopyButton() {
    return IconButton(
        icon: Icon(Icons.copy, size: 22),
        onPressed: () {
          if (dateTimeOut.text.isEmpty) return;
          Clipboard.setData(ClipboardData(text: dateTimeOut.text));
          FlutterToastr.show(localizations.copied, context);
        });
  }

  timestampConvert(String timestamp) {
    if (timestamp.isEmpty) return;
    try {
      if (timestamp.length == 13) {
        timestampOut.text = DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp)).format();
        return;
      }

      if (timestamp.length == 10) {
        timestampOut.text = DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp) * 1000).format();
        return;
      }
      FlutterToastr.show('Invalid timestamp', context);
    } catch (e) {
      FlutterToastr.show('Invalid timestamp', context);
    }
  }

  timeConvert(String dateTime) {
    if (dateTime.isEmpty) return;
    try {
      var date = DateTime.parse(dateTime);
      dateTimeOut.text = (date.millisecondsSinceEpoch ~/ 1000).toString();
    } catch (e) {
      FlutterToastr.show('Invalid date time', context);
    }
  }
}
