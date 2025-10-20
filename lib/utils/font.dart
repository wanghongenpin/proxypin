import 'dart:io';

class Fonts {
  String thin = "PingFangSC-Thin";
  String light = "PingFangSC-Light";
  String regular = "PingFangSC-Regular";
  String medium = "PingFangSC-Medium";
  String semibold = "PingFangSC-Semibold";
  String bold = "PingFangSC-Bold";
}

class AppleFonts extends Fonts {
  @override
  String thin = "PingFangSC-Thin";
  @override
  String light = "PingFangSC-Light";
  @override
  String regular = "PingFang SC";

  @override
  var medium = "PingFangSC-Medium";
  @override
  var semibold = "PingFangSC-Semibold";
  @override
  String bold = "PingFangSC-Bold";
}

class WindowsFonts extends Fonts {
  String thin = "Microsoft YaHei UI Light";
  String light = "Microsoft YaHei UI Light";
  String regular = "Microsoft YaHei UI";
  String medium = "Microsoft YaHei UI";
  String semibold = "Microsoft YaHei UI Bold";
  String bold = "Microsoft YaHei UI Bold";
}

class AndroidFonts extends Fonts {
  String thin = "sans-serif-thin";
  String light = "sans-serif-light";
  String regular = "sans-serif";
  String medium = "sans-serif-medium";
  String semibold =
      "sans-serif-medium"; // Android doesn't have a specific semibold, using medium.
  String bold = "sans-serif-bold";
}

Fonts fonts = Platform.isAndroid
    ? AndroidFonts()
    : Platform.isWindows
        ? WindowsFonts()
        : AppleFonts();
