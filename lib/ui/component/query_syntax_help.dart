import 'package:flutter/material.dart';
import 'package:proxypin/utils/query/query.dart';

/// 查询语法帮助：列出字段与示例，点击示例插入到输入框。
class QuerySyntaxHelp<T> extends StatelessWidget {
  final QuerySchema<T> schema;
  final ValueChanged<String> onInsert;

  /// 顶部常用快捷条件
  final List<String> quickFilters;

  const QuerySyntaxHelp({super.key, required this.schema, required this.onInsert, this.quickFilters = const []});

  /// 弹出条件编辑器；[controller] 为搜索输入框，编辑内容实时同步并回调 [onChanged]
  static Future<void> show<T>(BuildContext context,
      {required QuerySchema<T> schema,
      required TextEditingController controller,
      required ValueChanged<String> onChanged,
      List<String> quickFilters = const []}) {
    return showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        builder: (ctx) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
                child: QueryEditor<T>(
                    schema: schema, controller: controller, onChanged: onChanged, quickFilters: quickFilters))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCN = Localizations.localeOf(context).languageCode == 'zh';
    final hint = TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant);
    final code = TextStyle(fontSize: 12, fontFamily: 'monospace', color: theme.colorScheme.primary);

    Widget chip(String text) => ActionChip(
        label: Text(text, style: code),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onPressed: () => onInsert(text));

    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 24), shrinkWrap: true, children: [
      Text(isCN ? '语法' : 'Syntax', style: const TextStyle(fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      Text(
          isCN
              ? '空格 = 并且，| 或 OR = 或者，前缀 - 取反；值支持 * 通配、/正则/、"带空格"、逗号多选、范围 a-b；'
                  '数值支持 > >= < <= 与单位（k/m、ms/s）。不带字段的词按搜索范围做文本匹配。'
              : 'Space = AND, | or OR = OR, prefix - to negate. Values: * wildcard, /regex/, "quoted", a,b list, a-b range. '
                  'Numbers support > >= < <= and units (k/m, ms/s). Bare words match text in the search scope.',
          style: hint),
      if (quickFilters.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(isCN ? '常用' : 'Quick', style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: quickFilters.map(chip).toList()),
      ],
      const SizedBox(height: 12),
      for (final f in schema.fields) ...[
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                    width: 120,
                    child: Text(f.names.join(' / '),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, fontFamily: 'monospace'))),
                Expanded(child: Text(f.description, style: hint)),
              ]),
              if (f.examples.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 6, runSpacing: 4, children: f.examples.map(chip).toList())),
            ])),
        Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.3)),
      ],
    ]);
  }
}

/// 条件编辑器：多行编辑完整表达式，逐条显示 / 删除 / 定位条件，下方为字段与示例（点击追加，不关闭）。
class QueryEditor<T> extends StatefulWidget {
  final QuerySchema<T> schema;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final List<String> quickFilters;

  const QueryEditor(
      {super.key,
      required this.schema,
      required this.controller,
      required this.onChanged,
      this.quickFilters = const []});

  @override
  State<QueryEditor<T>> createState() => _QueryEditorState<T>();
}

class _QueryEditorState<T> extends State<QueryEditor<T>> {
  late final TextEditingController _edit = TextEditingController(text: widget.controller.text);
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _edit.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _set(String text, {TextSelection? selection}) {
    _edit.value = TextEditingValue(text: text, selection: selection ?? TextSelection.collapsed(offset: text.length));
    _sync(text);
  }

  void _sync(String text) {
    setState(() {});
    if (widget.controller.text == text) return;
    widget.controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    widget.onChanged(text);
  }

  void _insert(String text) {
    final current = _edit.text.trimRight();
    _set(current.isEmpty ? text : '$current $text');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCN = Localizations.localeOf(context).languageCode == 'zh';
    final text = _edit.text;
    final spans = Query.tokenSpans(text);
    final count = spans.where((e) => !Query.isOrToken(e.value)).length;

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 6, 0),
          child: Row(children: [
            Text(isCN ? '筛选条件' : 'Filter', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            if (count > 0)
              Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text('$count', style: TextStyle(color: theme.colorScheme.primary))),
            const Spacer(),
            TextButton(onPressed: text.isEmpty ? null : () => _set(''), child: Text(isCN ? '清空' : 'Clear')),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(isCN ? '完成' : 'Done')),
          ])),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
              controller: _edit,
              focusNode: _focus,
              minLines: 2,
              maxLines: 5,
              keyboardType: TextInputType.url,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              onChanged: _sync,
              decoration: InputDecoration(
                  isDense: true,
                  hintText: 'method:POST status:4xx -host:*.ads.com',
                  hintStyle: const TextStyle(fontSize: 12),
                  contentPadding: const EdgeInsets.all(10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
      if (spans.isNotEmpty)
        ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 132),
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [for (var i = 0; i < spans.length; i++) _chip(theme, text, spans[i], i)]))),
      const SizedBox(height: 6),
      Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.4)),
      Flexible(
          child: QuerySyntaxHelp<T>(schema: widget.schema, quickFilters: widget.quickFilters, onInsert: _insert)),
    ]);
  }

  Widget _chip(ThemeData theme, String text, QueryToken token, int index) {
    if (Query.isOrToken(token.value)) {
      return Text('OR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.tertiary));
    }
    final term = Query.parseTerm(token.value, widget.schema.hasField);
    final negate = term?.negate ?? false;
    final isField = term != null && !term.isText;
    final color = negate
        ? theme.colorScheme.error
        : isField
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface;
    return InputChip(
        label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(token.source(text),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: color))),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(color: color.withValues(alpha: 0.35)),
        deleteIconColor: color.withValues(alpha: 0.7),
        // 点击：在输入框中选中该条件，便于直接修改
        onPressed: () {
          _focus.requestFocus();
          _edit.selection = TextSelection(baseOffset: token.start, extentOffset: token.end);
        },
        onDeleted: () => _set(Query.removeToken(text, index)));
  }
}

/// 搜索框右侧的筛选按钮：显示条件数角标，点击打开 [QueryEditor]
class QueryFilterButton<T> extends StatelessWidget {
  final QuerySchema<T> schema;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final List<String> quickFilters;
  final double iconSize;
  final BoxConstraints? constraints;

  const QueryFilterButton(
      {super.key,
      required this.schema,
      required this.controller,
      required this.onChanged,
      this.quickFilters = const [],
      this.iconSize = 20,
      this.constraints});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final count = Query.tokenize(value.text).where((t) => !Query.isOrToken(t)).length;
          return IconButton(
              tooltip: Localizations.localeOf(context).languageCode == 'zh' ? '筛选条件' : 'Filter',
              padding: EdgeInsets.zero,
              constraints: constraints,
              icon: Badge(
                  isLabelVisible: count > 1,
                  label: Text('$count', style: const TextStyle(fontSize: 9)),
                  backgroundColor: theme.colorScheme.primary,
                  textColor: theme.colorScheme.onPrimary,
                  child: Icon(Icons.tune,
                      size: iconSize,
                      color: count > 0 ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant)),
              onPressed: () => QuerySyntaxHelp.show<T>(context,
                  schema: schema, controller: controller, onChanged: onChanged, quickFilters: quickFilters));
        });
  }
}
