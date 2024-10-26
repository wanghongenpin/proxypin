import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:proxypin/network/util/cert/basic_constraints.dart';
import 'package:proxypin/network/util/cert/x509.dart';
import 'package:pointycastle/pointycastle.dart';

void main() async {
  // encoding();
  // Add ext key usage 2.5.29.37
// // Add key usage  2.5.29.15
//   var keyUsage = [KeyUsage.KEY_CERT_SIGN, KeyUsage.CRL_SIGN];
//
//   var encode = keyUsageSequence(keyUsage)?.encode();
//   print(Int8List.view(encode!.buffer));

  var caPem = await File('assets/certs/ca.crt').readAsString();

  // var caPem = File('/Users/wanghongen/Downloads/proxyman.crt').readAsStringSync();
  //生成 公钥和私钥
  var caRoot = X509Utils.x509CertificateFromPem(caPem);
  var subject = caRoot.tbsCertificate!.subject;
  var d = X509Generate.getSubjectHashName(subject);

  //16进制
  print(d);
  // var certPath = 'assets/certs/ca.crt';
  //生成 公钥和私钥
  // var caRoot = X509Utils.x509CertificateFromPem(caPem);
  // print(caRoot.tbsCertificate.);
  // caRoot.subject = X509Utils.getSubject(caRoot.subject);
}

//获取证书 subject hash

void encoding() {
  var basicConstraints = BasicConstraints(isCA: true);

  var extensionTopSequence = ASN1Sequence();

  // Add basic constraints 2.5.29.19
  var basicConstraintsValue = ASN1Sequence();
  basicConstraintsValue.add(ASN1Boolean(basicConstraints.isCA));
  if (basicConstraints.pathLenConstraint != null) {
    basicConstraintsValue.add(ASN1Integer(BigInt.from(basicConstraints.pathLenConstraint!)));
  }

  var octetString = ASN1OctetString(octets: basicConstraintsValue.encode());
  var basicConstraintsSequence = ASN1Sequence();
  basicConstraintsSequence.add(ASN1ObjectIdentifier.fromIdentifierString('2.5.29.19'));
  if (basicConstraints.critical) {
    basicConstraintsSequence.add(ASN1Boolean(true));
  }
  basicConstraintsSequence.add(octetString);
  extensionTopSequence.add(basicConstraintsSequence);

  // Add key usage  2.5.29.15
  var keyUsage = [KeyUsage.KEY_CERT_SIGN, KeyUsage.CRL_SIGN];
  extensionTopSequence.add(keyUsageSequence(keyUsage)!);

  //2.5.29.17
  var sans = ['ProxyPin'];
  if (IterableUtils.isNotNullOrEmpty(sans)) {
    var sanList = ASN1Sequence();
    for (var s in sans) {
      sanList.add(ASN1PrintableString(stringValue: s, tag: 0x82));
    }
    var octetString = ASN1OctetString(octets: sanList.encode());

    var sanSequence = ASN1Sequence();
    sanSequence.add(ASN1ObjectIdentifier.fromIdentifierString('2.5.29.17'));
    sanSequence.add(octetString);
    extensionTopSequence.add(sanSequence);
  }

  // Add ext key usage 2.5.29.37
  var extKeyUsage = [ExtendedKeyUsage.SERVER_AUTH];
  var extKeyUsageSequence = extendedKeyUsageEncodings(extKeyUsage);
  if (extKeyUsageSequence != null) {
    extensionTopSequence.add(extKeyUsageSequence);
  }

  var extObj = ASN1Object(tag: 0xA3);
  extObj.valueBytes = extensionTopSequence.encode();

  print(Int8List.view(extensionTopSequence.encode().buffer));
  // print(Int8List.view(extObj.encode().buffer));
}

void _basicConstraints() {
  var basicConstraints = BasicConstraints(isCA: true);
  var basicConstraintsValue = ASN1Sequence();

  basicConstraintsValue.add(ASN1Boolean(basicConstraints.isCA));
  if (basicConstraints.pathLenConstraint != null) {
    basicConstraintsValue.add(ASN1Integer(BigInt.from(basicConstraints.pathLenConstraint!)));
  }

  print(Int8List.view(basicConstraintsValue.encode().buffer));

  var octetString = ASN1OctetString(octets: basicConstraintsValue.encode());
  print(Int8List.view(octetString.encode().buffer));

  var basicConstraintsSequence = ASN1Sequence();
  basicConstraintsSequence.add(ASN1ObjectIdentifier.fromIdentifierString('2.5.29.19'));
  basicConstraintsSequence.add(ASN1Boolean(true));
  basicConstraintsSequence.add(octetString);

  print(Int8List.view(basicConstraintsSequence.encode().buffer));
  //[48, 15, 6, 3, 85, 29, 19, 1, 1, -1, 4, 5, 48, 3, 1, 1, -1]
}

// class KeyUsage {
//   static const int keyCertSign = (1 << 2);
//   static const int cRLSign = (1 << 1);
//
//   final ASN1BitString bitString;
//
//   KeyUsage(int usage) : bitString = ASN1BitString(stringValues: getBytes(usage))..unusedbits = getPadBits(usage);
//
//   static Uint8List getBytes(int bitString) {
//     if (bitString == 0) {
//       return Uint8List(0);
//     }
//
//     int bytes = 4;
//     for (int i = 3; i >= 1; i--) {
//       if ((bitString & (0xFF << (i * 8))) != 0) {
//         break;
//       }
//       bytes--;
//     }
//
//     Uint8List result = Uint8List(bytes);
//     for (int i = 0; i < bytes; i++) {
//       result[i] = ((bitString >> (i * 8)) & 0xFF);
//     }
//
//     return result;
//   }
//
//   static int getPadBits(int bitString) {
//     int val = 0;
//     for (int i = 3; i >= 0; i--) {
//       if (i != 0) {
//         if ((bitString >> (i * 8)) != 0) {
//           val = (bitString >> (i * 8)) & 0xFF;
//           break;
//         }
//       } else {
//         if (bitString != 0) {
//           val = bitString & 0xFF;
//           break;
//         }
//       }
//     }
//
//     if (val == 0) {
//       return 0;
//     }
//
//     int bits = 1;
//     while (((val <<= 1) & 0xFF) != 0) {
//       bits++;
//     }
//
//     return 8 - bits;
//   }
// }

ASN1Sequence? keyUsageSequence(List<KeyUsage>? keyUsages) {
  int valueBytes = 0; // the last bit of the 2 bytes is always set
  for (KeyUsage usage in keyUsages!) {
    switch (usage) {
      case KeyUsage.KEY_CERT_SIGN:
        valueBytes |= (1 << 2);
        break;
      case KeyUsage.CRL_SIGN:
        valueBytes |= (1 << 1);
        break;
      // Add other cases as needed
      default:
        throw Error();
    }
  }

  var bytes = [valueBytes];
  if (valueBytes > 0xFF) {
    final int firstValueByte = (valueBytes & int.parse("ff00", radix: 16)) >> 8;
    final int secondValueByte = (valueBytes & int.parse("00ff", radix: 16));
    bytes = [firstValueByte, secondValueByte];
  }

  final Uint8List keyUsageBytes = Uint8List.fromList(<int>[
    // BitString identifier
    3,
    // Length
    bytes.length + 1,
    // Unused bytes at the end
    1,
    ...bytes
  ]);

  print(keyUsageBytes);
  var octetString = ASN1OctetString(octets: ASN1BitString.fromBytes(keyUsageBytes).encode());

  var keyUsageSequence = ASN1Sequence();
  keyUsageSequence.add(ASN1ObjectIdentifier.fromIdentifierString('2.5.29.15'));
  keyUsageSequence.add(ASN1Boolean(true));
  keyUsageSequence.add(octetString);

  return keyUsageSequence;
}

ASN1Sequence? extendedKeyUsageEncodings(List<ExtendedKeyUsage>? extKeyUsage) {
  if (IterableUtils.isNullOrEmpty(extKeyUsage)) {
    return null;
  }
  var extKeyUsageList = ASN1Sequence();
  for (var s in extKeyUsage!) {
    var oi = <int>[];
    switch (s) {
      case ExtendedKeyUsage.SERVER_AUTH:
        oi = [1, 3, 6, 1, 5, 5, 7, 3, 1];
        break;
      case ExtendedKeyUsage.CLIENT_AUTH:
        oi = [1, 3, 6, 1, 5, 5, 7, 3, 2];
        break;
      case ExtendedKeyUsage.CODE_SIGNING:
        oi = [1, 3, 6, 1, 5, 5, 7, 3, 3];
        break;
      case ExtendedKeyUsage.EMAIL_PROTECTION:
        oi = [1, 3, 6, 1, 5, 5, 7, 3, 4];
        break;
      case ExtendedKeyUsage.TIME_STAMPING:
        oi = [1, 3, 6, 1, 5, 5, 7, 3, 8];
        break;
      case ExtendedKeyUsage.OCSP_SIGNING:
        oi = [1, 3, 6, 1, 5, 5, 7, 3, 9];
        break;
      case ExtendedKeyUsage.BIMI:
        oi = [1, 3, 6, 1, 5, 5, 7, 3, 31];
        break;
    }

    extKeyUsageList.add(ASN1ObjectIdentifier(oi));
  }

  var octetString = ASN1OctetString(octets: extKeyUsageList.encode());

  var extKeyUsageSequence = ASN1Sequence();
  extKeyUsageSequence.add(ASN1ObjectIdentifier.fromIdentifierString('2.5.29.37'));
  extKeyUsageSequence.add(octetString);
  return extKeyUsageSequence;
}
