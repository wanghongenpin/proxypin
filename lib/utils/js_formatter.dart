class JS {
  /// 格式化 JavaScript 字符串（适合还原压缩后的 JS）
  static String pretty(String input) {
    if (input.trim().isEmpty) return input;
    try {
      final result = _JsFormatter(input).format();
      return result.isEmpty ? input : result;
    } catch (_) {
      return input;
    }
  }
}

class _JsFormatter {
  final String _src;
  int _i = 0;
  int _depth = 0;
  final StringBuffer _buf = StringBuffer();
  static const String _ind = '  ';

  _JsFormatter(this._src);

  String format() {
    while (_i < _src.length) {
      _step();
    }
    return _buf.toString().trim();
  }

  void _step() {
    final c = _src[_i];

    // Line comment
    if (c == '/' && _peek(1) == '/') {
      _readLineComment();
      return;
    }

    // Block comment
    if (c == '/' && _peek(1) == '*') {
      _readBlockComment();
      return;
    }

    // Template literal
    if (c == '`') {
      _readTemplateLiteral();
      return;
    }

    // String literal
    if (c == '"' || c == "'") {
      _readString(c);
      return;
    }

    // Open brace
    if (c == '{') {
      _trimTrailingSpace();
      _buf.write(' {\n');
      _depth++;
      _writeIndent();
      _i++;
      _skipWs();
      return;
    }

    // Close brace
    if (c == '}') {
      _trimTrailingSpace();
      _depth = (_depth - 1).clamp(0, 100);
      _buf.write('\n');
      _writeIndent();
      _buf.write('}');
      _i++;
      _skipWs();
      // Don't add newline if followed by ; , )
      if (_i < _src.length && _src[_i] != ';' && _src[_i] != ',' && _src[_i] != ')') {
        _buf.writeln();
        if (_depth > 0 && _i < _src.length) _writeIndent();
      }
      return;
    }

    // Semicolon
    if (c == ';') {
      _buf.write(';');
      _i++;
      _skipWs();
      if (_i < _src.length && _src[_i] != '}') {
        _buf.writeln();
        _writeIndent();
      }
      return;
    }

    // Comma — keep on same line but normalize space after
    if (c == ',') {
      _buf.write(', ');
      _i++;
      _skipWs();
      return;
    }

    // Whitespace normalization
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      final s = _buf.toString();
      if (s.isNotEmpty) {
        final last = s[s.length - 1];
        if (last != ' ' && last != '\n') {
          _buf.write(' ');
        }
      }
      _i++;
      return;
    }

    _buf.write(c);
    _i++;
  }

  void _readLineComment() {
    while (_i < _src.length && _src[_i] != '\n') {
      _buf.write(_src[_i]);
      _i++;
    }
    _buf.writeln();
    _writeIndent();
  }

  void _readBlockComment() {
    _buf.write('/*');
    _i += 2;
    while (_i < _src.length) {
      if (_src[_i] == '*' && _peek(1) == '/') {
        _buf.write('*/');
        _i += 2;
        break;
      }
      _buf.write(_src[_i]);
      _i++;
    }
  }

  void _readString(String quote) {
    _buf.write(quote);
    _i++;
    while (_i < _src.length) {
      final c = _src[_i];
      if (c == '\\') {
        _buf.write(c);
        _i++;
        if (_i < _src.length) {
          _buf.write(_src[_i]);
          _i++;
        }
        continue;
      }
      _buf.write(c);
      _i++;
      if (c == quote) break;
    }
  }

  void _readTemplateLiteral() {
    _buf.write('`');
    _i++;
    while (_i < _src.length) {
      final c = _src[_i];
      if (c == '\\') {
        _buf.write(c);
        _i++;
        if (_i < _src.length) {
          _buf.write(_src[_i]);
          _i++;
        }
        continue;
      }
      if (c == '`') {
        _buf.write(c);
        _i++;
        break;
      }
      _buf.write(c);
      _i++;
    }
  }

  void _trimTrailingSpace() {
    final s = _buf.toString().trimRight();
    _buf.clear();
    _buf.write(s);
  }

  void _skipWs() {
    while (_i < _src.length &&
        (_src[_i] == ' ' || _src[_i] == '\t' || _src[_i] == '\n' || _src[_i] == '\r')) {
      _i++;
    }
  }

  void _writeIndent() {
    _buf.write(_ind * _depth);
  }

  String? _peek(int offset) {
    final idx = _i + offset;
    return idx < _src.length ? _src[idx] : null;
  }
}

