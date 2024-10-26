import 'dart:io';

import 'package:proxypin/network/util/cert/pkcs12.dart';

void main() {
  File file = File('C:\\Users\\wanghongen\\Downloads\\new_key.p12');
  parsePKCS12([file], '01');

  List<File> files = [];
  files.add(File('C:\\Users\\wanghongen\\Downloads\\ProxyPinPkcs12.p12'));
  files.add(File('C:\\Users\\wanghongen\\Downloads\\proxyman.p12'));
  // files.add(File('C:\\Users\\wanghongen\\Downloads\\charles.p12'));
  parsePKCS12(files, '123');
}

void parsePKCS12(List<File> files, String password) {
  for (var file in files) {
    var bytes = file.readAsBytesSync();
    var decodePkcs12 = Pkcs12.parsePkcs12(bytes, password: password);

    print(decodePkcs12[0]);
    print(decodePkcs12[1]);
  }
}
