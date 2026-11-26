import 'package:flutter/material.dart';
import 'package:proxypin/utils/query/query.dart';

/// 查询语法帮助：列出字段与示例，点击示例插入到输入框。
class QuerySyntaxHelp<T> extends StatelessWidget {
  final QuerySchema<T> schema;
  final ValueChanged<String> onInsert;

  /// 顶部常用快捷条件
  final List<String> quickFilters;

  const QuerySyntaxHelp({super.key, required this.schema, required this.onInsert, this.quickFilters = const []});

  /// 弹出帮助；[controller] 为搜索输入框，点击后追加条件并回调 [onChanged]
  static Future<void> show<T>(BuildContext context,
      {required QuerySchema<T> schema,
      required TextEditingController controller,
      required ValueChanged<String> onChanged,
      List<String> quickFilters = const []}) {
    void insert(String text) {
      final current = controller.text.trimRight();
      final next = current.isEmpty ? text : '$current $text';
      controller.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length));
      onChanged(next);
    }

    return showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        builder: (ctx) => ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
            child: QuerySyntaxHelp<T>(
                schema: schema,
                quickFilters: quickFilters,
                onInsert: (text) {
                  insert(text);
                  Navigator.of(ctx).pop();
                })));
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

    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), shrinkWrap: true, children: [
      Text(isCN ? '高级筛选语法' : 'Filter syntax', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
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
