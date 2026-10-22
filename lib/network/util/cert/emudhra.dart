import 'dart:typed_data';

import 'package:pointycastle/pointycastle.dart';

import '../crypto.dart';
import 'cert_data.dart';
import 'x509.dart';

/// 已泄露的 eMudhra 中间 CA 链路, 参考 mitmproxy `--emudhra` 选项实现:
/// https://github.com/mitmproxy/mitmproxy/pull/8500
///
/// 包含 EM OV TLS CA - G3C 中间证书及其私钥(私钥标量过弱导致被伪造),
/// 以及由 emSign ECC Root CA - G3 交叉签发的 emSign Root TLS CA - G3, 详见
/// https://emudhra.we-have-a-problem.com/
///
/// 开启后 MITM 叶子证书使用该中间 CA 私钥签发, 并将中间证书与交叉签名根证书
/// 一并下发给客户端, 信任 eMudhra/emSign 根证书的系统无需安装自定义 CA 即可信任拦截证书。
class EmudhraChain {
  /// 已泄露的 EM OV TLS CA - G3C 私钥 (PKCS#8, EC P-384)
  static const String privateKeyPem = '''-----BEGIN PRIVATE KEY-----
MIG2AgEAMBAGByqGSM49AgEGBSuBBAAiBIGeMIGbAgEBBDAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAShZANiAAQTglHNUqyS
mMHIqtl3Mh3rl+cJvQtMoKylXcitUdz8nRWJoVl+OlEg4e/WMcY+GDXKyuKYaaYu
FjHoooGBq1ZhbcRdkYq8CfOrDmPPeSqk3O1zh743u6VpVJ8cArJw7Wc=
-----END PRIVATE KEY-----''';

  /// EM OV TLS CA - G3C 中间证书, 由 emSign Root TLS CA - G3 签发
  static const String intermediateCertPem = '''-----BEGIN CERTIFICATE-----
MIIDaDCCAu6gAwIBAgIPKWkmwiejoVJjkrGUgqUEMAoGCCqGSM49BAMDMFYxCzAJ
BgNVBAYTAklOMSUwIwYDVQQKDBxlTXVkaHJhIFRlY2hub2xvZ2llcyBMaW1pdGVk
MSAwHgYDVQQDDBdlbVNpZ24gUm9vdCBUTFMgQ0EgLSBHMzAeFw0yNTA0MzAxNTM3
NDFaFw00MDA0MjgxODMwMDBaMEAxCzAJBgNVBAYTAlVTMRQwEgYDVQQKDAtlTXVk
aHJhIEluYzEbMBkGA1UEAwwSRU0gT1YgVExTIENBIC0gRzNDMHYwEAYHKoZIzj0C
AQYFK4EEACIDYgAEE4JRzVKskpjByKrZdzId65fnCb0LTKCspV3IrVHc/J0ViaFZ
fjpRIOHv1jHGPhg1ysrimGmmLhYx6KKBgatWYW3EXZGKvAnzqw5jz3kqpNztc4e+
N7ulaVSfHAKycO1no4IBljCCAZIwHwYDVR0jBBgwFoAU4TqrIXzx401UrtRyt/2L
WUIgkFQwHQYDVR0OBBYEFDTq6gzryQra+dDF4u2beMmHnhtsMB0GA1UdJQQWMBQG
CCsGAQUFBwMBBggrBgEFBQcDAjBdBgNVHSAEVjBUMDkGCysGAQQBg44hAQABMCow
KAYIKwYBBQUHAgEWHGh0dHA6Ly9yZXBvc2l0b3J5LmVtc2lnbi5jb20wDQYLKwYB
BAGDjiEBAm4wCAYGZ4EMAQICMHUGCCsGAQUFBwEBBGkwZzAkBggrBgEFBQcwAYYY
aHR0cDovL29jc3AtYy5lbXNpZ24uY29tMD8GCCsGAQUFBzAChjNodHRwOi8vcmVw
b3NpdG9yeS5lbXNpZ24uY29tL2NlcnRzL0VNT1ZUTFNDQUczQy5wN2MwNwYDVR0f
BDAwLjAsoCqgKIYmaHR0cDovL2NybC5lbXNpZ24uY29tLz9yb290dGxzY2FnMy5j
cmwwDgYDVR0PAQH/BAQDAgEGMBIGA1UdEwEB/wQIMAYBAf8CAQAwCgYIKoZIzj0E
AwMDaAAwZQIxAMSZt2xsPeumRdeSMSQ3CbzIZeQ/q7GDCWfeE1Pq+mhgA6gRM44c
NVF3xJ+wsxJk+wIwFJbaDMokD8Ei6eNOiA8yUMYvfzQyngmrhZQMdPCK1SewrR79
4rSb9vGqxZzelQth
-----END CERTIFICATE-----''';

  /// emSign Root TLS CA - G3, 由 emSign ECC Root CA - G3 交叉签发
  static const String rootCertPem = '''-----BEGIN CERTIFICATE-----
MIIDdDCCAvmgAwIBAgIQAJYaPvsTWVdu0EAFtGhKWzAKBggqhkjOPQQDAzBrMQsw
CQYDVQQGEwJJTjETMBEGA1UECxMKZW1TaWduIFBLSTElMCMGA1UEChMcZU11ZGhy
YSBUZWNobm9sb2dpZXMgTGltaXRlZDEgMB4GA1UEAxMXZW1TaWduIEVDQyBSb290
IENBIC0gRzMwHhcNMjQwNzExMTU0MzM2WhcNMzkwNzA5MTgzMDAwWjBWMQswCQYD
VQQGEwJJTjElMCMGA1UECgwcZU11ZGhyYSBUZWNobm9sb2dpZXMgTGltaXRlZDEg
MB4GA1UEAwwXZW1TaWduIFJvb3QgVExTIENBIC0gRzMwdjAQBgcqhkjOPQIBBgUr
gQQAIgNiAARfD9w/q1cWxL6D9bMGH6CQ4u+gAV6GN9s+PwQx9Bl4hC+0iU8QOk8m
WO/RwXQy10DCSxT8vSIJClHKp+Ao4qJKdYeV0SwZ7LMQziyLfxIUOY6Grja/sQFw
LKYf8EdDXAyjggF1MIIBcTAfBgNVHSMEGDAWgBR8XQKEE9TMipuBzhccLikenEhj
QjAdBgNVHQ4EFgQU4TqrIXzx401UrtRyt/2LWUIgkFQwHQYDVR0lBBYwFAYIKwYB
BQUHAwEGCCsGAQUFBwMCMD0GA1UdIAQ2MDQwMgYEVR0gADAqMCgGCCsGAQUFBwIB
FhxodHRwOi8vcmVwb3NpdG9yeS5lbXNpZ24uY29tMHgGCCsGAQUFBwEBBGwwajAi
BggrBgEFBQcwAYYWaHR0cDovL29jc3AuZW1zaWduLmNvbTBEBggrBgEFBQcwAoY4
aHR0cDovL3JlcG9zaXRvcnkuZW1zaWduLmNvbS9jZXJ0cy9lbVNpZ25FQ0NSb290
Q0FHMy5jcnQwMwYDVR0fBCwwKjAooCagJIYiaHR0cDovL2NybC5lbXNpZ24uY29t
P1Jvb3RDQUczLmNybDAOBgNVHQ8BAf8EBAMCAQYwEgYDVR0TAQH/BAgwBgEB/wIB
ATAKBggqhkjOPQQDAwNpADBmAjEAt9CIpRGp46QHQYDUBnLKw+vvK0/h9vmilEAg
TroUl/anH4x2rXHqiCtBTBfgKDegAjEA8WpG1LTZdAIL0FSYqxXeREaeTSxEofM0
1jJH3jGvCXC79LU9UPJ2o3TU+UIj2gMV
-----END CERTIFICATE-----''';

  /// 叶子证书签名算法: ecdsa-with-SHA384, 与中间 CA 证书自身的签名算法一致
  static const String signatureAlgorithmOid = '1.2.840.10045.4.3.3';

  /// 已泄露的中间 CA 私钥
  static late final ECPrivateKey privateKey = _parsePrivateKey();

  /// 中间 CA 证书
  static late final X509CertificateData intermediateCert = X509Utils.x509CertificateFromPem(intermediateCertPem);

  /// 中间 CA subject DN 原始 ASN.1 字节, 签发叶子证书时作为 issuer, 保证二进制精确匹配
  static late final Uint8List issuerDnBytes = X509Utils.subjectDnBytesFromPem(intermediateCertPem);

  /// 追加在叶子证书之后的证书链 (中间证书 + 交叉签名根证书)
  static String get chainPem => '$intermediateCertPem\n$rootCertPem\n';

  /// 叶子证书 + 完整证书链的 PEM, 用于下发给客户端
  static String fullChain(String leafPem) => '$leafPem\n$chainPem';

  /// 解析 PKCS#8 PEM 中的 EC 私钥 (prime384r1)
  static ECPrivateKey _parsePrivateKey() {
    var bytes = CryptoUtils.getBytesFromPEMString(privateKeyPem);
    var seq = ASN1Parser(bytes).nextObject() as ASN1Sequence;

    // PrivateKeyInfo: [0]=version [1]=algorithm [2]=封装的 SEC1 ECPrivateKey
    var ecPrivateKeyOctet = seq.elements!.elementAt(2) as ASN1OctetString;
    var ecPrivateKey = ASN1Parser(ecPrivateKeyOctet.octets!).nextObject() as ASN1Sequence;

    // SEC1 ECPrivateKey: [0]=version [1]=私钥标量 OCTET STRING
    var keyOctets = (ecPrivateKey.elements!.elementAt(1) as ASN1OctetString).octets!;
    var d = BigInt.zero;
    for (var b in keyOctets) {
      d = (d << 8) | BigInt.from(b);
    }
    return ECPrivateKey(d, ECDomainParameters('secp384r1'));
  }
}
