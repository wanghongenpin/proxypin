import 'dart:typed_data';

import 'package:pointycastle/pointycastle.dart';

enum KeyUsage {
  /// 0
  DIGITAL_SIGNATURE,

  /// 1 (Also called contentCommitment now)
  NON_REPUDIATION,

  /// 2
  KEY_ENCIPHERMENT,

  /// 3
  DATA_ENCIPHERMENT,

  /// 4
  KEY_AGREEMENT,

  /// 5
  KEY_CERT_SIGN,

  /// 6
  CRL_SIGN,

  /// 7
  ENCIPHER_ONLY,

  /// 8
  DECIPHER_ONLY
}

class ExtensionKeyUsage {
  static const int digitalSignature = (1 << 7);
  static const int nonRepudiation = (1 << 6);
  static const int keyEncipherment = (1 << 5);
  static const int dataEncipherment = (1 << 4);
  static const int keyAgreement = (1 << 3);
  static const int keyCertSign = (1 << 2);
  static const int cRLSign = (1 << 1);
  static const int encipherOnly = (1 << 0);
  static const int decipherOnly = (1 << 15);

  final ASN1BitString bitString;
  final bool critical;

  ExtensionKeyUsage(int usage, {this.critical = true}) : bitString = ASN1BitString.fromBytes(keyUsageBytes(usage));

  static Uint8List keyUsageBytes(int valueBytes) {
    var bytes = [valueBytes];
    if (valueBytes > 0xFF) {
      final int firstValueByte = (valueBytes & int.parse("ff00", radix: 16)) >> 8;
      final int secondValueByte = (valueBytes & int.parse("00ff", radix: 16));
      bytes = [firstValueByte, secondValueByte];
    }

    return Uint8List.fromList(<int>[
      // BitString identifier
      3,
      // Length
      bytes.length + 1,
      // Unused bytes at the end
      1,
      ...bytes
    ]);
  }
}
