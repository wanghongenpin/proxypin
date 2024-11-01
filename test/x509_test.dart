import 'dart:io';

import 'package:proxypin/network/util/cert/x509.dart';

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
  var subject = caRoot.subject;
  var d = X509Utils.getSubjectHashName(subject);

  //16进制
  print(d);
  // var certPath = 'assets/certs/ca.crt';
  //生成 公钥和私钥
  // var caRoot = X509Utils.x509CertificateFromPem(caPem);
  // print(caRoot.tbsCertificate.);
  // caRoot.subject = X509Utils.getSubject(caRoot.subject);
}

//获取证书 subject hash

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
