/// 通用查询表达式（HTTP 请求列表、原始抓包列表共用）。
///
/// 语法：
/// - 空格分隔的条件为 AND；`OR` 或 `|` 分隔为 OR（`a b | c` = `(a AND b) OR c`）
/// - `field:value` 字段条件，未知字段名按普通文本处理（因此 `https://x.com` 仍是文本搜索）
/// - 前缀 `-` 或 `!` 取反：`-host:*.ads.com`
/// - 比较：`size>10k`、`time>=500ms`、`status:>=400`、`status!=200`
/// - 值：普通文本（包含，忽略大小写）、`*` 通配（整体匹配）、`/正则/`、`"带 空格"`、
///   数字范围 `400-499`、状态码类 `4xx`、逗号多选 `method:GET,POST`
library;

enum QueryOp { contains, eq, ne, gt, ge, lt, le }

class QueryTerm {
  /// 字段名（小写）；为空表示普通文本
  final String? field;
  final QueryOp op;
  final String value;
  final bool negate;

  const QueryTerm({this.field, this.op = QueryOp.contains, required this.value, this.negate = false});

  bool get isText => field == null;

  /// 逗号分隔的多选值
  List<String> get values => value.contains(',') && !isRegex ? value.split(',').where((e) => e.isNotEmpty).toList() : [value];

  bool get isRegex => value.length >= 2 && value.startsWith('/') && value.endsWith('/');

  @override
  String toString() => '${negate ? '-' : ''}${field ?? ''}${field == null ? '' : op.name}$value';

  // ---------------- 匹配辅助 ----------------

  /// 文本匹配：正则 / 通配(整体) / 包含；op 为 eq 时要求相等
  bool matchText(String? text) {
    if (text == null) return false;
    for (final v in values) {
      if (_matchTextOne(text, v)) return true;
    }
    return false;
  }

  bool _matchTextOne(String text, String v) {
    if (v.length >= 2 && v.startsWith('/') && v.endsWith('/')) {
      try {
        return RegExp(v.substring(1, v.length - 1), caseSensitive: false).hasMatch(text);
      } catch (_) {
        return false;
      }
    }
    final lowerText = text.toLowerCase();
    final lowerV = v.toLowerCase();
    if (lowerV.contains('*') || lowerV.contains('?')) {
      return _globToRegExp(lowerV).hasMatch(lowerText);
    }
    if (op == QueryOp.eq || op == QueryOp.ne) return lowerText == lowerV;
    return lowerText.contains(lowerV);
  }

  /// 任一文本匹配
  bool matchAnyText(Iterable<String?> texts) => texts.any(matchText);

  /// 数值匹配，支持比较符、范围 a-b、单位（由 [parser] 解析）
  bool matchNumber(num? actual, {num? Function(String)? parser}) {
    if (actual == null) return false;
    parser ??= parseNumber;
    for (final v in values) {
      if (_matchNumberOne(actual, v, parser)) return true;
    }
    return false;
  }

  bool _matchNumberOne(num actual, String v, num? Function(String) parser) {
    switch (op) {
      case QueryOp.gt:
      case QueryOp.ge:
      case QueryOp.lt:
      case QueryOp.le:
        final n = parser(v);
        if (n == null) return false;
        return switch (op) {
          QueryOp.gt => actual > n,
          QueryOp.ge => actual >= n,
          QueryOp.lt => actual < n,
          _ => actual <= n,
        };
      default:
        final range = _splitRange(v);
        if (range != null) {
          final from = range.$1.isEmpty ? null : parser(range.$1);
          final to = range.$2.isEmpty ? null : parser(range.$2);
          if (from == null && to == null) return false;
          return (from == null || actual >= from) && (to == null || actual <= to);
        }
        final n = parser(v);
        return n != null && actual == n;
    }
  }

  static (String, String)? _splitRange(String v) {
    // 负号开头不视为范围；"400-499"、"1k-" 、"-100" 不支持
    final idx = v.indexOf('-', 1);
    if (idx <= 0) return null;
    return (v.substring(0, idx), v.substring(idx + 1));
  }

  /// 数字，支持大小单位 b/k/kb/m/mb/g/gb（1024 进制）
  static num? parseNumber(String v) {
    final m = RegExp(r'^(\d+(?:\.\d+)?)\s*([a-z]*)$', caseSensitive: false).firstMatch(v.trim());
    if (m == null) return null;
    final n = double.parse(m.group(1)!);
    switch (m.group(2)!.toLowerCase()) {
      case '':
      case 'b':
        return n;
      case 'k':
      case 'kb':
        return n * 1024;
      case 'm':
      case 'mb':
        return n * 1024 * 1024;
      case 'g':
      case 'gb':
        return n * 1024 * 1024 * 1024;
    }
    return null;
  }

  /// 时长（毫秒），支持 ms/s/m/min，缺省为毫秒
  static num? parseDurationMs(String v) {
    final m = RegExp(r'^(\d+(?:\.\d+)?)\s*([a-z]*)$', caseSensitive: false).firstMatch(v.trim());
    if (m == null) return null;
    final n = double.parse(m.group(1)!);
    switch (m.group(2)!.toLowerCase()) {
      case '':
      case 'ms':
        return n;
      case 's':
        return n * 1000;
      case 'm':
      case 'min':
        return n * 60000;
    }
    return null;
  }

  /// 状态码：支持 2xx / 4xx 类别，其余走数值匹配
  bool matchStatus(int? code) {
    if (code == null) return false;
    for (final v in values) {
      final cls = RegExp(r'^([1-5])xx$', caseSensitive: false).firstMatch(v);
      if (cls != null) {
        final c = int.parse(cls.group(1)!);
        final hit = code ~/ 100 == c;
        if (op == QueryOp.ne ? !hit : hit) return true;
        continue;
      }
      final single = QueryTerm(field: field, op: op == QueryOp.ne ? QueryOp.eq : op, value: v);
      final hit = single.matchNumber(code);
      if (op == QueryOp.ne ? !hit : hit) return true;
    }
    return false;
  }

  static RegExp _globToRegExp(String glob) {
    final sb = StringBuffer('^');
    for (final ch in glob.split('')) {
      switch (ch) {
        case '*':
          sb.write('.*');
        case '?':
          sb.write('.');
        default:
          sb.write(RegExp.escape(ch));
      }
    }
    sb.write(r'$');
    return RegExp(sb.toString());
  }
}

/// 字段定义：一个字段可有多个别名
class QueryField<T> {
  final List<String> names;
  final String description;
  final List<String> examples;

  /// 返回条件是否满足（不考虑 negate）
  final bool Function(T item, QueryTerm term) test;

  const QueryField(this.names, this.test, {this.description = '', this.examples = const []});
}

class QuerySchema<T> {
  final List<QueryField<T>> fields;

  /// 普通文本条件的匹配
  final bool Function(T item, QueryTerm term) textTest;

  late final Map<String, QueryField<T>> _byName = {
    for (final f in fields)
      for (final n in f.names) n.toLowerCase(): f
  };

  QuerySchema({required this.fields, required this.textTest});

  QueryField<T>? field(String name) => _byName[name.toLowerCase()];

  bool hasField(String name) => _byName.containsKey(name.toLowerCase());

  Query<T> parse(String input) => Query._parse(input, this);
}

class Query<T> {
  final QuerySchema<T> schema;

  /// OR 分组，每组内 AND
  final List<List<QueryTerm>> groups;

  Query._(this.schema, this.groups);

  bool get isEmpty => groups.every((g) => g.isEmpty);

  /// 是否包含字段条件（否则只是普通文本搜索）
  bool get hasFieldTerms => groups.any((g) => g.any((t) => !t.isText));

  bool get hasOr => groups.length > 1;

  List<QueryTerm> get terms => groups.expand((g) => g).toList();

  bool matches(T item) {
    if (isEmpty) return true;
    for (final group in groups) {
      if (group.isEmpty) continue;
      if (group.every((t) => _evalTerm(item, t))) return true;
    }
    return false;
  }

  bool _evalTerm(T item, QueryTerm term) {
    bool result;
    if (term.isText) {
      result = schema.textTest(item, term);
    } else {
      final f = schema.field(term.field!);
      result = f == null ? schema.textTest(item, term) : f.test(item, term);
    }
    return term.negate ? !result : result;
  }

  // ---------------- 解析 ----------------

  static Query<T> _parse<T>(String input, QuerySchema<T> schema) {
    final groups = <List<QueryTerm>>[[]];
    for (final token in tokenize(input)) {
      if (token == '|' || token == 'OR' || token == '||') {
        if (groups.last.isNotEmpty) groups.add([]);
        continue;
      }
      final term = parseTerm(token, schema.hasField);
      if (term != null) groups.last.add(term);
    }
    groups.removeWhere((g) => g.isEmpty);
    return Query._(schema, groups);
  }

  /// 按空白切分，保留引号与 /正则/ 内的空格
  static List<String> tokenize(String input) {
    final tokens = <String>[];
    final sb = StringBuffer();
    String? quote;
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (quote != null) {
        if (ch == quote) {
          quote = null;
          if (ch == '/') sb.write(ch);
        } else {
          sb.write(ch);
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        continue;
      }
      // /正则/ 仅在值起始处生效（token 开头或紧跟 : = ~ 等之后）
      if (ch == '/' && (sb.isEmpty || RegExp(r'[:=~<>!-]$').hasMatch(sb.toString())) && input.indexOf('/', i + 1) > i) {
        quote = '/';
        sb.write(ch);
        continue;
      }
      if (ch.trim().isEmpty) {
        if (sb.isNotEmpty) tokens.add(sb.toString());
        sb.clear();
        continue;
      }
      sb.write(ch);
    }
    if (sb.isNotEmpty) tokens.add(sb.toString());
    return tokens;
  }

  static final _fieldPattern = RegExp(r'^([A-Za-z_][\w.]*)(:>=|:<=|:>|:<|:!=|:=|:!|>=|<=|!=|:|=|>|<|~)(.*)$');

  static QueryTerm? parseTerm(String token, bool Function(String) isField) {
    var negate = false;
    var t = token;
    if (t.length > 1 && (t.startsWith('-') || t.startsWith('!'))) {
      negate = true;
      t = t.substring(1);
    }
    if (t.isEmpty) return null;

    final m = _fieldPattern.firstMatch(t);
    if (m != null && isField(m.group(1)!)) {
      final field = m.group(1)!.toLowerCase();
      var opText = m.group(2)!;
      var value = m.group(3)!;
      // field:>=x 写法
      if (opText == ':' && value.isNotEmpty) {
        final inner = RegExp(r'^(>=|<=|!=|>|<|=)(.*)$').firstMatch(value);
        if (inner != null) {
          opText = inner.group(1)!;
          value = inner.group(2)!;
        }
      }
      final op = switch (opText.replaceFirst(':', '')) {
        '>=' => QueryOp.ge,
        '<=' => QueryOp.le,
        '>' => QueryOp.gt,
        '<' => QueryOp.lt,
        '!=' || '!' => QueryOp.ne,
        '=' => QueryOp.eq,
        _ => QueryOp.contains,
      };
      // != 统一转换为取反的等值匹配，字段实现只需处理正向逻辑
      if (op == QueryOp.ne) {
        return QueryTerm(field: field, op: QueryOp.eq, value: value, negate: !negate);
      }
      return QueryTerm(field: field, op: op, value: value, negate: negate);
    }
    return QueryTerm(value: t, negate: negate);
  }
}
