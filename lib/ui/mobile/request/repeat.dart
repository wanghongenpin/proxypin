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
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

///高级重放
/// @author wang
class MobileCustomRepeat extends StatefulWidget {
  final Function onRepeat;
  final SharedPreferences prefs;

  const MobileCustomRepeat({super.key, required this.onRepeat, required this.prefs});

  @override
  State<StatefulWidget> createState() => _CustomRepeatState();
}

class _CustomRepeatState extends State<MobileCustomRepeat> {
  TextEditingController count = TextEditingController(text: '1');
  TextEditingController interval = TextEditingController(text: '0');
  TextEditingController minInterval = TextEditingController(text: '0');
  TextEditingController maxInterval = TextEditingController(text: '1000');
  TextEditingController delay = TextEditingController(text: '0');

  bool fixed = true;
  bool keepSetting = true;

  TimeOfDay? time;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

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

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormState>();

    return Scaffold(
        appBar: AppBar(
          title: Text(localizations.customRepeat, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          actions: [
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
                  DateTime schedule = DateTime(now.year, now.month, now.day, time!.hour, time!.minute);
                  if (schedule.isBefore(now)) {
                    schedule = schedule.add(const Duration(days: 1));
                  }
                  delayValue += schedule.difference(now).inMilliseconds;
                }

                Future.delayed(Duration(milliseconds: delayValue), () => submitTask(int.parse(count.text)));
                Navigator.of(context).pop();
              },
            )
          ],
        ),
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(15),
            child: Form(
              key: formKey,
              child: Column(
                children: <Widget>[
                  field(localizations.repeatCount, textField(count)), //次数
                  const SizedBox(height: 6),
                  intervalWidget(), //间隔
                  const SizedBox(height: 6),
                  field(localizations.repeatDelay, textField(delay)), //延时
                  const SizedBox(height: 6),
                  field(
                      localizations.scheduleTime,
                      Row(children: [
                        Text(time?.format(context) ?? ''),
                        TextButton(
                            onPressed: () {
                              showTimePicker(context: context, initialTime: time ?? TimeOfDay.now()).then((value) {
                                if (value != null) {
                                  setState(() {
                                    time = value;
                                  });
                                }
                              });
                            },
                            child: Text(MaterialLocalizations.of(context).timePickerDialHelpText))
                      ])), //指定时间
                  const SizedBox(height: 6),
                  //记录选择
                  Row(children: [
                    Text(localizations.keepCustomSettings),
                    Expanded(
                        child: Checkbox(
                            value: keepSetting,
                            onChanged: (val) {
                              setState(() {
                                keepSetting = val == true;
                              });
                            })),
                  ])
                ],
              ),
            )));
  }

  //定时重放
  submitTask(int counter) {
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

  //间隔widget
  Widget intervalWidget() {
    return Row(
      children: [
        SizedBox(width: 83, child: Text(localizations.repeatInterval)),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          //Checkbox样式 固定和随机
          Row(children: [
            SizedBox(
                width: 112,
                height: 35,
                child: Transform.scale(
                    scale: 0.82,
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
            Expanded(child: textField(interval, style: const TextStyle(fontSize: 13))),
          ]),
          const SizedBox(height: 5),
          Row(children: [
            SizedBox(
                width: 112,
                child: Transform.scale(
                    scale: 0.82,
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
            Flexible(child: textField(minInterval, style: const TextStyle(fontSize: 13))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 5), child: Text("-")),
            Flexible(child: textField(maxInterval, style: const TextStyle(fontSize: 13))),
          ]),
        ])),
      ],
    );
  }

  Widget field(String label, Widget child) {
    return Row(
      children: [
        SizedBox(width: 95, child: Text("$label :")),
        Expanded(child: child),
      ],
    );
  }

  FormField textField(TextEditingController? controller, {TextStyle? style}) {
    Color color = Theme.of(context).colorScheme.primary;

    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: style,
      decoration: InputDecoration(
          errorStyle: const TextStyle(height: 2, fontSize: 0),
          contentPadding: const EdgeInsets.only(left: 10, right: 10, top: 5, bottom: 5),
          border: OutlineInputBorder(borderSide: BorderSide(width: 1, color: color.withOpacity(0.3))),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(width: 1.5, color: color.withOpacity(0.5))),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(width: 2, color: color))),
      validator: (val) => val == null || val.isEmpty ? localizations.cannotBeEmpty : null,
    );
  }
}
