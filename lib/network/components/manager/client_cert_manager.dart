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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:proxypin/network/util/cert/cert_data.dart';
import 'package:proxypin/network/util/cert/pkcs12.dart';
import 'package:proxypin/network/util/cert/x509.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/random.dart';
import 'package:proxypin/network/util/url_pattern.dart';
import 'package:proxypin/storage/path.dart';

/// 客户端证书(mTLS)管理器
///
/// 当目标服务需要双向认证时, 代理作为 TLS 客户端需要向上游出示客户端证书。
/// 用户导入 p12/pfx 证书后, 按域名匹配, 在建立上游 TLS 连接时加载对应证书。
///
/// @author wanghongen
class ClientCertManager {
  static const String _fileName = 'client_certificates.json';
  static const String _dirName = 'client_certificates';

  static ClientCertManager? _instance;

  bool enabled = true;
  final List<ClientCertItem> list = [];

  ClientCertManager._();

  /// 单例
  static Future<ClientCertManager> get instance async {
    if (_instance == null) {
      final mgr = ClientCertManager._();
      await mgr._load();
      _instance = mgr;
    }
    return _instance!;
  }

  /// 已加载完成的单例; 未加载时返回 null
  static ClientCertManager? get instanceOrNull => _instance;

  /// 主动预热, 避免首个请求命中时才 IO
  static Future<void> preload() async {
    await instance;
  }

  /// 根据域名查找客户端证书对应的 [SecurityContext], 未匹配返回 null
  static Future<SecurityContext?> securityContextForHost(String? host) async {
    final manager = instanceOrNull;
    if (manager == null) return null;
    return manager.resolveContext(host);
  }

  static File? _configFile;

  static Future<File> _getConfigFile() async {
    if (_configFile != null) return _configFile!;
    final path = await Paths.homePath();
    var file = File('$path${Platform.pathSeparator}$_fileName');
    if (!await file.exists()) {
      await file.create();
    }
    _configFile = file;
    return file;
  }

  static Future<Directory> _getDir() async {
    final path = await Paths.homePath();
    var dir = Directory('$path${Platform.pathSeparator}$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _load() async {
    try {
      final file = await _getConfigFile();
      final content = await file.readAsString();
      if (content.isEmpty) return;

      final config = jsonDecode(content);
      enabled = config['enabled'] != false;
      list.clear();
      for (var entry in (config['list'] as List? ?? [])) {
        list.add(ClientCertItem.fromJson(entry as Map<String, dynamic>));
      }
    } catch (e, st) {
      logger.e('load client cert config error', error: e, stackTrace: st);
    }
  }

  Future<void> flushConfig() async {
    final file = await _getConfigFile();
    await file.writeAsString(jsonEncode({
      'enabled': enabled,
      'list': list.map((e) => e.toJson()).toList(),
    }));
  }

  /// 导入 p12/pfx 客户端证书
  Future<ClientCertItem> importPkcs12(Uint8List bytes, String? password,
      {required String host, String? name}) async {
    final pems = Pkcs12.parsePkcs12(bytes, password: password);
    if (pems.length < 2 || !pems[0].contains('PRIVATE KEY')) {
      throw Exception('Invalid pkcs12 file: no private key');
    }

    final keyPem = pems[0];
    final certPem = pems.sublist(1).join('\n');

    // 解析叶子证书, 记录 CN 与有效期用于列表展示
    String? certName;
    int? notAfter;
    try {
      final cert = X509Utils.x509CertificateFromPem(pems[1]);
      certName = cert.subject['2.5.4.3'];
      notAfter = cert.validity.notAfter.millisecondsSinceEpoch;
    } catch (e) {
      logger.w('parse client cert info error', error: e);
    }

    final item = ClientCertItem(host: host, name: name ?? certName, certName: certName, notAfter: notAfter);
    await (await item.certFile()).writeAsString(certPem);
    await (await item.keyFile()).writeAsString(keyPem);

    list.add(item);
    await flushConfig();
    return item;
  }

  Future<void> remove(ClientCertItem item) async {
    list.remove(item);
    try {
      await (await item.certFile()).delete();
    } catch (_) {}
    try {
      await (await item.keyFile()).delete();
    } catch (_) {}
    await flushConfig();
  }

  /// 根据域名查找客户端证书对应的 [SecurityContext], 未匹配返回 null
  Future<SecurityContext?> resolveContext(String? host) async {
    if (!enabled || host == null || host.isEmpty) return null;
    for (var item in list) {
      if (item.enabled && item.match(host)) {
        return await item.securityContext();
      }
    }
    return null;
  }
}

class ClientCertItem {
  bool enabled = true;
  String? name;
  String host;
  final String id;

  /// 证书 subject CN
  String? certName;

  /// 证书过期时间(毫秒时间戳)
  int? notAfter;

  RegExp? _hostReg;
  SecurityContext? _context;

  ClientCertItem({String? id, required this.host, this.name, this.enabled = true, this.certName, this.notAfter})
      : id = id ?? generateId();

  static String generateId() {
    return DateTime.now().millisecondsSinceEpoch.toRadixString(36) + RandomUtil.randomString(4);
  }

  Future<File> certFile() async {
    final dir = await ClientCertManager._getDir();
    return File('${dir.path}${Platform.pathSeparator}$id.crt');
  }

  Future<File> keyFile() async {
    final dir = await ClientCertManager._getDir();
    return File('${dir.path}${Platform.pathSeparator}$id.key');
  }

  bool match(String domain) {
    if (host != _hostReg?.pattern) _hostReg = null;
    _hostReg ??= UrlPattern.toHostRegExp(host);
    return _hostReg!.hasMatch(domain);
  }

  /// 证书是否已过期
  bool get isExpired => notAfter != null && DateTime.now().millisecondsSinceEpoch > notAfter!;

  /// 读取叶子证书详情, 失败返回 null
  Future<X509CertificateData?> certDetails() async {
    try {
      final cert = await certFile();
      if (!await cert.exists()) return null;
      final pem = await cert.readAsString();
      final end = pem.indexOf(X509Utils.END_CERT);
      if (end < 0) return null;
      return X509Utils.x509CertificateFromPem(pem.substring(0, end + X509Utils.END_CERT.length));
    } catch (e, st) {
      logger.e('parse client cert details error', error: e, stackTrace: st);
      return null;
    }
  }

  /// 构建并缓存客户端证书的 [SecurityContext]
  Future<SecurityContext?> securityContext() async {
    if (_context != null) return _context;

    try {
      final cert = await certFile();
      final key = await keyFile();
      if (!await cert.exists() || !await key.exists()) return null;

      final context = SecurityContext(withTrustedRoots: false)
        ..usePrivateKeyBytes((await key.readAsString()).codeUnits)
        ..useCertificateChainBytes((await cert.readAsString()).codeUnits);

      _context = context;
      return context;
    } catch (e, st) {
      logger.e('load client cert error', error: e, stackTrace: st);
      return null;
    }
  }

  factory ClientCertItem.fromJson(Map<String, dynamic> json) {
    return ClientCertItem(
      id: json['id'],
      host: json['host'] ?? '',
      name: json['name'],
      enabled: json['enabled'] != false,
      certName: json['certName'],
      notAfter: json['notAfter'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'host': host,
      'name': name,
      'enabled': enabled,
      'certName': certName,
      'notAfter': notAfter,
    };
  }
}
