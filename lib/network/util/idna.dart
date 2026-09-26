/*
 * Copyright 2023 Hongen Wang All rights reserved.
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

/// 主机名规范化工具。
///
/// 部分客户端会把 URI 中非 ASCII 的主机名百分号编码后发送, 例如
/// `http://%E5%B0%8F%E5%BA%A6.%E4%B8%AD%E5%9B%BD/` (解码为 `小度.中国`)。
/// 这类含 `%` 的字符串若直接交给 dart:io 的 [Socket.connect],
/// 会被误判为 IPv6 link-local 作用域而抛出 FormatException(#923)。
///
/// 这里先做百分号解码, 再按 IDNA 将非 ASCII 主机名转为 punycode(如 `xn--`)
/// 形式, 便于各平台 DNS 解析。
library;

String _encodeDigit(int d) {
  if (d < 26) return String.fromCharCode(0x61 + d);
  return String.fromCharCode(0x30 + (d - 26));
}

int _adapt(int delta, int numPoints, bool firstTime) {
  delta = firstTime ? delta ~/ 700 : delta ~/ 2;
  delta += delta ~/ numPoints;
  int k = 0;
  while (delta > 455) {
    delta = delta ~/ 35;
    k += 36;
  }
  return k + (36 * delta) ~/ (delta + 38);
}

/// RFC 3492 punycode 编码
String punycodeEncode(String input) {
  final out = StringBuffer();
  final inputList = input.runes.toList();
  int n = 128;
  int delta = 0;
  int bias = 72;
  int h = 0;
  for (final c in inputList) {
    if (c < 0x80) {
      out.writeCharCode(c);
      h++;
    }
  }
  final b = h;
  if (b > 0 && h < inputList.length) out.write('-');
  while (h < inputList.length) {
    int m = 0x7fffffff;
    for (final c in inputList) {
      if (c >= n && c < m) m = c;
    }
    delta += (m - n) * (h + 1);
    n = m;
    for (final c in inputList) {
      if (c < n) delta++;
      if (c == n) {
        int q = delta;
        for (int k = 36;; k += 36) {
          int t;
          if (k <= bias) {
            t = 1;
          } else if (k >= bias + 26) {
            t = 26;
          } else {
            t = k - bias;
          }
          if (q < t) break;
          out.write(_encodeDigit(t + (q - t) % (36 - t)));
          q = (q - t) ~/ (36 - t);
        }
        out.write(_encodeDigit(q));
        bias = _adapt(delta, h + 1, h == b);
        delta = 0;
        h++;
      }
    }
    delta++;
    n++;
  }
  return out.toString();
}

/// IDNA 转 ASCII: 将主机名中的非 ASCII 标签转成 `xn--` 开头的 punycode,
/// 纯 ASCII 标签保持不变。
String idnToAscii(String host) {
  if (host.isEmpty || host.codeUnits.every((c) => c < 0x80)) {
    return host;
  }

  final trailingDot = host.endsWith('.');
  final labels = host.split('.').where((label) => label.isNotEmpty);
  final sb = StringBuffer();
  for (final label in labels) {
    if (sb.isNotEmpty) sb.write('.');
    if (label.codeUnits.every((c) => c < 0x80)) {
      sb.write(label);
    } else {
      sb.write('xn--');
      sb.write(punycodeEncode(label.toLowerCase()));
    }
  }
  if (trailingDot) sb.write('.');
  return sb.toString();
}

/// 将主机名规范化为可用于连接/DNS 的 ASCII 形式。
///
/// 1. 若包含百分号编码则先解码(如 `%E5%B0%8F` -> `小`)；
/// 2. 再通过 [idnToAscii] 将非 ASCII 主机名转为 punycode。
///
/// IPv6 link-local 作用域(如 `fe80::1%eth0`)不是合法的百分号编码,
/// 解码会失败, 此时原样返回, 不会破坏作用域语法。
String hostToAscii(String host) {
  if (host.isEmpty || !host.contains('%')) {
    return idnToAscii(host);
  }
  try {
    return idnToAscii(Uri.decodeComponent(host));
  } on FormatException {
    return host;
  } on ArgumentError {
    return host;
  }
}
