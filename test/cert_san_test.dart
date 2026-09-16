import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:proxypin/network/util/cert/x509.dart';
import 'package:proxypin/network/util/crypto.dart';

void main() {
  Future<String> generateCert(List<String> sans) async {
    var caPem = await File('assets/certs/ca.crt').readAsString();
    var caRoot = X509Utils.x509CertificateFromPem(caPem);
    var keyPair = CryptoUtils.generateRSAKeyPair();
    return X509Utils.generateSelfSignedCertificate(
      caRoot,
      keyPair.publicKey as RSAPublicKey,
      keyPair.privateKey as RSAPrivateKey,
      365,
      sans: sans,
      serialNumber: '1',
    );
  }

  test('IP address SAN is encoded as iPAddress, domain as dNSName', () async {
    var pem = await generateCert(['example.com', '120.26.213.201']);

    var cert = X509Utils.x509CertificateFromPem(pem);
    expect(cert.subjectAlternativNames, ['example.com', '120.26.213.201']);

    //dNSName(0x82=130), iPAddress(0x87=135)
    expect(_sanTags(pem), [130, 135]);
  });

  test('IPv6 SAN with brackets is encoded as iPAddress', () async {
    var pem = await generateCert(['[2408:8726:a000:f0:70::21]']);

    var cert = X509Utils.x509CertificateFromPem(pem);
    expect(cert.subjectAlternativNames, ['2408:8726:a000:00f0:0070:0000:0000:0021']);
    expect(_sanTags(pem), [135]);
  });

  test('remote IP SAN round-trips back as iPAddress', () async {
    var pem = await generateCert(['10.0.0.1']);
    var cert = X509Utils.x509CertificateFromPem(pem);
    var rePem = await generateCert(cert.subjectAlternativNames!);

    expect(_sanTags(rePem), [135]);
    expect(X509Utils.x509CertificateFromPem(rePem).subjectAlternativNames, ['10.0.0.1']);
  });
}

/// 提取证书 SAN 扩展中各条目的 ASN.1 tag
List<int> _sanTags(String pem) {
  var body = pem
      .replaceAll(X509Utils.BEGIN_CERT, '')
      .replaceAll(X509Utils.END_CERT, '')
      .replaceAll('\r\n', '')
      .replaceAll('\n', '');
  var parser = ASN1Parser(base64.decode(body));
  var certSeq = parser.nextObject() as ASN1Sequence;
  var tbs = certSeq.elements!.elementAt(0) as ASN1Sequence;
  var extObj = tbs.elements!.last;
  var extParser = ASN1Parser(extObj.valueBytes!);
  var extSeq = extParser.nextObject() as ASN1Sequence;
  for (var e in extSeq.elements!) {
    var seq = e as ASN1Sequence;
    var oid = seq.elements!.elementAt(0) as ASN1ObjectIdentifier;
    if (oid.objectIdentifierAsString == '2.5.29.17') {
      var octet = seq.elements!.elementAt(seq.elements!.length - 1) as ASN1OctetString;
      var sanParser = ASN1Parser(octet.valueBytes);
      var sanSeq = sanParser.nextObject() as ASN1Sequence;
      return sanSeq.elements!.map((san) => san.tag!).toList();
    }
  }
  return [];
}