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
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

///高级重放
/// @author wanghongen
class CustomRepeatDialog extends StatefulWidget {
  final Function onRepeat;
  final SharedPreferences prefs;

  const CustomRepeatDialog({super.key, required this.onRepeat, required this.prefs});

  @override
  State<StatefulWidget> createState() => _CustomRepeatState();
}

class _CustomRepeatState extends State<CustomRepeatDialog> {
  TextEditingController count = TextEditingController(text: '1');
  TextEditingController interval = TextEditingController(text: '0');
  TextEditingController minInterval = TextEditingController(text: '0');
  TextEditingController maxInterval = TextEditingController(text: '1000');
  TextEditingController delay = TextEditingController(text: '0');

  bool fixed = true;
  bool keepSetting = true;

  DateTime? time;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  bool get isEN => Localizations.localeOf(context).languageCode == "en";

  @override
  void initState() {
    super.initState();

    var customerRepeat = widget.prefs.getString('customerRepeat');
    keepSetting = customerRepeat != null;
    if (customerRepeat != null) {
      Map<String, dynamic> data = jsonDecode(customerRepeat);
      count.text = data['count'];
      interval.text = data['interval'];
      minInterval.text = data['minInterval'];
      maxInterval.text = data['maxInterval'];
      delay.text = data['delay'];
      fixed = data['fixed'] == true;
    }
  }

  @override
  void dispose() {
    count.dispose();
    interval.dispose();
    delay.dispose();
    super.dispose();
  }


  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormState>();

    return AlertDialog(
      title: Text(localizations.customRepeat, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      content: SingleChildScrollView(
          child: Form(
              key: formKey,
              child: ListBody(
                children: <Widget>[
                  field(localizations.repeatCount, textField(count)), //次数
                  const SizedBox(height: 8),
                  Row(
                    //间隔
                    children: [
                      SizedBox(width: isEN ? 100 : 90, child: Text(localizations.repeatInterval)),
                      const SizedBox(height: 5),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        //Checkbox样式 固定和随机
                        Row(children: [
                          SizedBox(
                              width: isEN ? 107 : 84,
                              height: 35,
                              child: Transform.scale(
                                  scale: 0.83,
                                  child: CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text("${localizations.fixed}:"),
                                      value: fixed,
                                      dense: true,
                                      onChanged: (val) {
                                        setState(() {
                                          fixed = true;
                                        });
                                      }))),
                          SizedBox(width: 152, height: 32, child: textField(interval, style: const TextStyle(fontSize: 13))),
                        ]),
                        Row(children: [
                          SizedBox(
                              width: isEN ? 107 : 84,
                              height: 35,
                              child: Transform.scale(
                                  scale: 0.83,
                                  child: CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text("${localizations.random}:"),
                                      value: !fixed,
                                      dense: true,
                                      onChanged: (val) {
                                        setState(() {
                                          fixed = false;
                                        });
                                      }))),
                          SizedBox(width: 65, height: 32, child: textField(minInterval, style: const TextStyle(fontSize: 13))),
                          const Padding(padding: EdgeInsets.symmetric(horizontal: 5), child: Text("-")),
                          SizedBox(width: 70, height: 32, child: textField(maxInterval, style: const TextStyle(fontSize: 13))),
                        ]),
                      ]),
                    ],
                  ),
                  const SizedBox(height: 8),
                  field(localizations.repeatDelay, textField(delay)), //延时
                  const SizedBox(height: 8),
                  field(
                      localizations.scheduleTime,
                      InkWell(
                        onTap: _pickScheduleDateTime,
                        child: Container(
                          height: 42,
                          padding: const EdgeInsets.only(left: 10, right: 10),
                              decoration: BoxDecoration(
                              border: Border.all(color: Theme.of(context).colorScheme.primary.withAlpha((0.5 * 255).round()), width: 1.0),
                              borderRadius: BorderRadius.circular(4)),
                          child: Row(
                            children: [
                              Text(time == null
                                  ? ''
                                  : "${time!.year}-${_two(time!.month)}-${_two(time!.day)} ${_two(time!.hour)}:${_two(time!.minute)}"),
                              const Expanded(child: SizedBox()),
                              if (time != null)
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      time = null;
                                    });
                                  },
                                  child: const Icon(Icons.clear, size: 18),
                                ),
                              if (time == null) Icon(Icons.access_time, size: 18, color: Theme.of(context).colorScheme.primary),
                            ],
                          ),
                        ),
                      )), //指定时间
                  const SizedBox(height: 8),
                  //记录选择
                  Row(mainAxisAlignment: MainAxisAlignment.start, children: [
                    Text(localizations.keepCustomSettings),
                    Expanded(
                      child: Checkbox(
                        value: keepSetting,
                        onChanged: (val) {
                          setState(() {
                            keepSetting = val == true;
                          });
                        },
                      ),
                    ),
                  ])
                ],
              ))),
      actions: <Widget>[
        TextButton(
          child: Text(localizations.cancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
          child: Text(localizations.done),
          onPressed: () {
            if (!formKey.currentState!.validate()) {
              return;
            }
            if (keepSetting) {
              widget.prefs.setString(
                  'customerRepeat',
                  jsonEncode({
                    'count': count.text,
                    'interval': interval.text,
                    'minInterval': minInterval.text,
                    'maxInterval': maxInterval.text,
                    'delay': delay.text,
                    'fixed': fixed
                  }));
            } else {
              widget.prefs.remove('customerRepeat');
            }

            int delayValue = int.parse(delay.text);
            if (time != null) {
              DateTime now = DateTime.now();
              if (time!.isBefore(now)) {
                time = time!.add(const Duration(days: 1));
              }
              delayValue += time!.difference(now).inMilliseconds;
            }

            //定时发起请求
            Future.delayed(Duration(milliseconds: delayValue), () => submitTask(int.parse(count.text)));
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  //定时重放
  void submitTask(int counter) {
    if (counter <= 0) {
      return;
    }
    widget.onRepeat.call();

    int intervalValue = int.parse(interval.text);
    //随机
    if (!fixed) {
      int min = int.parse(minInterval.text);
      int max = int.parse(maxInterval.text);
      intervalValue = Random().nextInt(max - min) + min;
    }

    Future.delayed(Duration(milliseconds: intervalValue), () {
      if (counter - 1 > 0) {
        submitTask(counter - 1);
      }
    });
  }

  Future<void> _pickScheduleDateTime() async {
    DateTime now = DateTime.now();

    // Normalize minimum date to minute precision to avoid millisecond/second mismatches
    DateTime minDate = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    DateTime initial = time ?? minDate;
    if (initial.isBefore(minDate)) initial = minDate;

    DateTime temp = initial;

    var date = await showDialog<DateTime>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            contentPadding: const EdgeInsets.all(16.0),
            content: SizedBox(
              height: 250,
              width: 300,
              child: CupertinoTheme(
                data: CupertinoThemeData(brightness: Theme.of(context).brightness),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.dateAndTime,
                  initialDateTime: initial,
                  minimumDate: minDate,
                  maximumDate: minDate.add(const Duration(days: 365)),
                  use24hFormat: true,
                  onDateTimeChanged: (val) {
                    temp = val;
                  },
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(localizations.cancel)),
              TextButton(onPressed: () => Navigator.pop(context, temp), child: Text(localizations.done)),
            ],
          );
        });

    if (date != null) {
      setState(() {
        // ensure selected date is not before now (safety)
        DateTime now2 = DateTime.now();
        if (date.isBefore(now2)) {
          // clamp to now to avoid scheduling into the past
          time = now2;
        } else {
          time = date;
        }
      });
    }
  }

  Widget field(String label, Widget child) {
    return Row(
      children: [
        SizedBox(width: isEN ? 110 : 95, child: Text(label)),
        Expanded(child: child),
      ],
    );
  }

  Widget textField(TextEditingController? controller, {TextStyle? style}) {
    Color color = Theme.of(context).colorScheme.primary;

    return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 42),
        child: TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: style,
          decoration: InputDecoration(
              errorStyle: const TextStyle(height: 2, fontSize: 0),
              contentPadding: const EdgeInsets.only(left: 10, right: 10, top: 5, bottom: 5),
              border: OutlineInputBorder(borderSide: BorderSide(width: 1, color: color.withAlpha((0.3 * 255).round()))),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(width: 1.5, color: color.withAlpha((0.5 * 255).round()))),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(width: 2, color: color))),
          validator: (val) => val == null || val.isEmpty ? localizations.cannotBeEmpty : null,
        ));
  }
}
