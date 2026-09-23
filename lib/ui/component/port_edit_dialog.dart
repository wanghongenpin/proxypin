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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';

/// MCP 端口编辑对话框。
///
/// 自身持有 [TextEditingController] 并在 [State.dispose] 释放——不能由调用方在
/// `await showDialog` 返回后立即 dispose：那时路由仍在播放退出动画，[TextField]
/// 还会 build，提前释放会触发 “used after being disposed”。
///
/// 返回校验通过的端口；取消或非法时返回 null。
///
/// @author wanghongen
class PortEditDialog extends StatefulWidget {
  /// 输入框初始值
  final int initialPort;

  /// 输入框为空时的提示（一般为默认端口）
  final int defaultPort;

  const PortEditDialog({super.key, required this.initialPort, required this.defaultPort});

  /// 便捷打开入口
  static Future<int?> show(BuildContext context, {required int initialPort, required int defaultPort}) {
    return showDialog<int>(
      context: context,
      builder: (_) => PortEditDialog(initialPort: initialPort, defaultPort: defaultPort),
    );
  }

  @override
  State<PortEditDialog> createState() => _PortEditDialogState();
}

class _PortEditDialogState extends State<PortEditDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.initialPort}');

  AppLocalizations get l => AppLocalizations.of(context)!;

  @override
  void dispose() {
    // 仅在对话框真正卸载（退出动画结束）后释放，避免 TextField 仍在 build 时访问
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    var value = int.tryParse(_controller.text.trim());
    if (value == null || value < 1024 || value > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.mcpPortInvalid), duration: const Duration(seconds: 2)));
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      title: Text(l.mcpPort, style: const TextStyle(fontSize: 16)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(hintText: '${widget.defaultPort}'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        TextButton(onPressed: _submit, child: Text(l.save)),
      ],
    );
  }
}
