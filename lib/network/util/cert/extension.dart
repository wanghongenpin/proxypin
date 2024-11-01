import 'package:pointycastle/pointycastle.dart';

/// an object for the elements in the X.509 V3 extension block.
class Extension {
  /// Key Usage
  static final ASN1ObjectIdentifier keyUsage = ASN1ObjectIdentifier.fromIdentifierString("2.5.29.15");

  /// Subject Alternative Name
  static final ASN1ObjectIdentifier subjectAlternativeName = ASN1ObjectIdentifier.fromIdentifierString("2.5.29.17");

  /// Basic Constraints
  static final ASN1ObjectIdentifier basicConstraints = ASN1ObjectIdentifier.fromIdentifierString("2.5.29.19");

  /// Extended Key Usage
  static final ASN1ObjectIdentifier extendedKeyUsage = ASN1ObjectIdentifier.fromIdentifierString("2.5.29.37");

  final ASN1ObjectIdentifier extnId;
  final bool critical;

  final ASN1OctetString value;

  Extension(this.extnId, this.critical, this.value);
}

enum ExtendedKeyUsage {
  SERVER_AUTH,
  CLIENT_AUTH,
  CODE_SIGNING,
  EMAIL_PROTECTION,
  TIME_STAMPING,
  OCSP_SIGNING,
  BIMI
}