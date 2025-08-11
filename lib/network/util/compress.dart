import 'dart:io';
import 'dart:typed_data';

import 'package:brotli/brotli.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:zstandard/zstandard.dart';

///GZIP 解压缩
List<int> gzipDecode(List<int> byteBuffer) {
  GZipCodec gzipCodec = GZipCodec();
  try {
    return gzipCodec.decode(byteBuffer);
  } catch (e) {
    logger.e("gzipDecode error: $e");
    return byteBuffer;
  }
}

///GZIP 压缩
List<int> gzipEncode(List<int> input) {
  return GZipCodec().encode(input);
}

///GZIP magic check
bool isGzip(List<int> input) {
  return input.length >= 2 && input[0] == 0x1F && input[1] == 0x8B;
}

///br 解压缩
List<int> brDecode(List<int> byteBuffer) {
  try {
    return brotli.decode(byteBuffer);
  } catch (e) {
    logger.e("brDecode error: $e");
    return byteBuffer;
  }
}

///zstd 解压缩
Future<List<int>?> zstdDecode(List<int> byteBuffer) async {
  final zstandard = Zstandard();
  try {
    return zstandard.decompress(Uint8List.fromList(byteBuffer));
  } catch (e) {
    logger.e("zstdDecode error: $e");
    return byteBuffer;
  }
}
