import 'dart:io';
import 'dart:math';

import 'package:basic_utils/basic_utils.dart';
import 'package:proxypin/network/util/cert/basic_constraints.dart';
import 'package:proxypin/network/util/cert/key_usage.dart' as x509;
import 'package:proxypin/network/util/cert/x509.dart';

void main() async {
  var caPem = await File('assets/certs/ca.crt').readAsString();
  //生成 公钥和私钥
  var caRoot = X509Utils.x509CertificateFromPem(caPem);
  var generateRSAKeyPair = CryptoUtils.generateRSAKeyPair();
  var serverPubKey = generateRSAKeyPair.publicKey as RSAPublicKey;
  // var serverPriKey = generateRSAKeyPair.privateKey as RSAPrivateKey;

  print(CryptoUtils.encodeRSAPublicKeyToPem(serverPubKey));
  //保存私钥
  var serverPublicKeyPem = """-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqVXqbCErPZMS+2Eb3MUT
eTNIYZHoCMZk5gFIo3pD70dZimQj2yMBIh9Rq4rO0/Dj9zt52vR1zbxDnmx/5TDC
djDHk/zHYW66VLYCo4n1H4/dddFvJ8Y8syBNpa+seSAR6ljF807gZqINGeNKi8Du
N82XiED2Ix3woE1jMQfP3E16alxHaejFBZ77SUOXJhJDM5SKD2H0bxGw9cVw9K69
NmnZMIM9+U8+TuM9EzvMUuHTY278Ov72c9HpO5OAx2zfyXGlmUGgyUCiYnxeATX5
LceGVEoT2MWhFibWvPBpH315xNXU57dWKWW714tPsvzzNHzKZspz/LQ36fU9goUg
NQIDAQAB
-----END PUBLIC KEY-----
  """;
  print(serverPublicKeyPem);
  var readAsString = await File('assets/certs/server.key').readAsString();
  // var rsaPrivateKeyFromPem = CryptoUtils.rsaPrivateKeyFromPem(serverPriKeyPem);
  // print(rsaPrivateKeyFromPem);
  var crt = generate(
      caRoot, CryptoUtils.rsaPublicKeyFromPem(serverPublicKeyPem), CryptoUtils.rsaPrivateKeyFromPem(readAsString));
  print(crt);

  // await File('assets/certs/server.crt').writeAsString(crt);
  // var readAsString2 = File('assets/certs/server.crt').readAsStringSync();

  //TLS服务器证书必须包含ExtendedKeyUsage（EKU）扩展，该扩展包含id-kp-serverAuth OID。

  // X509Utils.generateSelfSignedCertificate(serverPriKey, caPem, 825,
  //     serialNumber: Random().nextInt(1000000).toString(),
  //     sans: [
  //       'ProxyPin CA (${Platform.localHostname})'
  //     ],
  //     issuer: {
  //       'C': 'CN',
  //       'ST': 'BJ',
  //       'L': 'Beijing',
  //       'O': 'Proxy',
  //       'OU': 'ProxyPin',
  //       'CN': 'ProxyPin CA (${Platform.localHostname})'
  //     },
  //     keyUsage: [
  //       KeyUsage.DIGITAL_SIGNATURE,
  //       KeyUsage.KEY_CERT_SIGN,
  //       KeyUsage.CRL_SIGN
  //     ],
  //     extKeyUsage: [
  //       ExtendedKeyUsage.SERVER_AUTH
  //     ]);

  // var generatePkcs12 = Pkcs12Utils.generatePkcs12(readAsString, [crt], password: '123');
  // await File('/Users/wanghongen/Downloads/server.p12').writeAsBytes(generatePkcs12);
}

/// 生成证书
String generate(X509CertificateData caRoot, RSAPublicKey serverPubKey, RSAPrivateKey caPriKey) {
//根据CA证书subject来动态生成目标服务器证书的issuer和subject
  Map<String, String> x509Subject = {
    'C': 'CN',
    'ST': 'BJ',
    'L': 'Beijing',
    'O': 'Proxy',
    'OU': 'ProxyPin',
  };
  x509Subject['CN'] = 'ProxyPin CA (wanghongen)';

  var csrPem = X509Generate.generateSelfSignedCertificate(caRoot, serverPubKey, caPriKey, 365,
      keyUsage: x509.KeyUsage(x509.KeyUsage.keyCertSign | x509.KeyUsage.cRLSign),
      extKeyUsage: [ExtendedKeyUsage.SERVER_AUTH],
      basicConstraints: BasicConstraints(isCA: true),
      sans: [x509Subject['CN']!],
      serialNumber: Random().nextInt(1000000).toString(),
      subject: x509Subject);
  return csrPem;
}
