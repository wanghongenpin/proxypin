import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/asn1/asn1_object.dart';
import 'package:pointycastle/asn1/asn1_parser.dart';
import 'package:pointycastle/asn1/primitives/asn1_bit_string.dart';
import 'package:pointycastle/asn1/primitives/asn1_integer.dart';
import 'package:pointycastle/asn1/primitives/asn1_object_identifier.dart';
import 'package:pointycastle/asn1/primitives/asn1_octet_string.dart';
import 'package:pointycastle/asn1/primitives/asn1_sequence.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/key_generators/api.dart';
import 'package:pointycastle/key_generators/rsa_key_generator.dart';
import 'package:pointycastle/paddings/pkcs7.dart';
import 'package:pointycastle/random/fortuna_random.dart';

import 'lang.dart';

class CryptoUtils {
  /// ignore: constant_identifier_names
  static const String BEGIN_PUBLIC_KEY = '-----BEGIN PUBLIC KEY-----';
  static const String END_PUBLIC_KEY = '-----END PUBLIC KEY-----';

  // ignore: constant_identifier_names
  static const BEGIN_PRIVATE_KEY = '-----BEGIN PRIVATE KEY-----';
  static const END_PRIVATE_KEY = '-----END PRIVATE KEY-----';

  static const BEGIN_RSA_PRIVATE_KEY = '-----BEGIN RSA PRIVATE KEY-----';
  static const END_RSA_PRIVATE_KEY = '-----END RSA PRIVATE KEY-----';

  static const BEGIN_EC_PRIVATE_KEY = '-----BEGIN EC PRIVATE KEY-----';
  static const String END_EC_PRIVATE_KEY = '-----END EC PRIVATE KEY-----';

  ///
  /// Get a hash for the given [bytes] using the given [algorithm]
  ///
  /// The default [algorithm] used is **SHA-256**. All supported algorihms are :
  ///
  /// * SHA-1
  /// * SHA-224
  /// * SHA-256
  /// * SHA-384
  /// * SHA-512
  /// * SHA-512/224
  /// * SHA-512/256
  /// * MD5
  ///
  static String getHash(Uint8List bytes, {String algorithmName = 'SHA-256'}) {
    var hash = getHashPlain(bytes, algorithmName: algorithmName);

    const hexDigits = '0123456789abcdef';
    var charCodes = Uint8List(hash.length * 2);
    for (var i = 0, j = 0; i < hash.length; i++) {
      var byte = hash[i];
      charCodes[j++] = hexDigits.codeUnitAt((byte >> 4) & 0xF);
      charCodes[j++] = hexDigits.codeUnitAt(byte & 0xF);
    }

    return String.fromCharCodes(charCodes).toUpperCase();
  }

  ///
  /// Get a hash for the given [bytes] using the given [algorithm]
  ///
  /// The default [algorithm] used is **SHA-256**. All supported algorihms are :
  ///
  /// * SHA-1
  /// * SHA-224
  /// * SHA-256
  /// * SHA-384
  /// * SHA-512
  /// * SHA-512/224
  /// * SHA-512/256
  /// * MD5
  ///
  static Uint8List getHashPlain(Uint8List bytes, {String algorithmName = 'SHA-256'}) {
    Uint8List hash;
    switch (algorithmName) {
      case 'SHA-1':
        hash = Digest('SHA-1').process(bytes);
        break;
      case 'SHA-224':
        hash = Digest('SHA-224').process(bytes);
        break;
      case 'SHA-256':
        hash = Digest('SHA-256').process(bytes);
        break;
      case 'SHA-384':
        hash = Digest('SHA-384').process(bytes);
        break;
      case 'SHA-512':
        hash = Digest('SHA-512').process(bytes);
        break;
      case 'SHA-512/224':
        hash = Digest('SHA-512/224').process(bytes);
        break;
      case 'SHA-512/256':
        hash = Digest('SHA-512/256').process(bytes);
        break;
      case 'MD5':
        hash = Digest('MD5').process(bytes);
        break;
      default:
        throw ArgumentError('Hash not supported');
    }

    return hash;
  }

  ///
  /// Returns the private key type of the given [pem]
  ///
  static String getPrivateKeyType(String pem) {
    if (pem.startsWith(BEGIN_RSA_PRIVATE_KEY)) {
      return 'RSA_PKCS1';
    } else if (pem.startsWith(BEGIN_PRIVATE_KEY)) {
      return 'RSA';
    } else if (pem.startsWith(BEGIN_EC_PRIVATE_KEY)) {
      return 'ECC';
    }
    return 'RSA';
  }

  ///
  /// Generates a RSA [AsymmetricKeyPair] with the given [keySize].
  /// The default value for the [keySize] is 2048 bits.
  ///
  /// The following keySize is supported:
  /// * 1024
  /// * 2048
  /// * 3072
  /// * 4096
  /// * 8192
  ///
  static AsymmetricKeyPair generateRSAKeyPair({int keySize = 2048}) {
    var keyParams = RSAKeyGeneratorParameters(BigInt.parse('65537'), keySize, 12);

    var secureRandom = getSecureRandom();

    var rngParams = ParametersWithRandom(keyParams, secureRandom);
    var generator = RSAKeyGenerator();
    generator.init(rngParams);

    return generator.generateKeyPair();
  }

  ///
  /// Decode a [RSAPublicKey] from the given [pem] String.
  ///
  static RSAPublicKey rsaPublicKeyFromPem(String pem) {
    var bytes = CryptoUtils.getBytesFromPEMString(pem);
    return rsaPublicKeyFromDERBytes(bytes);
  }

  ///
  /// Decode the given [bytes] into an [RSAPublicKey].
  ///
  static RSAPublicKey rsaPublicKeyFromDERBytes(Uint8List bytes) {
    var asn1Parser = ASN1Parser(bytes);
    var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    ASN1Sequence publicKeySeq;
    if (topLevelSeq.elements![1].runtimeType == ASN1BitString) {
      var publicKeyBitString = topLevelSeq.elements![1] as ASN1BitString;

      var publicKeyAsn = ASN1Parser(publicKeyBitString.stringValues as Uint8List?);
      publicKeySeq = publicKeyAsn.nextObject() as ASN1Sequence;
    } else {
      publicKeySeq = topLevelSeq;
    }
    var modulus = publicKeySeq.elements![0] as ASN1Integer;
    var exponent = publicKeySeq.elements![1] as ASN1Integer;

    var rsaPublicKey = RSAPublicKey(modulus.integer!, exponent.integer!);

    return rsaPublicKey;
  }

  ///
  /// Decode a [RSAPrivateKey] from the given [pem] String.
  ///
  static RSAPrivateKey rsaPrivateKeyFromPem(String pem) {
    var bytes = getBytesFromPEMString(pem);
    return rsaPrivateKeyFromDERBytes(bytes);
  }

  //
  /// Helper function for decoding the base64 in [pem].
  ///
  /// Throws an ArgumentError if the given [pem] is not sourounded by begin marker -----BEGIN and
  /// endmarker -----END or the [pem] consists of less than two lines.
  ///
  /// The PEM header check can be skipped by setting the optional paramter [checkHeader] to false.
  ///
  static Uint8List getBytesFromPEMString(String pem, {bool checkHeader = true}) {
    var lines = LineSplitter.split(pem).map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
    String base64;
    if (checkHeader) {
      if (lines.length < 2 || !lines.first.startsWith('-----BEGIN') || !lines.last.startsWith('-----END')) {
        throw ArgumentError('The given string does not have the correct '
            'begin/end markers expected in a PEM file.');
      }
      base64 = lines.sublist(1, lines.length - 1).join('');
    } else {
      base64 = lines.join('');
    }

    return Uint8List.fromList(base64Decode(base64));
  }

  ///
  /// Decode the given [bytes] into an [RSAPrivateKey].
  ///
  static RSAPrivateKey rsaPrivateKeyFromDERBytes(Uint8List bytes) {
    var asn1Parser = ASN1Parser(bytes);
    var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    //ASN1Object version = topLevelSeq.elements[0];
    //ASN1Object algorithm = topLevelSeq.elements[1];
    var privateKey = topLevelSeq.elements![2];

    asn1Parser = ASN1Parser(privateKey.valueBytes);
    var pkSeq = asn1Parser.nextObject() as ASN1Sequence;

    var modulus = pkSeq.elements![1] as ASN1Integer;
    //ASN1Integer publicExponent = pkSeq.elements[2] as ASN1Integer;
    var privateExponent = pkSeq.elements![3] as ASN1Integer;
    var p = pkSeq.elements![4] as ASN1Integer;
    var q = pkSeq.elements![5] as ASN1Integer;
    //ASN1Integer exp1 = pkSeq.elements[6] as ASN1Integer;
    //ASN1Integer exp2 = pkSeq.elements[7] as ASN1Integer;
    //ASN1Integer co = pkSeq.elements[8] as ASN1Integer;

    var rsaPrivateKey = RSAPrivateKey(modulus.integer!, privateExponent.integer!, p.integer, q.integer);

    return rsaPrivateKey;
  }

  ///
  /// Enode the given [publicKey] to PEM format using the PKCS#8 standard.
  ///
  static String encodeRSAPublicKeyToPem(RSAPublicKey publicKey) {
    var algorithmSeq = ASN1Sequence();
    var paramsAsn1Obj = ASN1Object.fromBytes(Uint8List.fromList([0x5, 0x0]));
    algorithmSeq.add(ASN1ObjectIdentifier.fromName('rsaEncryption'));
    algorithmSeq.add(paramsAsn1Obj);

    var publicKeySeq = ASN1Sequence();
    publicKeySeq.add(ASN1Integer(publicKey.modulus));
    publicKeySeq.add(ASN1Integer(publicKey.exponent));
    var publicKeySeqBitString = ASN1BitString(stringValues: Uint8List.fromList(publicKeySeq.encode()));

    var topLevelSeq = ASN1Sequence();
    topLevelSeq.add(algorithmSeq);
    topLevelSeq.add(publicKeySeqBitString);
    var dataBase64 = base64.encode(topLevelSeq.encode());
    var chunks = Strings.chunk(dataBase64, 64);

    return '$BEGIN_PUBLIC_KEY\n${chunks.join('\n')}\n$END_PUBLIC_KEY';
  }

  ///
  /// Enode the given [rsaPrivateKey] to PEM format using the PKCS#1 standard.
  ///
  /// The ASN1 structure is decripted at <https://tools.ietf.org/html/rfc8017#page-54>.
  ///
  /// ```
  /// RSAPrivateKey ::= SEQUENCE {
  ///   version           Version,
  ///   modulus           INTEGER,  -- n
  ///   publicExponent    INTEGER,  -- e
  ///   privateExponent   INTEGER,  -- d
  ///   prime1            INTEGER,  -- p
  ///   prime2            INTEGER,  -- q
  ///   exponent1         INTEGER,  -- d mod (p-1)
  ///   exponent2         INTEGER,  -- d mod (q-1)
  ///   coefficient       INTEGER,  -- (inverse of q) mod p
  ///   otherPrimeInfos   OtherPrimeInfos OPTIONAL
  /// }
  /// ```
  static String encodeRSAPrivateKeyToPemPkcs1(RSAPrivateKey rsaPrivateKey) {
    var version = ASN1Integer(BigInt.from(0));
    var modulus = ASN1Integer(rsaPrivateKey.n);
    var publicExponent = ASN1Integer(BigInt.parse('65537'));
    var privateExponent = ASN1Integer(rsaPrivateKey.privateExponent);

    var p = ASN1Integer(rsaPrivateKey.p);
    var q = ASN1Integer(rsaPrivateKey.q);
    var dP = rsaPrivateKey.privateExponent! % (rsaPrivateKey.p! - BigInt.from(1));
    var exp1 = ASN1Integer(dP);
    var dQ = rsaPrivateKey.privateExponent! % (rsaPrivateKey.q! - BigInt.from(1));
    var exp2 = ASN1Integer(dQ);
    var iQ = rsaPrivateKey.q!.modInverse(rsaPrivateKey.p!);
    var co = ASN1Integer(iQ);

    var topLevelSeq = ASN1Sequence();
    topLevelSeq.add(version);
    topLevelSeq.add(modulus);
    topLevelSeq.add(publicExponent);
    topLevelSeq.add(privateExponent);
    topLevelSeq.add(p);
    topLevelSeq.add(q);
    topLevelSeq.add(exp1);
    topLevelSeq.add(exp2);
    topLevelSeq.add(co);
    var dataBase64 = base64.encode(topLevelSeq.encode());
    var chunks = Strings.chunk(dataBase64, 64);
    return '$BEGIN_RSA_PRIVATE_KEY\n${chunks.join('\n')}\n$END_RSA_PRIVATE_KEY';
  }

  ///
  /// Enode the given [rsaPrivateKey] to PEM format using the PKCS#8 standard.
  ///
  /// The ASN1 structure is decripted at <https://tools.ietf.org/html/rfc5208>.
  /// ```
  /// PrivateKeyInfo ::= SEQUENCE {
  ///   version         Version,
  ///   algorithm       AlgorithmIdentifier,
  ///   PrivateKey      BIT STRING
  /// }
  /// ```
  ///
  static String encodeRSAPrivateKeyToPem(RSAPrivateKey rsaPrivateKey) {
    var version = ASN1Integer(BigInt.from(0));

    var algorithmSeq = ASN1Sequence();
    var algorithmAsn1Obj =
        ASN1Object.fromBytes(Uint8List.fromList([0x6, 0x9, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0xd, 0x1, 0x1, 0x1]));
    var paramsAsn1Obj = ASN1Object.fromBytes(Uint8List.fromList([0x5, 0x0]));
    algorithmSeq.add(algorithmAsn1Obj);
    algorithmSeq.add(paramsAsn1Obj);

    var privateKeySeq = ASN1Sequence();
    var modulus = ASN1Integer(rsaPrivateKey.n);
    var publicExponent = ASN1Integer(BigInt.parse('65537'));
    var privateExponent = ASN1Integer(rsaPrivateKey.privateExponent);
    var p = ASN1Integer(rsaPrivateKey.p);
    var q = ASN1Integer(rsaPrivateKey.q);
    var dP = rsaPrivateKey.privateExponent! % (rsaPrivateKey.p! - BigInt.from(1));
    var exp1 = ASN1Integer(dP);
    var dQ = rsaPrivateKey.privateExponent! % (rsaPrivateKey.q! - BigInt.from(1));
    var exp2 = ASN1Integer(dQ);
    var iQ = rsaPrivateKey.q!.modInverse(rsaPrivateKey.p!);
    var co = ASN1Integer(iQ);

    privateKeySeq.add(version);
    privateKeySeq.add(modulus);
    privateKeySeq.add(publicExponent);
    privateKeySeq.add(privateExponent);
    privateKeySeq.add(p);
    privateKeySeq.add(q);
    privateKeySeq.add(exp1);
    privateKeySeq.add(exp2);
    privateKeySeq.add(co);
    var publicKeySeqOctetString = ASN1OctetString(octets: Uint8List.fromList(privateKeySeq.encode()));

    var topLevelSeq = ASN1Sequence();
    topLevelSeq.add(version);
    topLevelSeq.add(algorithmSeq);
    topLevelSeq.add(publicKeySeqOctetString);
    var dataBase64 = base64.encode(topLevelSeq.encode());
    var chunks = Strings.chunk(dataBase64, 64);
    return '$BEGIN_PRIVATE_KEY\n${chunks.join('\n')}\n$END_PRIVATE_KEY';
  }

  ///
  /// Generates a secure [FortunaRandom]
  ///
  static SecureRandom getSecureRandom() {
    var secureRandom = FortunaRandom();
    var random = Random.secure();
    var seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  ///
  /// Revomes the PKCS7 / PKCS5 padding from the [padded] bytes
  ///
  static Uint8List removePKCS7Padding(Uint8List padded) =>
      padded.sublist(0, padded.length - PKCS7Padding().padCount(padded));

  ///
  /// Adds a PKCS7 / PKCS5 padding to the given [bytes] and [blockSizeBytes]
  ///
  static Uint8List addPKCS7Padding(Uint8List bytes, int blockSizeBytes) {
    final padLength = blockSizeBytes - (bytes.length % blockSizeBytes);

    final padded = Uint8List(bytes.length + padLength)..setAll(0, bytes);
    PKCS7Padding().addPadding(padded, bytes.length);

    return padded;
  }
}
