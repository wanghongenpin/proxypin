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
  static const String httpScheme = "http://";
  static const String httpsScheme = "https://";
  static const String wsScheme = "ws://";
  static const String wssScheme = "wss://";

  static const schemes = [httpsScheme, httpScheme, wssScheme, wsScheme];

  String scheme;
  String host;
  final int port;

  HostAndPort(this.scheme, this.host, this.port);

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
        return HostAndPort(scheme, domain, scheme == httpScheme ? 80 : 443);
      }
    }
    //ip格式 host:port
    List<String> hostAndPort = domain.split(":");
    if (hostAndPort.length == 2) {
      bool isSsl = ssl ?? hostAndPort[1] == "443";
      scheme ??= isSsl ? httpsScheme : httpScheme;
      return HostAndPort(scheme, hostAndPort[0], int.parse(hostAndPort[1]));
    }
    scheme ??= (ssl == true ? httpsScheme : httpScheme);
    return HostAndPort(scheme, hostAndPort[0], scheme == httpScheme ? 80 : 443);
  }

  String get domain {
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
