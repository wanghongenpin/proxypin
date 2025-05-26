import 'dart:typed_data';

import 'package:proxypin/network/http/constants.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/util/byte_buf.dart';

/// http解析器
class HttpParse {
  static const int defaultMaxLength = 102400;

  /// 解析请求行
  List<String> parseInitialLine(ByteBuf data, int size) {
    List<String> initialLine = [];
    var startIndex = data.readerIndex;
    for (int i = data.readerIndex; i < size; i++) {
      if (_isLineEnd(data, i)) {
        //请求行结束
        Uint8List requestLine = data.readBytes(i - data.readerIndex);
        data.skipBytes(2);
        initialLine = _splitLine(requestLine);
        break;
      }
    }

    if (initialLine.length == 3) {
      return initialLine;
    }

    if (data.length > defaultMaxLength) {
      throw Exception("request line too long");
    }

    data.readerIndex = startIndex;
    return [];
  }

  //分割行
  List<String> _splitLine(Uint8List data) {
    List<String> lines = [];
    int start = 0;
    for (int i = 0; i < data.length; i++) {
      if (data[i] == HttpConstants.sp) {
        lines.add(String.fromCharCodes(data.sublist(start, i)));
        start = i + 1;
        if (lines.length == 2) {
          break;
        }
      }
    }
    lines.add(String.fromCharCodes(data.sublist(start)));
    return lines;
  }

  /// 解析请求头
  bool parseHeaders(ByteBuf data, HttpHeaders headers) {
    if (!data.isReadable()) {
      return false;
    }

    int startIndex = data.readerIndex;
    for (int i = data.readerIndex; i < data.length; i++) {
      if ((i - startIndex) > defaultMaxLength) {
        throw Exception("header too long");
      }

      if (_isLineEnd(data, i)) {
        Uint8List line = data.readBytes(i - data.readerIndex);
        data.skipBytes(2);
        if (line.isEmpty) {
          break;
        }
        var header = _splitHeader(line);
        headers.add(header[0], header[1]);
      }
    }

    //\r\n \r\n结束
    return _isLineEnd(data, data.readerIndex - 4) && _isLineEnd(data, data.readerIndex - 2);
  }

  //是否行结束
  bool _isLineEnd(ByteBuf data, int index) {
    return index + 1 < data.length && data.get(index) == HttpConstants.cr && data.get(index + 1) == HttpConstants.lf;
  }

  //分割头
  List<String> _splitHeader(List<int> data) {
    List<String> headers = [];
    for (int i = 0; i < data.length; i++) {
      if (data[i] == HttpConstants.colon) {
        headers.add(String.fromCharCodes(data.sublist(0, i)));

        if (data[i + 1] == HttpConstants.sp) {
          headers.add(String.fromCharCodes(data.sublist(i + 2)));
        } else {
          headers.add(String.fromCharCodes(data.sublist(i + 1)));
        }
        break;
      }
    }
    return headers;
  }
}
