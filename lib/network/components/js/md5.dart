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

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:proxypin/network/util/lang.dart';

/// JsMd5
/// @author Hongen Wang
class Md5Bridge {
  static const String _md5 = '''
    function md5(input) {
      return sendMessage('md5', JSON.stringify(input));
    }
  ''';

  ///注册js md5
  static void registerMd5(JavascriptRuntime flutterJs) {
    var channels = JavascriptRuntime.channelFunctionsRegistered[flutterJs.getEngineInstanceId()];
    if (channels != null && channels.containsKey('md5')) {
      return;
    }

    flutterJs.evaluate(_md5);

    flutterJs.onMessage('md5', (args) {
      List<int> input;
      //判断是否是二进制
      if (Lists.getElementType(args) == int) {
        input = Lists.convertList<int>(args);
      } else {
        input = utf8.encode(args.toString());
      }

      return md5.convert(input).toString();
    });
  }
}
