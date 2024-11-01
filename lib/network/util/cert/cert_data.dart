import 'dart:typed_data';

import 'extension.dart';
import 'key_usage.dart';

class X509CertificateData {
  /// The subject data of the certificate
  Map<String, String?> subject;

  /// The version of the certificate
  int version;

  BigInt serialNumber;

  /// The signatureAlgorithm of the certificate
  String signatureAlgorithm;

  /// The readable name of the signatureAlgorithm of the certificate
  String? signatureAlgorithmReadableName;

  Map<String, String?> issuer;

  /// The validity of the certificate
  @Deprecated('Use tbsCertificate.validity instead')
  X509CertificateValidity validity;

  /// The sha1 thumbprint for the certificate
  String? sha1Thumbprint;

  /// The sha256 thumbprint for the certificate
  String? sha256Thumbprint;

  /// The md5 thumbprint for the certificate
  String? md5Thumbprint;

  /// The public key data from the certificate
  X509CertificatePublicKeyData publicKeyData;

  /// The subject alternative names
  List<String>? subjectAlternativNames;

  /// The plain certificate pem string, that was used to decode.
  String? plain;

  /// The extended key usage extension
  List<ExtendedKeyUsage>? extKeyUsage;

  /// The certificate extensions
  X509CertificateDataExtensions? extensions;

  /// The signature
  String? signature;

  /// The tbsCertificateSeq as base64 string
  String? tbsCertificateSeqAsString;

  X509CertificateData({
    required this.version,
    required this.serialNumber,
    required this.signatureAlgorithm,
    required this.issuer,
    required this.validity,
    required this.subject,
    // required this.tbsCertificate,
    this.signatureAlgorithmReadableName,
    this.sha1Thumbprint,
    this.sha256Thumbprint,
    this.md5Thumbprint,
    required this.publicKeyData,
    required this.subjectAlternativNames,
    this.plain,
    this.extKeyUsage,
    this.extensions,
    this.tbsCertificateSeqAsString,
    required this.signature,
  });
}

class SubjectPublicKeyInfo {
  /// The algorithm of the public key
  String? algorithm;

  /// The readable name of the algorithm
  String? algorithmReadableName;

  /// The parameter of the public key
  String? parameter;

  /// The readable name of the parameter
  String? parameterReadableName;

  /// The key length of the public key
  int? length;

  /// The sha1 thumbprint of the public key
  String? sha1Thumbprint;

  /// The sha256 thumbprint of the public key
  String? sha256Thumbprint;

  /// The bytes representing the public key as String
  String? bytes;

  /// The exponent used on a RSA public key
  int? exponent;

  SubjectPublicKeyInfo({
    this.algorithm,
    this.length,
    this.sha1Thumbprint,
    this.sha256Thumbprint,
    this.bytes,
    this.algorithmReadableName,
    this.parameter,
    this.parameterReadableName,
    this.exponent,
  });
}

class X509CertificateValidity {
  /// The start date
  DateTime notBefore;

  /// The end date
  DateTime notAfter;

  X509CertificateValidity({required this.notBefore, required this.notAfter});
}

//
/// Model that represents the extensions of a x509Certificate
///
class X509CertificateDataExtensions {
  /// The subject alternative names
  List<String>? subjectAlternativNames;

  /// The extended key usage extension
  List<ExtendedKeyUsage>? extKeyUsage;

  /// The key usage extension
  List<KeyUsage>? keyUsage;

  /// The cA field of the basic constraints extension
  bool? cA;

  /// The pathLenConstraint field of the basic constraints extension
  int? pathLenConstraint;

  /// The base64 encoded VMC logo
  VmcData? vmc;

  /// The distribution points for the crl files. Normally a url.
  List<String>? cRLDistributionPoints;

  X509CertificateDataExtensions({
    this.subjectAlternativNames,
    this.extKeyUsage,
    this.keyUsage,
    this.cA,
    this.pathLenConstraint,
    this.vmc,
    this.cRLDistributionPoints,
  });
}

///
/// Model that a public key from a X509Certificate
///
class X509CertificatePublicKeyData {
  /// The algorithm of the public key
  String? algorithm;

  /// The readable name of the algorithm
  String? algorithmReadableName;

  /// The parameter of the public key
  String? parameter;

  /// The readable name of the parameter
  String? parameterReadableName;

  /// The key length of the public key
  int? length;

  /// The sha1 thumbprint of the public key
  String? sha1Thumbprint;

  /// The sha256 thumbprint of the public key
  String? sha256Thumbprint;

  /// The bytes representing the public key as String
  String? bytes;

  Uint8List? plainSha1;

  /// The exponent used on a RSA public key
  int? exponent;

  X509CertificatePublicKeyData({
    this.algorithm,
    this.length,
    this.sha1Thumbprint,
    this.sha256Thumbprint,
    this.bytes,
    this.plainSha1,
    this.algorithmReadableName,
    this.parameter,
    this.parameterReadableName,
    this.exponent,
  });

  static Uint8List? plainSha1FromJson(List<int>? json) {
    if (json == null) {
      return null;
    }
    return Uint8List.fromList(json);
  }

  static List<int>? plainSha1ToJson(Uint8List? object) {
    if (object == null) {
      return null;
    }
    return object.toList();
  }

  X509CertificatePublicKeyData.fromSubjectPublicKeyInfo(
      SubjectPublicKeyInfo info) {
    algorithm = info.algorithm;
    length = info.length;
    sha1Thumbprint = info.sha1Thumbprint;
    sha256Thumbprint = info.sha256Thumbprint;
    bytes = info.bytes;
    algorithmReadableName = info.algorithmReadableName;
    parameter = info.parameter;
    parameterReadableName = info.parameterReadableName;
    exponent = info.exponent;
  }
}

class VmcData {
  /// The base64 encoded logo
  String? base64Logo;

  /// The logo type
  String? type;

  /// The hash
  String? hash;

  /// The readable version of the algorithm of the hash
  String? hashAlgorithmReadable;

  /// The algorithm of the hash
  String? hashAlgorithm;

  VmcData({
    this.base64Logo,
    this.hash,
    this.hashAlgorithm,
    this.hashAlgorithmReadable,
    this.type,
  });

  String getFullSvgData() {
    return 'data:$type;base64,$base64Logo';
  }
}
