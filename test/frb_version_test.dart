/*
 * Copyright 2026 Hongen Wang All rights reserved.
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

import 'package:code_forge/code_forge.dart';
import 'package:flutter_rust_bridge/src/misc/version.dart' show kFlutterRustBridgeRuntimeVersion;
import 'package:flutter_test/flutter_test.dart';

/// code_forge 的 Rust 桥接代码是用固定版本的工具（codegen）生成的，
/// flutter_rust_bridge 运行时要求 codegen 版本与运行时版本完全一致，
/// 否则 `RustLib.init()` 会失败，所有用到 CodeForgeController 的页面（
/// HTTP/JS/JSON/XML/TextDiff/TextEditor/重写/脚本编辑器）都会白屏。
///
/// 升级 code_forge 后如果这里挂了，说明 pubspec.yaml 里
/// `flutter_rust_bridge` 的 pin 版本和 code_forge 的 codegen 版本对不上，
/// 请把 pubspec.yaml 里的 flutter_rust_bridge 改成报错信息提示的版本。
void main() {
  test('code_forge codegen 版本必须与 flutter_rust_bridge 运行时版本一致', () {
    // ignore: invalid_use_of_internal_member
    final codegen = RustLib.instance.codegenVersion;
    expect(
      codegen,
      kFlutterRustBridgeRuntimeVersion,
      reason: 'code_forge 的 codegen 版本($codegen) 与 flutter_rust_bridge '
          '运行时版本($kFlutterRustBridgeRuntimeVersion)不一致，'
          'RustLib.init() 会失败导致编辑器页面白屏。'
          '请同步 pubspec.yaml 里的 flutter_rust_bridge pin。',
    );
  });
}