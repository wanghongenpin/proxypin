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

import 'dart:async';
import 'dart:core';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:proxypin/network/util/cert/basic_constraints.dart';
import 'package:proxypin/network/util/cert/pkcs12.dart';
import 'package:proxypin/network/util/cert/x509.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/random.dart';
import 'package:proxypin/utils/lang.dart';

import 'cert/cert_data.dart';
import 'cert/extension.dart';
import 'cert/key_usage.dart';
import 'crypto.dart';
import 'file_read.dart';

Future<void> main() async {
  await CertificateManager.getCertificateContext('www.jianshu.com');
  CertificateManager.caCert.tbsCertificateSeqAsString;

  String cer = CertificateManager.get('www.jianshu.com')!;
  print(cer);
}

enum StartState { uninitialized, initializing, initialized }

class CertificateManager {
  /// 证书缓存
  static final Map<String, String> _certificateMap = {};

  /// 服务端密钥
  static AsymmetricKeyPair _serverKeyPair = CryptoUtils.generateRSAKeyPair();

  /// ca证书
  static late X509CertificateData _caCert;

  /// ca私钥
  static late RSAPrivateKey _caPriKey;

  /// 是否初始化
  static StartState _state = StartState.uninitialized;
  static Completer<void> _initializationCompleter = Completer<void>();

  static String? get(String host) {
    return _certificateMap[host];
  }

  static X509CertificateData get caCert => _caCert;

  /// 清除缓存
  static void cleanCache() {
    _certificateMap.clear();
  }

  /// 获取域名自签名证书
  static Future<SecurityContext> getCertificateContext(String host) async {
    var cer = _certificateMap[host];

    if (cer == null) {
      if (_state != StartState.initialized) {
        await initCAConfig();
      }
      cer = generate(_caCert, _serverKeyPair.publicKey as RSAPublicKey, _caPriKey, host);
      _certificateMap[host] = cer;
    }

    var rsaPrivateKey = _serverKeyPair.privateKey as RSAPrivateKey;

    return SecurityContext.defaultContext
      ..useCertificateChainBytes(cer.codeUnits)
      ..allowLegacyUnsafeRenegotiation = true
      ..usePrivateKeyBytes(CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(rsaPrivateKey).codeUnits);
  }

  /// 生成证书
  static String generate(X509CertificateData caRoot, RSAPublicKey serverPubKey, RSAPrivateKey caPriKey, String host) {
    //根据CA证书subject来动态生成目标服务器证书的issuer和subject
    Map<String, String> x509Subject = {
      'C': 'CN',
      'ST': 'BJ',
      'L': 'Beijing',
      'O': 'Proxy',
      'OU': 'ProxyPin',
    };

    x509Subject['CN'] = host;

    var csrPem = X509Utils.generateSelfSignedCertificate(caRoot, serverPubKey, caPriKey, 365,
        sans: [host], serialNumber: Random().nextInt(1000000).toString(), subject: x509Subject);
    return csrPem;
  }

  /// 获取证书主题hash
  static Future<String> systemCertificateName() async {
    if (_state != StartState.initialized) {
      await initCAConfig();
    }

    var subject = caCert.subject;
    return '${X509Utils.getSubjectHashName(subject)}.0';
  }

  //重新生成根证书
  static Future<void> generateNewRootCA() async {
    if (_state != StartState.initialized) {
      await initCAConfig();
    }

    var generateRSAKeyPair = CryptoUtils.generateRSAKeyPair();
    var serverPubKey = generateRSAKeyPair.publicKey as RSAPublicKey;
    var serverPriKey = generateRSAKeyPair.privateKey as RSAPrivateKey;

    //根据CA证书subject来动态生成目标服务器证书的issuer和subject
    Map<String, String> x509Subject = {
      'C': 'CN',
      'ST': 'BJ',
      'L': 'Beijing',
      'O': 'Proxy',
      'OU': 'ProxyPin',
    };
    x509Subject['CN'] = 'ProxyPin CA (${DateTime.now().dateFormat()},${RandomUtil.randomString(6).toUpperCase()})';

    var csrPem = X509Utils.generateSelfSignedCertificate(
      _caCert,
      serverPubKey,
      serverPriKey,
      825,
      sans: [x509Subject['CN']!],
      serialNumber: DateTime.now().millisecondsSinceEpoch.toString(),
      issuer: x509Subject,
      subject: x509Subject,
      keyUsage: ExtensionKeyUsage(ExtensionKeyUsage.keyCertSign),
      extKeyUsage: [ExtendedKeyUsage.SERVER_AUTH],
      basicConstraints: BasicConstraints(isCA: true),
    );

    //重新写入根证书
    var caFile = await certificateFile();
    await caFile.writeAsString(csrPem);

    //私钥
    var serverPriKeyPem = CryptoUtils.encodeRSAPrivateKeyToPem(serverPriKey);
    var keyFile = await privateKeyFile();
    await keyFile.writeAsString(serverPriKeyPem);
    cleanCache();
    _state = StartState.uninitialized;
  }

  ///重置默认根证书
  static Future<void> resetDefaultRootCA() async {
    var caFile = await certificateFile();
    await caFile.delete();

    var keyFile = await privateKeyFile();
    await keyFile.delete();
    cleanCache();
    _state = StartState.uninitialized;
  }

  static Future<void> initCAConfig() async {
    if (_state == StartState.initialized || _state == StartState.initializing) {
      return _initializationCompleter.future;
    }

    var startTime = DateTime.now().millisecondsSinceEpoch;

    _state = StartState.initializing;
    _initializationCompleter = Completer<void>();

    try {
      _serverKeyPair = CryptoUtils.generateRSAKeyPair();

      //从项目目录加入ca根证书
      var caPemFile = await certificateFile();
      _caCert = X509Utils.x509CertificateFromPem(await caPemFile.readAsString());
      //根据CA证书subject来动态生成目标服务器证书的issuer和subject

      //从项目目录加入ca私钥
      var keyFile = await privateKeyFile();
      _caPriKey = CryptoUtils.rsaPrivateKeyFromPem(await keyFile.readAsString());

      _state = StartState.initialized;
      _initializationCompleter.complete();
    } catch (e) {
      logger.e('init ca config error:$e');
      _state = StartState.uninitialized;
      _initializationCompleter.completeError(e);
    }

    logger.d('init ca config end cost:${DateTime.now().millisecondsSinceEpoch - startTime}');

    return _initializationCompleter.future;
  }

  /// 证书文件
  static Future<File> certificateFile() async {
    final String appPath = await getApplicationSupportDirectory().then((value) => value.path);
    var caFile = File("$appPath${Platform.pathSeparator}ca.crt");
    if (!(await caFile.exists())) {
      var body = await FileRead.read('assets/certs/ca.crt');
      await caFile.writeAsBytes(body.buffer.asUint8List());
    }

    return caFile;
  }

  /// 私钥文件
  static Future<File> privateKeyFile() async {
    final String appPath = await getApplicationSupportDirectory().then((value) => value.path);
    var caFile = File("$appPath${Platform.pathSeparator}ca_key.pem");
    if (!(await caFile.exists())) {
      var body = await FileRead.read('assets/certs/ca_key.pem');
      await caFile.writeAsBytes(body.buffer.asUint8List());
    }

    return caFile;
  }

  ///生成 p12文件
  static Future<Uint8List> generatePkcs12(String? password) async {
    var caFile = await CertificateManager.certificateFile();
    var keyFile = await CertificateManager.privateKeyFile();
    return Pkcs12.generatePkcs12(await keyFile.readAsString(), [await caFile.readAsString()], password: password);
  }

  ///import p12文件
  static Future<void> importPkcs12(Uint8List pkcs12, String? password) async {
    var decodePkcs12 = Pkcs12.parsePkcs12(pkcs12, password: password);

    var caFile = await CertificateManager.certificateFile();
    var keyFile = await CertificateManager.privateKeyFile();
    if (decodePkcs12.length != 2) {
      throw Exception('Invalid pkcs12 file');
    }

    await keyFile.writeAsString(decodePkcs12[0]);
    await caFile.writeAsString(decodePkcs12[1]);

    cleanCache();
    _state = StartState.uninitialized;
  }
}
