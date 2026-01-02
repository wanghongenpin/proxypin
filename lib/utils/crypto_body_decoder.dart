import 'dart:convert';
import 'dart:typed_data';

import 'package:proxypin/network/http/http.dart';

import '../network/components/manager/request_crypto_manager.dart';
import '../network/util/logger.dart';
import 'aes.dart';

class CryptoDecodedResult {
  final Uint8List bytes;
  final String? text;
  final CryptoRule? rule;

  const CryptoDecodedResult({required this.bytes, this.text, this.rule});

  bool get hasText => text != null && text!.trim().isNotEmpty;
}

class CryptoBodyDecoder {
  static Future<CryptoDecodedResult?> maybeDecode(HttpMessage message) async {
    final url = message is HttpRequest
        ? message.requestUrl
        : message is HttpResponse
            ? message.request?.requestUrl
            : null;
    if (url == null) return null;
    final ruleStore = await RequestCryptoManager.instance;

    CryptoRule? match = ruleStore.getMatchingRule(url);
    if (match != null) {
      return _tryDecode(message, match.config, rule: match);
    }

    return null;
  }

  static CryptoDecodedResult? decode(HttpMessage message, CryptoKeyConfig config) {
    return _tryDecode(message, config);
  }

  static CryptoDecodedResult? decodeWithConfig(HttpMessage message, CryptoKeyConfig config) {
    return _tryDecode(message, config);
  }

  static CryptoDecodedResult? _tryDecode(HttpMessage message, CryptoKeyConfig config, {CryptoRule? rule}) {
    final raw = message.body;
    if (raw == null || raw.isEmpty || !config.isReady) {
      return null;
    }

    // If rule specifies a field, try to parse body as JSON and extract that field for decryption
    final fieldPath = rule?.field?.trim();
    logger.d("CryptoBodyDecoder _tryDecode with config: $config and rule: $rule fieldPath: $fieldPath");
    if (fieldPath != null && fieldPath.isNotEmpty) {
      // parse body as text
      final content = _bytesToString(raw, message.charset);
      if (content == null) return null;
      dynamic jsonObj;
      try {
        jsonObj = jsonDecode(content);
      } catch (_) {
        return null;
      }

      final extracted = _extractJsonField(jsonObj, fieldPath);
      if (extracted == null) return null;
      // Only attempt when extracted is a string or number (we stringify otherwise)
      String fieldStr = extracted.toString();

      // build candidates from the field string: raw bytes and base64-decoded (if looks like base64)
      final candidates = <Uint8List>[];
      final base64Candidate = _tryDecodeBase64String(fieldStr);
      if (base64Candidate != null) candidates.add(base64Candidate);

      for (final candidate in candidates) {
        try {
          final decrypted = _decryptCandidate(candidate, config);
          // print("CryptoBodyDecoder _tryDecode decrypted bytes: $decrypted");
          if (decrypted != null) {
            return CryptoDecodedResult(bytes: decrypted, text: _bytesToString(decrypted, message.charset), rule: rule);
          }
        } catch (e) {
          logger.d("CryptoBodyDecoder _tryDecode decryption error: $e");
          continue;
        }
      }
      return null;
    }

    // whole-body: try raw bytes and base64-decoded text
    final candidates = <Uint8List>[];
    // candidates.add(Uint8List.fromList(raw));
    final base64Candidate = _fromBase64(raw);
    if (base64Candidate != null) {
      candidates.add(base64Candidate);
    }
    // logger.d("CryptoBodyDecoder _tryDecode total candidates: ${candidates.length}");
    for (final candidate in candidates) {
      try {
        final decrypted = _decryptCandidate(candidate, config);
        // logger.d("CryptoBodyDecoder _tryDecode decrypted bytes: $decrypted");
        if (decrypted != null) {
          return CryptoDecodedResult(bytes: decrypted, text: _bytesToString(decrypted, message.charset), rule: rule);
        }
      } catch (e) {
        logger.d("CryptoBodyDecoder _tryDecode decryption error: $e");
        continue;
      }
    }
    return null;
  }

  // Attempt to decrypt a single candidate, handling ivSource == 'prefix' by extracting IV bytes.
  static Uint8List? _decryptCandidate(Uint8List candidate, CryptoKeyConfig config) {
    const int aesBlockSize = 16;
    // If using prefix-mode, split IV and cipher bytes and ensure cipher bytes length is valid for non-PKCS7 paddings
    if (config.mode == 'CBC' && config.ivSource == 'prefix') {
      final n = config.ivPrefixLength;
      if (candidate.length <= n) return null;
      final ivBytes = candidate.sublist(0, n);
      final cipherBytes = candidate.sublist(n);
      // For non-PKCS7 paddings (e.g., ZeroPadding/raw) the cipher bytes length must be multiple of block size
      if (config.padding != 'PKCS7' && (cipherBytes.length % aesBlockSize != 0)) return null;
      final ivStr = 'base64:' + base64.encode(ivBytes);
      try {
        return AesUtils.decrypt(cipherBytes, key: config.key, keyLength: config.keyLength, mode: config.mode, padding: config.padding, iv: ivStr);
      } catch (e) {
        logger.d('CryptoBodyDecoder _decryptCandidate error (prefix): $e');
        return null;
      }
    } else {
      // iv provided in config.iv (may include base64: prefix or be plain text)
      // For non-PKCS7 paddings ensure candidate length is block-aligned before attempting raw decrypt
      if (config.padding != 'PKCS7' && (candidate.length % aesBlockSize != 0)) return null;
      final ivParam = (config.mode == 'CBC') ? config.iv : null;
      try {
        return AesUtils.decrypt(candidate, key: config.key, keyLength: config.keyLength, mode: config.mode, padding: config.padding, iv: ivParam);
      } catch (e) {
        logger.d('CryptoBodyDecoder _decryptCandidate error: $e');
        return null;
      }
    }
  }

  // Try to decode a base64 string; return bytes or null
  static Uint8List? _tryDecodeBase64String(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return null;
    if (!_maybeBase64(trimmed)) return null;
    try {
      return Uint8List.fromList(base64.decode(trimmed));
    } catch (_) {
      return null;
    }
  }

  // Extract a nested JSON field by a dot-separated path. Supports array indexes like items[0].value
  static dynamic _extractJsonField(dynamic jsonObj, String path) {
    final parts = path.split('.');
    dynamic current = jsonObj;
    for (final part in parts) {
      if (current == null) return null;
      // check for array index like key[index]
      final arrayMatch = RegExp(r"^([a-zA-Z0-9_\-]+)\[(\d+)\]").firstMatch(part);
      if (arrayMatch != null) {
        final key = arrayMatch.group(1)!;
        final idx = int.parse(arrayMatch.group(2)!);
        if (current is Map && current.containsKey(key)) {
          final list = current[key];
          if (list is List && idx >= 0 && idx < list.length) {
            current = list[idx];
            continue;
          }
          return null;
        }
        return null;
      }

      // normal key or numeric index for lists
      if (current is Map) {
        if (!current.containsKey(part)) return null;
        current = current[part];
      } else if (current is List) {
        final idx = int.tryParse(part);
        if (idx == null || idx < 0 || idx >= current.length) return null;
        current = current[idx];
      } else {
        return null;
      }
    }
    return current;
  }

  static Uint8List? _fromBase64(List<int> raw) {
    try {
      final content = utf8.decode(raw).trim();
      if (content.isEmpty || !_maybeBase64(content)) {
        return null;
      }
      return Uint8List.fromList(base64.decode(content));
    } catch (_) {
      return null;
    }
  }

  static bool _maybeBase64(String value) {
    if (value.length % 4 != 0) return false;
    if (value.contains(RegExp(r'[^A-Za-z0-9+/=\r\n]'))) return false;
    return true;
  }

  static String? _bytesToString(List<int> bytes, String? charset) {
    try {
      if (charset == null || charset.toLowerCase().contains('utf')) {
        return utf8.decode(bytes);
      }
      return const Latin1Codec().decode(bytes);
    } catch (_) {
      try {
        return utf8.decode(bytes);
      } catch (_) {
        return null;
      }
    }
  }
}
