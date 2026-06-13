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
  } catch (e, stackTrace) {
    logger.e("gzipDecode error, inputLength=${byteBuffer.length}", error: e, stackTrace: stackTrace);
    return byteBuffer;
  }
}

///GZIP 压缩
List<int> gzipEncode(List<int> input) {
  return GZipCodec().encode(input);
}

///br 解压缩
List<int> brDecode(List<int> byteBuffer) {
  try {
    return brotli.decode(byteBuffer);
  } catch (e, stackTrace) {
    logger.e("brDecode error, inputLength=${byteBuffer.length}", error: e, stackTrace: stackTrace);
    return byteBuffer;
  }
}

///zstd 解压缩
Future<List<int>?> zstdDecode(List<int> byteBuffer) async {
  final zstandard = Zstandard();
  try {
    return zstandard.decompress(Uint8List.fromList(byteBuffer));
  } catch (e, stackTrace) {
    logger.e("zstdDecode error, inputLength=${byteBuffer.length}", error: e, stackTrace: stackTrace);
    return byteBuffer;
  }
}


///zlib
List<int> zlibDecode(List<int> byteBuffer) {
  try {
    final rawDeflateDecoder = ZLibDecoder(raw: true);
    return rawDeflateDecoder.convert(byteBuffer);
  } catch (e, stackTrace) {
    logger.e("zlibDecode error, inputLength=${byteBuffer.length}", error: e, stackTrace: stackTrace);
    return byteBuffer;
  }
}