import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class AesUtils {
  static Uint8List encrypt(Uint8List input,
      {required String key, required int keyLength, required String mode, required String padding, String? iv}) {
    return _process(input, true,
        key: key, keyLength: keyLength, mode: mode, padding: padding, iv: iv);
  }

  static Uint8List decrypt(Uint8List input,
      {required String key, required int keyLength, required String mode, required String padding, String? iv}) {
    var data = _process(input, false,
        key: key, keyLength: keyLength, mode: mode, padding: padding, iv: iv);
    // 移除填充零字节（仅 ZeroPadding 场景）
    if (padding == 'ZeroPadding') {
      int lastNonZeroIndex = data.lastIndexWhere((byte) => byte != 0);
      if (lastNonZeroIndex < 0) return Uint8List(0);
      data = data.sublist(0, lastNonZeroIndex + 1);
    }
    return data;
  }

  // Refactored process method (renamed to _process and split into helpers)
  static Uint8List _process(Uint8List input, bool isEncrypt,
      {required String key, required int keyLength, required String mode, required String padding, String? iv}) {
    final int keySize = keyLength ~/ 8;

    // Build key bytes: support 'base64:' prefix or plain text
    final keyBytes = _buildKeyBytes(key, keySize);

    // If CBC mode, prepare IV bytes
    Uint8List? ivBytes;
    if (mode == 'CBC') {
      if (iv == null) {
        throw ArgumentError.value(iv, 'iv', 'IV is required for CBC mode');
      }
      ivBytes = _buildIvBytes(iv);
      // Ensure IV is block-size (16) length
      final blockSize = 16;
      if (ivBytes.length < blockSize) {
        final tmp = Uint8List(blockSize);
        tmp.setRange(0, ivBytes.length, ivBytes);
        ivBytes = tmp;
      } else if (ivBytes.length > blockSize) {
        ivBytes = ivBytes.sublist(0, blockSize);
      }
    }

    final aesEngine = AESEngine();

    // When encrypting with ZeroPadding, pad input to block size
    if (isEncrypt && padding == 'ZeroPadding') {
      input = _padZeroForEncrypt(input, aesEngine.blockSize);
    }

    // PKCS7 path
    if (padding == 'PKCS7') {
      return _processWithPaddedCipher(input, isEncrypt, mode, keyBytes, ivBytes, aesEngine);
    }

    // Raw block cipher / ZeroPadding path
    return _processRawCipher(input, isEncrypt, mode, keyBytes, ivBytes, aesEngine);
  }

  // Build key bytes with required keySize length (pad/truncate handled where used)
  static Uint8List _buildKeyBytes(String key, int keySize) {
    final src = _decodeKeyStringToBytes(key);
    final keyBytes = Uint8List(keySize);
    for (int i = 0; i < keySize && i < src.length; i++) {
      keyBytes[i] = src[i];
    }
    return keyBytes;
  }

  // Decode IV string to bytes (supports base64: prefix or plain text)
  static Uint8List _buildIvBytes(String iv) {
    return _decodeKeyStringToBytes(iv);
  }

  // Zero-padding helper for encryption
  static Uint8List _padZeroForEncrypt(Uint8List input, int blockSize) {
    final rem = input.length % blockSize;
    if (rem == 0) return input;
    final padLen = blockSize - rem;
    final tmp = Uint8List(input.length + padLen);
    tmp.setRange(0, input.length, input);
    // trailing zeros already default to 0
    return tmp;
  }

  static Uint8List _processWithPaddedCipher(Uint8List input, bool isEncrypt, String mode, Uint8List keyBytes,
      Uint8List? ivBytes, AESEngine aesEngine) {
    final BlockCipher blockCipher = (mode == 'CBC') ? CBCBlockCipher(aesEngine) : aesEngine;
    final paddedCipher = PaddedBlockCipherImpl(PKCS7Padding(), blockCipher);

    final params = (mode == 'CBC')
        ? PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
            ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), ivBytes!), null)
        : PaddedBlockCipherParameters<KeyParameter, Null>(KeyParameter(keyBytes), null);

    paddedCipher.init(isEncrypt, params);
    return paddedCipher.process(input);
  }

  static Uint8List _processRawCipher(Uint8List input, bool isEncrypt, String mode, Uint8List keyBytes,
      Uint8List? ivBytes, AESEngine aesEngine) {
    final BlockCipher cipher = (mode == 'CBC') ? CBCBlockCipher(aesEngine) : aesEngine;

    final CipherParameters params = (mode == 'CBC')
        ? ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), ivBytes!)
        : KeyParameter(keyBytes);

    cipher.init(isEncrypt, params);

    if (input.length % cipher.blockSize != 0) {
      throw ArgumentError('Input length must be multiple of block size (${cipher.blockSize}) for raw AES processing');
    }

    final out = Uint8List(input.length);
    var offset = 0;
    while (offset < input.length) {
      final processed = cipher.process(input.sublist(offset, offset + cipher.blockSize));
      out.setRange(offset, offset + processed.length, processed);
      offset += cipher.blockSize;
    }
    return out;
  }

  // Decode key or iv string that may be prefixed with 'base64:' or be plain text
  static Uint8List _decodeKeyStringToBytes(String s) {
    if (s.startsWith('base64:')) {
      final b64 = s.substring(7);
      try {
        return Uint8List.fromList(base64.decode(b64));
      } catch (_) {
        // fallback to utf8 bytes of the full string
        return Uint8List.fromList(utf8.encode(s));
      }
    }

    // default: treat as plain text
    return Uint8List.fromList(utf8.encode(s));
  }

}