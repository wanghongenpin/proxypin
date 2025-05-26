import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class AesUtils {
  static Uint8List encrypt(Uint8List input,
      {required String key, required int keyLength, required String mode, required String padding, String? iv}) {
    return process(input, true, key: key, keyLength: keyLength, mode: mode, padding: padding, iv: iv);
  }

  static Uint8List decrypt(Uint8List input,
      {required String key, required int keyLength, required String mode, required String padding, String? iv}) {
    var data = process(input, false, key: key, keyLength: keyLength, mode: mode, padding: padding, iv: iv);
    // 移除填充零字节
    if (padding == 'ZeroPadding') {
      int lastNonZeroIndex = data.lastIndexWhere((byte) => byte != 0);
      data = data.sublist(0, lastNonZeroIndex + 1);
    }
    return data;
  }

  static Uint8List process(Uint8List input, bool isEncrypt,
      {required String key, required int keyLength, required String mode, required String padding, String? iv}) {
    int keySize = keyLength ~/ 8;

    final aesKey = Uint8List.fromList(utf8.encode(key.padRight(keySize, '0')));
    final aesIv = mode == 'CBC' ? Uint8List.fromList(utf8.encode(iv!.padRight(keySize, '0'))) : null;

    BlockCipher cipher = BlockCipher(mode == 'CBC' ? 'AES/CBC' : 'AES/ECB');
    CipherParameters params =
        aesIv == null ? KeyParameter(aesKey) : ParametersWithIV<KeyParameter>(KeyParameter(aesKey), aesIv);

    if (padding == 'PKCS7') {
      cipher = PaddedBlockCipherImpl(PKCS7Padding(), cipher);
      params = PaddedBlockCipherParameters<CipherParameters, CipherParameters>(params, null);
    }

    // 检查输入长度是否为块大小的整数倍
    if (input.length % cipher.blockSize != 0 && padding == 'ZeroPadding') {
      input = Uint8List.fromList(input + Uint8List(cipher.blockSize - (input.length % cipher.blockSize)));
    }

    cipher.init(isEncrypt, params);
    return cipher.process(input);
  }
}
