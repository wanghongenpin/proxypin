// ignore_for_file: constant_identifier_names, depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/asn1/unsupported_object_identifier_exception.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:proxypin/network/util/cert/extension.dart';

import '../crypto.dart';
import '../lang.dart';
import 'basic_constraints.dart';
import 'cert_data.dart';
import 'key_usage.dart';

/// @author wanghongen
/// 2023/7/26
class X509Utils {
  static const String BEGIN_CERT = '-----BEGIN CERTIFICATE-----';
  static const String END_CERT = '-----END CERTIFICATE-----';

  static const BEGIN_CRL = '-----BEGIN X509 CRL-----';
  static const END_CRL = '-----END X509 CRL-----';

  //所在国家
  static const String COUNTRY_NAME = "2.5.4.6";
  static const String SERIAL_NUMBER = "2.5.4.5";
  static const String DN_QUALIFIER = "2.5.4.46";

  ///android 系统证书名称
  static String getSubjectHashName(Map<String, String?> subject) {
    // Add Issuer
    var issuerSeq = ASN1Sequence();
    for (var k in subject.keys) {
      var s = X509Utils._identifier(k, subject[k]!);
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
  /// Encode the given [asn1Object] to PEM format and adding the [begin] and [end].
  ///
  static String encodeASN1ObjectToPem(ASN1Object asn1Object, String begin, String end, {String newLine = '\n'}) {
    var bytes = asn1Object.encode();
    var chunks = Strings.chunk(base64.encode(bytes), 64);
    return '$begin$newLine${chunks.join(newLine)}$newLine$end';
  }

  ///
  /// Converts the given DER encoded CRL to a PEM string with the corresponding
  /// headers. The given [bytes] can be taken directly from a .crl file.
  ///
  static String crlDerToPem(Uint8List bytes) {
    return formatKeyString(base64.encode(bytes), BEGIN_CRL, END_CRL);
  }

  ///
  /// Formats the given [key] by chunking the [key] and adding the [begin] and [end] to the [key].
  ///
  /// The line length will be defined by the given [chunkSize]. The default value is 64.
  ///
  /// Each line will be delimited by the given [lineDelimiter]. The default value is '\n'.w
  ///
  static String formatKeyString(String key, String begin, String end,
      {int chunkSize = 64, String lineDelimiter = '\n'}) {
    var sb = StringBuffer();
    var chunks = Strings.chunk(key, chunkSize);
    if (Strings.isNotEmpty(begin)) {
      sb.write(begin + lineDelimiter);
    }
    for (var s in chunks) {
      sb.write(s + lineDelimiter);
    }
    if (Strings.isNotEmpty(end)) {
      sb.write(end);
      return sb.toString();
    } else {
      var tmp = sb.toString();
      return tmp.substring(0, tmp.lastIndexOf(lineDelimiter));
    }
  }

  ///
  /// Parses the given PEM to a [X509CertificateData] object.
  ///
  /// Throws an [ASN1Exception] if the pem could not be read by the [ASN1Parser].
  ///
  static X509CertificateData x509CertificateFromPem(String pem) {
    var bytes = CryptoUtils.getBytesFromPEMString(pem);
    var asn1Parser = ASN1Parser(bytes);
    var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

    var x509 = _x509FromAsn1Sequence(topLevelSeq);

    var sha1String = CryptoUtils.getHash(bytes, algorithmName: 'SHA-1');
    var md5String = CryptoUtils.getHash(bytes, algorithmName: 'MD5');
    var sha256String = CryptoUtils.getHash(bytes, algorithmName: 'SHA-256');

    x509.plain = pem;
    x509.sha1Thumbprint = sha1String;
    x509.md5Thumbprint = md5String;
    x509.sha256Thumbprint = sha256String;
    return x509;
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
    ExtensionKeyUsage? keyUsage,
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

    issuer ??= Map.from(caRoot.subject);

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
    subject ??= Map.from(caRoot.subject);

    for (var k in subject.keys) {
      var s = _identifier(k, subject[k]!);
      subjectSeq.add(s);
    }

    data.add(subjectSeq);

    // Add Public Key
    data.add(_makePublicKeyBlock(publicKey));

    // Add Extensions

    if (Lists.isNotEmpty(sans) || keyUsage != null || Lists.isNotEmpty(extKeyUsage)) {
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
      if (sans != null && sans.isNotEmpty) {
        var sanList = ASN1Sequence();
        for (var s in sans) {
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

    var chunks = Strings.chunk(base64Encode(outer.encode()), 64);

    return '$BEGIN_CERT\n${chunks.join('\r\n')}\n$END_CERT';
  }

  static X509CertificateData _x509FromAsn1Sequence(ASN1Sequence topLevelSeq) {
    var tbsCertificateSeq = topLevelSeq.elements!.elementAt(0) as ASN1Sequence;
    var signatureAlgorithmSeq = topLevelSeq.elements!.elementAt(1) as ASN1Sequence;
    var signateureSeq = topLevelSeq.elements!.elementAt(2) as ASN1BitString;

    // tbsCertificate
    var element = 0;
    // Version
    var version = 1;
    if (tbsCertificateSeq.elements!.elementAt(0) is ASN1Integer) {
      // The version ASN1Object ist missing use version 1
      version = 1;
      element = -1;
    } else {
      // Version 1 (int = 0), version 2 (int = 1) or version 3 (int = 2)
      var versionObject = tbsCertificateSeq.elements!.elementAt(element + 0);
      version = versionObject.valueBytes!.elementAt(2);
      version++;
    }

    // Serial Number
    var serialInteger = tbsCertificateSeq.elements!.elementAt(element + 1) as ASN1Integer;
    var serialNumber = serialInteger.integer;

    // Signature
    // var signatureSequence = tbsCertificateSeq.elements!.elementAt(element + 2) as ASN1Sequence;
    // var o = signatureSequence.elements!.elementAt(0) as ASN1ObjectIdentifier;
    // var signatureAlgorithm = o.objectIdentifierAsString!;
    // var signatureAlgorithmReadable = o.readableName!;

    // Issuer
    var issuerSequence = tbsCertificateSeq.elements!.elementAt(element + 3) as ASN1Sequence;
    var issuer = _getDnFromSeq(issuerSequence);

    // Validity
    var validitySequence = tbsCertificateSeq.elements!.elementAt(element + 4) as ASN1Sequence;
    var validity = _getValidityFromSeq(validitySequence);

    // Subject
    var subjectSequence = tbsCertificateSeq.elements!.elementAt(element + 5) as ASN1Sequence;
    var subject = _getDnFromSeq(subjectSequence);

    // Subject Public Key Info
    var pubKeySequence = tbsCertificateSeq.elements!.elementAt(element + 6) as ASN1Sequence;
    var subjectPublicKeyInfo = _getSubjectPublicKeyInfoFromSeq(pubKeySequence);

    X509CertificateDataExtensions? extensions;
    if (version > 1 && tbsCertificateSeq.elements!.length > element + 7) {
      var extensionObject = tbsCertificateSeq.elements!.elementAt(element + 7);
      var extParser = ASN1Parser(extensionObject.valueBytes);
      var extSequence = extParser.nextObject() as ASN1Sequence;
      extensions = _getExtensionsFromSeq(extSequence);
    }

    // signatureAlgorithm
    var pubKeyOid = signatureAlgorithmSeq.elements!.elementAt(0) as ASN1ObjectIdentifier;

    // signatureValue
    var sigAsString = _bytesAsString(signateureSeq.valueBytes!);

    return X509CertificateData(
      version: version,
      serialNumber: serialNumber!,
      signatureAlgorithm: pubKeyOid.objectIdentifierAsString!,
      signatureAlgorithmReadableName: pubKeyOid.readableName,
      signature: sigAsString,
      issuer: issuer,
      validity: validity,
      subject: subject,
      publicKeyData: X509CertificatePublicKeyData.fromSubjectPublicKeyInfo(subjectPublicKeyInfo),
      subjectAlternativNames: extensions?.subjectAlternativNames,
      extKeyUsage: extensions?.extKeyUsage,
      extensions: extensions,
      // tbsCertificate: tbsCertificate,
      tbsCertificateSeqAsString: base64.encode(
        tbsCertificateSeq.encode(),
      ),
    );
  }

  static X509CertificateDataExtensions _getExtensionsFromSeq(ASN1Sequence extSequence) {
    List<String>? sans;
    List<KeyUsage>? keyUsage;
    List<ExtendedKeyUsage>? extKeyUsage;
    List<dynamic> basicConstraints;
    var extensions = X509CertificateDataExtensions();
    for (var subseq in extSequence.elements!) {
        var seq = subseq as ASN1Sequence;
        var oi = seq.elements!.elementAt(0) as ASN1ObjectIdentifier;
        if (oi.objectIdentifierAsString == '2.5.29.17') {
          if (seq.elements!.length == 3) {
            sans = _fetchSansFromExtension(seq.elements!.elementAt(2));
          } else {
            sans = _fetchSansFromExtension(seq.elements!.elementAt(1));
          }
          extensions.subjectAlternativNames = sans;
        }

        var keyUsageSequence = ASN1Sequence();
        keyUsageSequence.add(ASN1ObjectIdentifier.fromIdentifierString('2.5.29.15'));

        if (oi.objectIdentifierAsString == '2.5.29.15') {
          if (seq.elements!.length == 3) {
            keyUsage = _fetchKeyUsageFromExtension(seq.elements!.elementAt(2));
          } else {
            keyUsage = _fetchKeyUsageFromExtension(seq.elements!.elementAt(1));
          }
          extensions.keyUsage = keyUsage;
        }
        if (oi.objectIdentifierAsString == '2.5.29.37') {
          if (seq.elements!.length == 3) {
            extKeyUsage = _fetchExtendedKeyUsageFromExtension(seq.elements!.elementAt(2));
          } else {
            extKeyUsage = _fetchExtendedKeyUsageFromExtension(seq.elements!.elementAt(1));
          }
          extensions.extKeyUsage = extKeyUsage;
        }
        if (oi.objectIdentifierAsString == '2.5.29.19') {
          if (seq.elements!.length == 3) {
            basicConstraints = _fetchBasicConstraintsFromExtension(seq.elements!.elementAt(2));
          } else {
            basicConstraints = [null, null];
          }

          extensions.cA = basicConstraints[0];
          extensions.pathLenConstraint = basicConstraints[1];
        }
        if (oi.objectIdentifierAsString == '1.3.6.1.5.5.7.1.12') {
          var vmcData = _fetchVmcLogo(seq.elements!.elementAt(1));
          extensions.vmc = vmcData;
        }
        if (oi.objectIdentifierAsString == '2.5.29.31') {
          var cRLDistributionPoints = _fetchCrlDistributionPoints(seq.elements!.elementAt(1));
          extensions.cRLDistributionPoints = cRLDistributionPoints;
        }
      }
    return extensions;
  }

  static ASN1Sequence? keyUsageSequence(ExtensionKeyUsage keyUsages) {
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
    if (extKeyUsage == null || extKeyUsage.isEmpty) {
      return null;
    }
    var extKeyUsageList = ASN1Sequence();
    for (var s in extKeyUsage) {
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

  static SubjectPublicKeyInfo _getSubjectPublicKeyInfoFromSeq(ASN1Sequence pubKeySequence) {
    var algSeq = pubKeySequence.elements!.elementAt(0) as ASN1Sequence;
    var algOi = algSeq.elements!.elementAt(0) as ASN1ObjectIdentifier;
    var asn1AlgParameters = algSeq.elements!.elementAt(1);
    var algParameters = '';
    var algParametersReadable = '';
    if (asn1AlgParameters is ASN1ObjectIdentifier) {
      algParameters = asn1AlgParameters.objectIdentifierAsString!;
      algParametersReadable = asn1AlgParameters.readableName!;
    }

    var pubBitString = pubKeySequence.elements!.elementAt(1) as ASN1BitString;
    var asn1PubKeyParser = ASN1Parser(pubBitString.stringValues as Uint8List?);
    ASN1Object? next;
    try {
      next = asn1PubKeyParser.nextObject();
    } catch (e) {
      // continue
    }
    int pubKeyLength;
    int? exponent;
    var pubKeyAsBytes = pubKeySequence.encodedBytes;
    if (next != null && next is ASN1Sequence) {
      var s = next;
      var key = s.elements!.elementAt(0) as ASN1Integer;
      if (s.elements!.length == 2 && s.elements!.elementAt(1) is ASN1Integer) {
        var asn1Exponent = s.elements!.elementAt(1) as ASN1Integer;
        exponent = asn1Exponent.integer!.toInt();
      }
      pubKeyLength = key.integer!.bitLength;
      //pubKeyAsBytes = s.encodedBytes;
    } else {
      //pubKeyAsBytes = pubBitString.valueBytes;
      var length = pubBitString.valueBytes!.elementAt(0) == 0
          ? (pubBitString.valueByteLength! - 1)
          : pubBitString.valueByteLength;
      pubKeyLength = length! * 8;
    }

    var pubKeyThumbprint = CryptoUtils.getHash(pubKeySequence.encodedBytes!, algorithmName: 'SHA-1');
    var pubKeySha256Thumbprint = CryptoUtils.getHash(pubKeySequence.encodedBytes!, algorithmName: 'SHA-256');

    return SubjectPublicKeyInfo(
      algorithm: algOi.objectIdentifierAsString,
      algorithmReadableName: algOi.readableName,
      parameter: algParameters != '' ? algParameters : null,
      parameterReadableName: algParametersReadable != '' ? algParametersReadable : null,
      length: pubKeyLength,
      bytes: _bytesAsString(pubKeyAsBytes!),
      sha1Thumbprint: pubKeyThumbprint,
      sha256Thumbprint: pubKeySha256Thumbprint,
      exponent: exponent,
    );
  }

  ///
  /// Converts the bytes to a hex string
  ///
  static String _bytesAsString(Uint8List bytes) {
    var b = StringBuffer();
    for (var v in bytes) {
      var s = v.toRadixString(16);
      if (s.length == 1) {
        b.write('0$s');
      } else {
        b.write(s);
      }
    }
    return b.toString().toUpperCase();
  }

  ///
  /// Fetches the base64 encoded VMC logo from the given [extData]
  ///
  static VmcData _fetchVmcLogo(ASN1Object extData) {
    var octet = extData as ASN1OctetString;
    var vmcParser = ASN1Parser(octet.valueBytes);
    var topSeq = vmcParser.nextObject() as ASN1Sequence;
    var obj1 = topSeq.elements!.elementAt(0);
    var obj1Parser = ASN1Parser(obj1.valueBytes);
    var obj2 = obj1Parser.nextObject();
    var obj2Parser = ASN1Parser(obj2.valueBytes);
    var obj2Seq = obj2Parser.nextObject() as ASN1Sequence;
    var nextSeq = obj2Seq.elements!.elementAt(0) as ASN1Sequence;
    var finalSeq = nextSeq.elements!.elementAt(0) as ASN1Sequence;

    var data = VmcData();
    // Parse fileType
    var ia5 = finalSeq.elements!.elementAt(0) as ASN1IA5String;
    var fileType = ia5.stringValue!;

    // Parse hash
    var hashSeq = finalSeq.elements!.elementAt(1) as ASN1Sequence;
    var hasFinalSeq = hashSeq.elements!.elementAt(0) as ASN1Sequence;
    var algSeq = hasFinalSeq.elements!.elementAt(0) as ASN1Sequence;
    var oi = algSeq.elements!.elementAt(0) as ASN1ObjectIdentifier;
    data.hashAlgorithm = oi.objectIdentifierAsString;
    data.hashAlgorithmReadable = oi.readableName;
    var octetString = hasFinalSeq.elements!.elementAt(1) as ASN1OctetString;
    var hash = _bytesAsString(octetString.octets!);
    data.hash = hash;

    // Parse base64 logo
    var logoSeq = finalSeq.elements!.elementAt(2) as ASN1Sequence;
    var ia5Logo = logoSeq.elements!.elementAt(0) as ASN1IA5String;
    var base64LogoGzip = ia5Logo.stringValue;
    var gzip = base64LogoGzip!.substring(base64LogoGzip.indexOf(',') + 1);
    final decodedData = GZipCodec().decode(base64.decode(gzip));
    var base64Logo = base64.encode(decodedData);

    data.base64Logo = base64Logo;
    data.type = fileType;

    return data;
  }

  ///
  /// Parses the given object identifier values to the internal enum
  ///
  static List<KeyUsage> _fetchKeyUsageFromExtension(ASN1Object extData) {
    var keyUsage = <KeyUsage>[];
    var octet = extData as ASN1OctetString;
    var keyUsageParser = ASN1Parser(octet.valueBytes);
    var keyUsageBitString = keyUsageParser.nextObject() as ASN1BitString;
    if (keyUsageBitString.valueBytes?.isEmpty ?? true) {
      return keyUsage;
    }

    final Uint8List bytes = keyUsageBitString.valueBytes!;
    final int lastBitsToSkip = bytes.first;
    final int amountOfBytes = bytes.length - 1; //don't count the first byte

    for (int bitCounter = 0; bitCounter < amountOfBytes * 8 - lastBitsToSkip; ++bitCounter) {
      final int byteIndex = bitCounter ~/ 8; // the current byte
      final int bitIndex = bitCounter % 8; // the current bit
      if (byteIndex >= amountOfBytes) {
        return keyUsage;
      }

      final int byte = bytes[1 + byteIndex]; //skip the first byte
      final bool keyBit = _getBitOfByte(byte, bitIndex);

      if (keyBit == true && KeyUsage.values.length > bitCounter) {
        keyUsage.add(KeyUsage.values[bitCounter]);
      }
    }
    return keyUsage;
  }

  /// From left to right. Returns [true] for 1 and [false] for [0].
  static bool _getBitOfByte(int byte, int bitIndex) {
    final int shift = 7 - bitIndex;
    final int shiftedByte = byte >> shift;
    if (shiftedByte & 1 == 1) {
      return true;
    } else {
      return false;
    }
  }

  ///
  /// Parses the given object identifier values to the internal enum
  ///
  static List<ExtendedKeyUsage> _fetchExtendedKeyUsageFromExtension(ASN1Object extData) {
    var extKeyUsage = <ExtendedKeyUsage>[];
    var octet = extData as ASN1OctetString;
    var keyUsageParser = ASN1Parser(octet.valueBytes);
    var keyUsageSeq = keyUsageParser.nextObject() as ASN1Sequence;
    for (var oi in keyUsageSeq.elements!) {
      if (oi is ASN1ObjectIdentifier) {
        var s = oi.objectIdentifierAsString;
        switch (s) {
          case '1.3.6.1.5.5.7.3.1':
            extKeyUsage.add(ExtendedKeyUsage.SERVER_AUTH);
            break;
          case '1.3.6.1.5.5.7.3.2':
            extKeyUsage.add(ExtendedKeyUsage.CLIENT_AUTH);
            break;
          case '1.3.6.1.5.5.7.3.3':
            extKeyUsage.add(ExtendedKeyUsage.CODE_SIGNING);
            break;
          case '1.3.6.1.5.5.7.3.4':
            extKeyUsage.add(ExtendedKeyUsage.EMAIL_PROTECTION);
            break;
          case '1.3.6.1.5.5.7.3.8':
            extKeyUsage.add(ExtendedKeyUsage.TIME_STAMPING);
            break;
          case '1.3.6.1.5.5.7.3.9':
            extKeyUsage.add(ExtendedKeyUsage.OCSP_SIGNING);
            break;
          case '1.3.6.1.5.5.7.3.31':
            extKeyUsage.add(ExtendedKeyUsage.BIMI);
            break;
          default:
        }
      }
    }
    return extKeyUsage;
  }

  ///
  /// Parses the given ASN1Object to the two basic constraint
  /// fields cA and pathLenConstraint. Returns a list of types [bool, int] if
  /// cA is true and a valid pathLenConstraint is specified, else the
  /// corresponding element will be null.
  ///
  static List<dynamic> _fetchBasicConstraintsFromExtension(ASN1Object extData) {
    var basicConstraints = <dynamic>[null, null];
    var octet = extData as ASN1OctetString;
    var constraintParser = ASN1Parser(octet.valueBytes);
    var constraintSeq = constraintParser.nextObject() as ASN1Sequence;
    for (var obj in constraintSeq.elements!) {
      if (obj is ASN1Boolean) {
        basicConstraints[0] = obj.boolValue;
      }
      if (obj is ASN1Integer) {
        basicConstraints[1] = obj.integer!.toInt();
      }
    }
    return basicConstraints;
  }

  ///
  /// Fetches a list of subject alternative names from the given [extData]
  ///
  static List<String> _fetchSansFromExtension(ASN1Object extData) {
    var sans = <String>[];
    var octet = extData as ASN1OctetString;
    var sanParser = ASN1Parser(octet.valueBytes);
    var sanSeq = sanParser.nextObject() as ASN1Sequence;
    for (var san in sanSeq.elements!) {
      if (san.tag == 135) {
        var sb = StringBuffer();
        if (san.valueByteLength == 16) {
          //IPv6
          for (var i = 0; i < (san.valueByteLength ?? 0); i++) {
            if (sb.isNotEmpty && i % 2 == 0) {
              sb.write(':');
            }
            sb.write(san.valueBytes![i].toRadixString(16).padLeft(2, '0'));
          }
        } else {
          //IPv4 and others
          for (var b in san.valueBytes!) {
            if (sb.isNotEmpty) {
              sb.write('.');
            }
            sb.write(b);
          }
        }
        sans.add(sb.toString());
      } else if (san.tag == 164) {
        // WE HAVE CONSTRUCTED SAN
        var constructedParser = ASN1Parser(san.valueBytes);
        var seq = constructedParser.nextObject() as ASN1Sequence;
        var sanValue = 'DirName:';
        for (var san in seq.elements!) {
          var set = san as ASN1Set;
          var seq = set.elements!.elementAt(0) as ASN1Sequence;
          var oid = seq.elements!.elementAt(0) as ASN1ObjectIdentifier;
          var object = seq.elements!.elementAt(1);
          var value = '';
          sanValue = '$sanValue/';
          if (object is ASN1UTF8String) {
            var objectAsUtf8 = object;
            value = objectAsUtf8.utf8StringValue!;
          } else if (object is ASN1PrintableString) {
            var objectPrintable = object;
            value = objectPrintable.stringValue!;
          }
          sanValue = '$sanValue${oid.readableName}=$value';
        }
        sans.add(sanValue);
      } else {
        var s = String.fromCharCodes(san.valueBytes!);
        sans.add(s);
      }
    }
    return sans;
  }

  static List<String> _fetchCrlDistributionPoints(ASN1Object extData) {
    var cRLDistributionPoints = <String>[];

    var octet = extData as ASN1OctetString;
    var parser = ASN1Parser(octet.valueBytes);
    var topSeq = parser.nextObject() as ASN1Sequence;
    for (var e in topSeq.elements!) {
      var seq = e as ASN1Sequence;
      var o1 = seq.elements!.elementAt(0);
      var parser = ASN1Parser(o1.valueBytes);
      var o2 = parser.nextObject();
      parser = ASN1Parser(o2.valueBytes);
      var o3 = parser.nextObject();
      var point = String.fromCharCodes(o3.valueBytes!.toList());
      cRLDistributionPoints.add(point);
    }
    return cRLDistributionPoints;
  }

  static X509CertificateValidity _getValidityFromSeq(ASN1Sequence validitySequence) {
    DateTime? asn1FromDateTime;
    DateTime? asn1ToDateTime;
    if (validitySequence.elements!.elementAt(0) is ASN1UtcTime) {
      var asn1From = validitySequence.elements!.elementAt(0) as ASN1UtcTime;
      asn1FromDateTime = asn1From.time;
    } else {
      var asn1From = validitySequence.elements!.elementAt(0) as ASN1GeneralizedTime;
      asn1FromDateTime = asn1From.dateTimeValue;
    }
    if (validitySequence.elements!.elementAt(1) is ASN1UtcTime) {
      var asn1To = validitySequence.elements!.elementAt(1) as ASN1UtcTime;
      asn1ToDateTime = asn1To.time;
    } else {
      var asn1To = validitySequence.elements!.elementAt(1) as ASN1GeneralizedTime;
      asn1ToDateTime = asn1To.dateTimeValue;
    }

    return X509CertificateValidity(
      notBefore: asn1FromDateTime!,
      notAfter: asn1ToDateTime!,
    );
  }

  static Map<String, String> _getDnFromSeq(ASN1Sequence issuerSequence) {
    var dnData = <String, String>{};
    for (var s in issuerSequence.elements as dynamic) {
      for (var ele in s.elements!) {
        var seq = ele as ASN1Sequence;
        var o = seq.elements!.elementAt(0) as ASN1ObjectIdentifier;
        var object = seq.elements!.elementAt(1);
        String? value = '';
        if (object is ASN1UTF8String) {
          var objectAsUtf8 = object;
          value = objectAsUtf8.utf8StringValue;
        } else if (object is ASN1PrintableString) {
          var objectPrintable = object;
          value = objectPrintable.stringValue;
        } else if (object is ASN1TeletextString) {
          var objectTeletext = object;
          value = objectTeletext.stringValue;
        }
        dnData.putIfAbsent(o.objectIdentifierAsString!, () => value ?? '');
      }
    }
    return dnData;
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
