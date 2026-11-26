import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/utils/query/query.dart';

/// HTTP 请求列表的查询字段
class RequestQueryItem {
  final HttpRequest request;
  final HttpResponse? response;

  /// 普通文本条件的匹配（沿用搜索范围设置）
  final bool Function(RequestQueryItem item, QueryTerm term)? textMatcher;

  RequestQueryItem(this.request, this.response, {this.textMatcher});
}

/// 帮助面板中的常用快捷条件
const List<String> quickRequestFilters = [
  'is:error',
  'is:pending',
  'is:slow',
  'type:json',
  '-type:image',
  'method:POST',
  'status:4xx',
  'size>100k',
  'proto:ws',
];

class RequestQuery {
  RequestQuery._();

  static final Map<String, List<ContentType>> _typeAliases = {
    'img': [ContentType.image],
    'image': [ContentType.image],
    'javascript': [ContentType.js],
    'script': [ContentType.js],
    'form': [ContentType.formUrl, ContentType.formData],
    'multipart': [ContentType.formData],
    'media': [ContentType.video],
    'event-stream': [ContentType.sse],
    'other': [ContentType.http],
  };

  static bool _matchContentType(QueryTerm term, HttpMessage? message) {
    if (message == null) return false;
    final type = message.contentType;
    final header = message.headers.contentType;
    for (final v in term.values) {
      final lower = v.toLowerCase();
      final aliases = _typeAliases[lower];
      if (aliases != null && aliases.contains(type)) return true;
      if (type.name.toLowerCase() == lower) return true;
      // 退化为 Content-Type 头文本匹配，例如 type:protobuf
      if (QueryTerm(field: term.field, value: v).matchText(header)) return true;
    }
    return false;
  }

  static int? _bodySize(HttpMessage? m) {
    if (m == null) return null;
    return m.body?.length ?? (m.contentLength >= 0 ? m.contentLength : m.packageSize);
  }

  static int? _durationMs(RequestQueryItem item) {
    final res = item.response;
    if (res == null) return null;
    return res.responseTime.difference(item.request.requestTime).inMilliseconds;
  }

  /// header:Name 存在；header:Name=value 值匹配；header:value 匹配任意头名或值
  static bool _matchHeaders(QueryTerm term, Iterable<HttpMessage?> messages) {
    final value = term.value;
    final eq = value.indexOf('=');
    for (final m in messages) {
      if (m == null) continue;
      for (final entry in m.headers.entries) {
        if (eq > 0) {
          final name = value.substring(0, eq);
          if (entry.key.toLowerCase() != name.toLowerCase()) continue;
          final valueTerm = QueryTerm(field: term.field, value: value.substring(eq + 1));
          if (entry.value.any(valueTerm.matchText)) return true;
        } else if (term.op == QueryOp.eq) {
          if (entry.key.toLowerCase() == value.toLowerCase()) return true;
        } else {
          if (term.matchText(entry.key) || entry.value.any(term.matchText)) return true;
        }
      }
    }
    return false;
  }

  static bool _matchBody(QueryTerm term, HttpMessage? m) {
    if (m == null) return false;
    if (m.contentType.isBinary) return false;
    return term.matchText(m.bodyAsString);
  }

  static bool _matchProto(QueryTerm term, RequestQueryItem item) {
    final req = item.request;
    final res = item.response;
    final scheme = req.hostAndPort?.scheme ?? '';
    for (final v in term.values) {
      final hit = switch (v.toLowerCase()) {
        'https' => scheme.startsWith('https'),
        'http' => scheme.startsWith('http://'),
        'ws' || 'websocket' => req.isWebSocket || res?.isWebSocket == true,
        'wss' => (req.isWebSocket || res?.isWebSocket == true) && scheme.startsWith('https'),
        'sse' => res?.contentType == ContentType.sse,
        'h1' || 'http1' || 'http/1.1' => req.protocolVersion == 'HTTP/1.1',
        'h2' || 'http2' || 'http/2' => req.protocolVersion == 'HTTP/2' || req.protocolVersion == 'h2',
        'graphql' => req.graphqlOperationName != null || req.path.contains('graphql'),
        _ => false,
      };
      if (hit) return true;
    }
    return false;
  }

  static bool _matchIs(QueryTerm term, RequestQueryItem item) {
    final res = item.response;
    for (final v in term.values) {
      final hit = switch (v.toLowerCase()) {
        'pending' => res == null,
        'done' || 'complete' => res != null,
        'error' || 'fail' || 'failed' => res == null ? false : res.status.code >= 400,
        'ok' || 'success' => res != null && res.status.code >= 200 && res.status.code < 400,
        'redirect' => res != null && res.status.code >= 300 && res.status.code < 400,
        'ws' || 'websocket' => item.request.isWebSocket,
        'sse' => res?.contentType == ContentType.sse,
        'https' => item.request.hostAndPort?.scheme.startsWith('https') == true,
        'h2' => item.request.protocolVersion == 'HTTP/2',
        'graphql' => item.request.graphqlOperationName != null,
        'cookie' => item.request.headers.get('Cookie') != null,
        'large' => (_bodySize(res) ?? 0) > 1024 * 1024,
        'slow' => (_durationMs(item) ?? 0) > 1000,
        _ => false,
      };
      if (hit) return true;
    }
    return false;
  }

  static final QuerySchema<RequestQueryItem> schema = QuerySchema<RequestQueryItem>(
    textTest: (item, term) {
      if (item.textMatcher != null) return item.textMatcher!(item, term);
      return term.matchText(item.request.requestUrl);
    },
    fields: [
      QueryField(['method', 'm'], (i, t) => t.matchText(i.request.method.name),
          description: '请求方法', examples: ['method:POST', 'm:GET,PUT']),
      QueryField(['host', 'domain', 'd'], (i, t) => t.matchAnyText([i.request.hostAndPort?.host, i.request.remoteDomain()]),
          description: '域名，支持 * 通配', examples: ['host:*.example.com', '-host:ads']),
      QueryField(['path', 'p'], (i, t) => t.matchText(i.request.path), description: '路径', examples: ['path:/api/']),
      QueryField(['url', 'u'], (i, t) => t.matchText(i.request.requestUrl), description: '完整 URL', examples: ['url:/v\\d+/']),
      QueryField(['query', 'param'], (i, t) {
        final q = i.request.requestUri?.query;
        if (t.value.contains('=')) {
          final idx = t.value.indexOf('=');
          final v = i.request.queries[t.value.substring(0, idx)];
          return QueryTerm(field: t.field, value: t.value.substring(idx + 1)).matchText(v);
        }
        return t.matchText(q) || i.request.queries.keys.any(t.matchText);
      }, description: '查询参数', examples: ['query:token', 'query:page=2']),
      QueryField(['status', 's', 'code'], (i, t) => t.matchStatus(i.response?.status.code),
          description: '状态码，支持 4xx / 范围 / 比较', examples: ['status:4xx', 'status:>=500', 'status!=200']),
      QueryField(['type', 't', 'restype'], (i, t) => _matchContentType(t, i.response),
          description: '响应类型 json/html/js/css/image/font/video/xml/text/sse/form', examples: ['type:json', '-type:image']),
      QueryField(['reqtype'], (i, t) => _matchContentType(t, i.request), description: '请求类型', examples: ['reqtype:form']),
      QueryField(['size', 'ressize'], (i, t) => t.matchNumber(_bodySize(i.response)),
          description: '响应大小，单位 b/k/m', examples: ['size>100k', 'size:1k-10k']),
      QueryField(['reqsize'], (i, t) => t.matchNumber(_bodySize(i.request)), description: '请求体大小', examples: ['reqsize>1k']),
      QueryField(['time', 'duration', 'cost'], (i, t) => t.matchNumber(_durationMs(i), parser: QueryTerm.parseDurationMs),
          description: '耗时，单位 ms/s', examples: ['time>1s', 'time:100-500']),
      QueryField(['header', 'h'], (i, t) => _matchHeaders(t, [i.request, i.response]),
          description: '请求或响应头', examples: ['header:authorization', 'header:x-env=prod']),
      QueryField(['reqheader', 'qh'], (i, t) => _matchHeaders(t, [i.request]), description: '请求头'),
      QueryField(['resheader', 'rh'], (i, t) => _matchHeaders(t, [i.response]), description: '响应头'),
      QueryField(['body', 'b'], (i, t) => _matchBody(t, i.request) || _matchBody(t, i.response),
          description: '请求或响应体', examples: ['body:"error_code"']),
      QueryField(['reqbody', 'qb'], (i, t) => _matchBody(t, i.request), description: '请求体'),
      QueryField(['resbody', 'rb'], (i, t) => _matchBody(t, i.response), description: '响应体'),
      QueryField(['cookie'], (i, t) => i.request.cookies.any(t.matchText) || (i.response?.headers.getList('Set-Cookie')?.any(t.matchText) ?? false),
          description: 'Cookie', examples: ['cookie:session']),
      QueryField(['app', 'process'], (i, t) => t.matchAnyText([i.request.processInfo?.name, i.request.processInfo?.id]),
          description: '来源应用名或包名', examples: ['app:微信', 'app:com.tencent.*']),
      QueryField(['port'], (i, t) => t.matchNumber(i.request.hostAndPort?.port), description: '端口', examples: ['port:8080']),
      QueryField(['ip'], (i, t) => t.matchAnyText([i.request.remoteHost, i.response?.remoteHost]), description: '客户端/远程 IP'),
      QueryField(['proto', 'protocol', 'scheme'], (i, t) => _matchProto(t, i),
          description: 'http/https/ws/sse/h1/h2/graphql', examples: ['proto:h2', 'proto:ws']),
      QueryField(['is', 'has'], (i, t) => _matchIs(t, i),
          description: 'pending/error/ok/redirect/ws/sse/https/h2/graphql/cookie/large/slow', examples: ['is:error', 'is:slow']),
    ],
  );

  static Query<RequestQueryItem> parse(String input) => schema.parse(input);
}
