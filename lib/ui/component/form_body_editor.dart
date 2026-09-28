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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/component/env_var_highlight.dart';
import 'package:proxypin/utils/multipart.dart';

/// 通用 key/value 表单构建器，multipart/form-data 与
/// application/x-www-form-urlencoded 共用：
/// - multipart：[allowFiles] = true，可添加文本字段或文件字段；
/// - form-url：[allowFiles] = false，仅文本字段。
///
/// 原地修改 [form]，父组件发送请求时读取同一对象。
/// 文件在选中时即读入字节，保证发送/断点执行路径保持同步。
/// 文案全部复用现有国际化 key，不新增翻译。
///
/// @author wanghongen
class FormBodyEditor extends StatefulWidget {
  final FormBody form;

  /// 是否允许添加文件字段（仅 multipart 为 true）
  final bool allowFiles;

  const FormBodyEditor({super.key, required this.form, this.allowFiles = false});

  @override
  State<FormBodyEditor> createState() => FormBodyEditorState();
}

class FormBodyEditorState extends State<FormBodyEditor> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  void addTextField() {
    setState(() => widget.form.parts.add(FormPart(name: '')));
  }

  Future<void> addFiles() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;

    final parts = <FormPart>[];
    for (final file in files) {
      // 预读字节，发送时不再做异步 I/O
      final bytes = await file.readAsBytes();
      parts.add(FormPart(name: '', kind: FormPartKind.file, fileName: file.name, bytes: bytes));
    }
    if (!mounted) return;
    setState(() => widget.form.parts.addAll(parts));
  }

  @override
  Widget build(BuildContext context) {
    // "添加文本/选择文件"入口在请求编辑器的顶部工具栏
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: widget.form.parts.isEmpty
            // 复用 emptyData
            ? Center(
                child: Text(localizations.emptyData,
                    textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 10),
                itemCount: widget.form.parts.length,
                itemBuilder: (_, index) {
                  final part = widget.form.parts[index];
                  return _FormPartRow(
                    key: ObjectKey(part),
                    part: part,
                    onDelete: () => setState(() => widget.form.parts.removeAt(index)),
                  );
                },
              ),
      ),
    ]);
  }
}

/// 单个表单字段行，自持控制器并在行销毁时释放。
class _FormPartRow extends StatefulWidget {
  final FormPart part;
  final VoidCallback onDelete;

  const _FormPartRow({super.key, required this.part, required this.onDelete});

  @override
  State<_FormPartRow> createState() => _FormPartRowState();
}

class _FormPartRowState extends State<_FormPartRow> {
  late final TextEditingController _nameController;
  TextEditingController? _valueController;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    final part = widget.part;
    _nameController = TextEditingController(text: part.name);
    if (!part.isFile) {
      // 文本字段值支持 {{env}} 高亮
      _valueController = EnvHighlightTextEditingController(text: part.value);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _valueController?.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final file = await FilePicker.pickFile();
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      widget.part.fileName = file.name;
      widget.part.bytes = bytes;
      widget.part.contentType = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final part = widget.part;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Checkbox(
          value: part.enabled,
          visualDensity: VisualDensity.compact,
          onChanged: (v) => setState(() {
            part.enabled = v ?? true;
          }),
        ),
        Expanded(
          flex: 4,
          child: TextField(
            controller: _nameController,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: localizations.name,
              border: const OutlineInputBorder(),
              enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.black12)),
            ),
            onChanged: (v) => part.name = v,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: part.isFile ? _fileValue(part) : _textValue(part),
        ),
        IconButton(
          tooltip: localizations.delete,
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close),
          onPressed: widget.onDelete,
        ),
      ]),
    );
  }

  Widget _textValue(FormPart part) {
    return TextField(
      controller: _valueController,
      style: const TextStyle(fontSize: 13),
      minLines: 1,
      maxLines: 3,
      decoration: InputDecoration(
        isDense: true,
        hintText: localizations.value,
        border: const OutlineInputBorder(),
        enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.black12)),
      ),
      onChanged: (v) => part.value = v,
    );
  }

  Widget _fileValue(FormPart part) {
    final fileName = part.fileName;
    return InkWell(
      onTap: _pickFile,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          const Icon(Icons.insert_drive_file_outlined, size: 16),
          const SizedBox(width: 6),
          Expanded(
            // 未选择时复用 selectFile；已选择显示 文件名(大小)
            child: fileName == null
                ? Text(localizations.selectFile,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))
                : Text('$fileName (${_formatSize(part.fileSize ?? 0)})',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
          ),
          const Icon(Icons.folder_open, size: 16),
        ]),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
