import 'dart:math';

class RandomUtil {
  static const _characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  // 复用同一个 Random 实例。每次 new Random() 会以当前时间作为种子，
  // 同一时间片(如 HTTP/2 一次解码中连续创建多个请求)内会得到相同种子、相同序列，
  // 导致 requestId 等随机串重复。
  static final Random _random = Random();

  static String randomString(int length) {
    return String.fromCharCodes(Iterable.generate(
      length,
      (_) => _characters.codeUnitAt(_random.nextInt(_characters.length)),
    ));
  }
}
