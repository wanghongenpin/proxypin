// ignore_for_file: constant_identifier_names, depend_on_referenced_packages

import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:proxypin/network/util/cert/extension.dart';
import 'package:proxypin/network/util/cert/key_usage.dart' as x509;
import 'package:pointycastle/asn1/unsupported_object_identifier_exception.dart';
import 'package:pointycastle/pointycastle.dart';

import 'basic_constraints.dart';

/// @author wanghongen
/// 2023/7/26
class X509Generate {
  static const String BEGIN_CERT = '-----BEGIN CERTIFICATE-----';
  static const String END_CERT = '-----END CERTIFICATE-----';

  //所在国家
  static const String COUNTRY_NAME = "2.5.4.6";
  static const String SERIAL_NUMBER = "2.5.4.5";
  static const String DN_QUALIFIER = "2.5.4.46";

  ///android 系统证书名称
  static String getSubjectHashName(Map<String, String?> subject) {
    // Add Issuer
    var issuerSeq = ASN1Sequence();
    for (var k in subject.keys) {
      var s = X509Generate._identifier(k, subject[k]!);
      issuerSeq.add(s);
    }
    var derEncoded = issuerSeq.encode();
    // Convert the hash to a long value
    var hashBytes = md5.convert(derEncoded).bytes;
    int hash = (hashBytes[0] & 0xff) |
        ((hashBytes[1] & 0xff) << 8) |
        ((hashBytes[2] & 0xff) << 16) |
        ((hashBytes[3] & 0xff) << 24);
    String hexString = hash.toRadixString(16).padLeft(8, '0');
    return hexString;
  }

  ///
  /// Generates a self signed certificate
  ///
  /// * [privateKey] = The private key used for signing
  /// * [csr] = The CSR containing the DN and public key
  /// * [days] = The validity in days
  /// * [sans] = Subject alternative names to place within the certificate
  /// * [extKeyUsage] = The extended key usage definition
  /// * [serialNumber] = The serialnumber. If not set the default will be 1.
  /// * [issuer] = The issuer. If null, the issuer will be the subject of the given csr.
  ///
  static String generateSelfSignedCertificate(
    X509CertificateData caRoot,
    RSAPublicKey publicKey,
    RSAPrivateKey privateKey,
    int days, {
    List<String>? sans,
    String serialNumber = '1',
    Map<String, String>? issuer,
    Map<String, String>? subject,
    x509.KeyUsage? keyUsage,
    List<ExtendedKeyUsage>? extKeyUsage,
    BasicConstraints? basicConstraints,
  }) {
    var data = ASN1Sequence();

    // Add version
    var version = ASN1Object(tag: 0xA0);
    version.valueBytes = ASN1Integer.fromtInt(2).encode();
    data.add(version);

    // Add serial number
    data.add(ASN1Integer(BigInt.parse(serialNumber)));

    // Add protocol
    var blockProtocol = ASN1Sequence();
    blockProtocol.add(ASN1ObjectIdentifier.fromIdentifierString(caRoot.signatureAlgorithm));
    blockProtocol.add(ASN1Null());
    data.add(blockProtocol);

    issuer ??= Map.from(caRoot.tbsCertificate!.subject);

    // Add Issuer
    var issuerSeq = ASN1Sequence();
    for (var k in issuer.keys) {
      var s = _identifier(k, issuer[k]!);
      issuerSeq.add(s);
    }
    data.add(issuerSeq);

    // Add Validity
    var validitySeq = ASN1Sequence();
    validitySeq.add(ASN1UtcTime(DateTime.now().subtract(const Duration(days: 3)).toUtc()));
    validitySeq.add(ASN1UtcTime(DateTime.now().add(Duration(days: days)).toUtc()));
    data.add(validitySeq);

    // Add Subject
    var subjectSeq = ASN1Sequence();
    subject ??= Map.from(caRoot.tbsCertificate!.subject);

    for (var k in subject.keys) {
      var s = _identifier(k, subject[k]!);
      subjectSeq.add(s);
    }

    data.add(subjectSeq);

    // Add Public Key
    data.add(_makePublicKeyBlock(publicKey));

    // Add Extensions

    if (IterableUtils.isNotNullOrEmpty(sans) || keyUsage != null || IterableUtils.isNotNullOrEmpty(extKeyUsage)) {
      var extensionTopSequence = ASN1Sequence();

      // Add basic constraints 2.5.29.19
      if (basicConstraints != null) {
        var basicConstraintsValue = ASN1Sequence();
        basicConstraintsValue.add(ASN1Boolean(basicConstraints.isCA));
        if (basicConstraints.pathLenConstraint != null) {
          basicConstraintsValue.add(ASN1Integer(BigInt.from(basicConstraints.pathLenConstraint!)));
        }
        var octetString = ASN1OctetString(octets: basicConstraintsValue.encode());
        var basicConstraintsSequence = ASN1Sequence();
        basicConstraintsSequence.add(Extension.basicConstraints);
        if (basicConstraints.critical) {
          basicConstraintsSequence.add(ASN1Boolean(true));
        }
        basicConstraintsSequence.add(octetString);
        extensionTopSequence.add(basicConstraintsSequence);
      }

      // Add key usage  2.5.29.15
      if (keyUsage != null) {
        extensionTopSequence.add(keyUsageSequence(keyUsage)!);
      }

      //2.5.29.17
      if (IterableUtils.isNotNullOrEmpty(sans)) {
        var sanList = ASN1Sequence();
        for (var s in sans!) {
          sanList.add(ASN1PrintableString(stringValue: s, tag: 0x82));
        }
        var octetString = ASN1OctetString(octets: sanList.encode());

        var sanSequence = ASN1Sequence();
        sanSequence.add(Extension.subjectAlternativeName);
        sanSequence.add(octetString);
        extensionTopSequence.add(sanSequence);
      }

      // Add ext key usage 2.5.29.37
      var extKeyUsageSequence = extendedKeyUsageEncodings(extKeyUsage);
      if (extKeyUsageSequence != null) {
        extensionTopSequence.add(extKeyUsageSequence);
      }

      var extObj = ASN1Object(tag: 0xA3);
      extObj.valueBytes = extensionTopSequence.encode();

      data.add(extObj);
    }

    var outer = ASN1Sequence();
    outer.add(data);
    outer.add(blockProtocol);
    var encode = _rsaSign(data.encode(), privateKey, _getDigestFromOi(caRoot.signatureAlgorithm));
    outer.add(ASN1BitString(stringValues: encode));

    var chunks = StringUtils.chunk(base64Encode(outer.encode()), 64);

    return '$BEGIN_CERT\n${chunks.join('\r\n')}\n$END_CERT';
  }

  static ASN1Sequence? keyUsageSequence(x509.KeyUsage keyUsages) {
    var octetString = ASN1OctetString(octets: keyUsages.bitString.encode());

    var keyUsageSequence = ASN1Sequence();
    keyUsageSequence.add(Extension.keyUsage);
    if (keyUsages.critical) {
      keyUsageSequence.add(ASN1Boolean(true));
    }
    keyUsageSequence.add(octetString);

    return keyUsageSequence;
  }

  static ASN1Sequence? extendedKeyUsageEncodings(List<ExtendedKeyUsage>? extKeyUsage) {
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
    extKeyUsageSequence.add(Extension.extendedKeyUsage);
    extKeyUsageSequence.add(octetString);
    return extKeyUsageSequence;
  }

  static ASN1Set _identifier(String k, String value) {
    ASN1ObjectIdentifier oIdentifier;
    try {
      oIdentifier = ASN1ObjectIdentifier.fromName(k);
    } on UnsupportedObjectIdentifierException {
      oIdentifier = ASN1ObjectIdentifier.fromIdentifierString(k);
    }

    ASN1Object pString;
    var identifier = oIdentifier.objectIdentifierAsString;
    if (identifier == COUNTRY_NAME || SERIAL_NUMBER == identifier || identifier == DN_QUALIFIER) {
      pString = ASN1PrintableString(stringValue: value);
    } else {
      pString = ASN1UTF8String(utf8StringValue: value);
    }

    var innerSequence = ASN1Sequence(elements: [oIdentifier, pString]);
    return ASN1Set(elements: [innerSequence]);
  }

  static Uint8List _rsaSign(Uint8List inBytes, RSAPrivateKey privateKey, String signingAlgorithm) {
    var signer = Signer('$signingAlgorithm/RSA');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));

    var signature = signer.generateSignature(inBytes) as RSASignature;

    return signature.bytes;
  }

  ///
  /// Create  the public key ASN1Sequence for the csr.
  ///
  static ASN1Sequence _makePublicKeyBlock(RSAPublicKey publicKey) {
    var blockEncryptionType = ASN1Sequence();
    blockEncryptionType.add(ASN1ObjectIdentifier.fromName('rsaEncryption'));
    blockEncryptionType.add(ASN1Null());

    var publicKeySequence = ASN1Sequence();
    publicKeySequence.add(ASN1Integer(publicKey.modulus));
    publicKeySequence.add(ASN1Integer(publicKey.exponent));

    var blockPublicKey = ASN1BitString(stringValues: publicKeySequence.encode());

    var outer = ASN1Sequence();
    outer.add(blockEncryptionType);
    outer.add(blockPublicKey);

    return outer;
  }

  static String _getDigestFromOi(String oi) {
    switch (oi) {
      case 'ecdsaWithSHA1':
      case 'sha1WithRSAEncryption':
        return 'SHA-1';
      case 'ecdsaWithSHA224':
      case 'sha224WithRSAEncryption':
        return 'SHA-224';
      case 'ecdsaWithSHA256':
      case 'sha256WithRSAEncryption':
        return 'SHA-256';
      case 'ecdsaWithSHA384':
      case 'sha384WithRSAEncryption':
        return 'SHA-384';
      case 'ecdsaWithSHA512':
      case 'sha512WithRSAEncryption':
        return 'SHA-512';
      default:
        return 'SHA-256';
    }
  }
}
