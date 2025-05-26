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

import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';

/// 获取主机和端口
HostAndPort getHostAndPort(HttpRequest request, {bool? ssl}) {
  String requestUri = request.uri;
  //有些请求直接是路径 /xxx, 从header取host
  if (request.uri.startsWith("/")) {
    requestUri = request.headers.get(HttpHeaders.HOST)!;
  }
  return HostAndPort.of(requestUri, ssl: ssl);
}

class HostAndPort {
  static final ipv6Pattern = r'^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|'
      r'([0-9a-fA-F]{1,4}:){1,7}:|'
      r'([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|'
      r'([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|'
      r'([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|'
      r'([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|'
      r'([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|'
      r'[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|'
      r':((:[0-9a-fA-F]{1,4}){1,7}|:)|'
      r'fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|'
      r'::(ffff(:0{1,4}){0,1}:){0,1}'
      r'(([0-9]{1,3}\.){3,3}[0-9]{1,3})|'
      r'([0-9a-fA-F]{1,4}:){1,4}:'
      r'(([0-9]{1,3}\.){3,3}[0-9]{1,3}))$';

  static final ipV6RegExp = RegExp(ipv6Pattern);

  static const String httpScheme = "http://";
  static const String httpsScheme = "https://";
  static const String wsScheme = "ws://";
  static const String wssScheme = "wss://";

  static const schemes = [httpsScheme, httpScheme, wssScheme, wsScheme];

  String scheme;
  String host;
  final int port;
  bool? _ipv6;

  bool get isIPv6 {
    _ipv6 ??= _isIPv6(host);
    return _ipv6!;
  }

  static bool _isIPv6(String address) {
    return ipV6RegExp.hasMatch(address);
  }

  HostAndPort(this.scheme, this.host, this.port, {bool? ipv6}) : _ipv6 = ipv6;

  factory HostAndPort.host(String host, int port, {String? scheme}) {
    return HostAndPort(scheme ?? (port == 443 ? httpsScheme : httpScheme), host, port);
  }

  /// 是否是url
  static bool startsWithScheme(String url) {
    return schemes.any((scheme) => url.startsWith(scheme));
  }

  bool isSsl() {
    return httpsScheme.startsWith(scheme);
  }

  /// 根据url构建
  static HostAndPort of(String url, {bool? ssl}) {
    String domain = url;
    String? scheme;
    //域名格式 直接解析
    if (startsWithScheme(url)) {
      try {
        Uri uri = Uri.parse(url);
        return HostAndPort('${uri.scheme}://', uri.host, uri.port);
      } catch (e) {
        //httpScheme
        scheme = schemes.firstWhere((element) => url.startsWith(element), orElse: () => httpScheme);
        domain = url.substring(scheme.length).split("/")[0];
      }

      //说明支持ipv6
      if (domain.startsWith('[') && domain.endsWith(']')) {
        return HostAndPort(scheme, domain, scheme == httpScheme ? 80 : 443, ipv6: true);
      }
    }

    //ip格式 host:port
    var indexOf = domain.lastIndexOf(':');
    String host = domain.substring(0, indexOf == -1 ? domain.length : indexOf);
    String? port = indexOf == -1 ? null : domain.substring(indexOf + 1, domain.length);
    bool? ipv6 = host.startsWith('[') && host.endsWith(']') ? true : null;

    if (port != null) {
      bool isSsl = port == "443" || ssl == true;
      scheme ??= isSsl ? httpsScheme : httpScheme;
      return HostAndPort(scheme, host, int.parse(port), ipv6: ipv6);
    }
    scheme ??= (ssl == true ? httpsScheme : httpScheme);
    return HostAndPort(scheme, host, scheme == httpScheme ? 80 : 443, ipv6: ipv6);
  }

  String get domain {
    String host = this.host;
    if (isIPv6 && !host.startsWith('[') && !host.endsWith(']')) {
      host = '[$host]';
    }
    return '$scheme$host${(port == 80 || port == 443) ? "" : ":$port"}';
  }

  HostAndPort copyWith({String? scheme, String? host, int? port}) {
    return HostAndPort(scheme ?? this.scheme, host ?? this.host, port ?? this.port);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HostAndPort &&
          runtimeType == other.runtimeType &&
          scheme == other.scheme &&
          host == other.host &&
          port == other.port;

  @override
  int get hashCode => scheme.hashCode ^ host.hashCode ^ port.hashCode;

  @override
  String toString() {
    return domain;
  }
}

/// 代理信息
class ProxyInfo {
  bool enabled = false;

  //是否展示抓包
  bool capturePacket = true;
  String host = '127.0.0.1';
  int? port;

  //authorization
  String? username;
  String? password;

  ProxyInfo();

  ProxyInfo.of(this.host, this.port) : enabled = true;

  bool get isAuthenticated => username?.isNotEmpty == true;

  ProxyInfo.fromJson(Map<String, dynamic> json) {
    enabled = json['enabled'] == true;
    capturePacket = json['capturePacket'] ?? true;
    host = json['host'];
    port = json['port'];
    username = json['username'];
    password = json['password'];
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'capturePacket': capturePacket,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
    };
  }

  @override
  String toString() {
    return 'ProxyInfo{enabled: $enabled, capturePacket: $capturePacket, host: $host, port: $port, username: $username, password: $password}';
  }
}
