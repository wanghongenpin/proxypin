import 'dart:convert';
import 'dart:typed_data';

void main() {
  print(base64Decode("CiRjNjJlOTc0ZC1j"));
  print(utf8.decode(base64Decode("CiRjNjJlOTc0ZC1j")));
  // 输入的十六进制字符串
  String hex = "1F 8B 08 00 00 00 00 00 00 FF DD 58 CF";
  // 转换为Base64
  String base64Str = hexToBase64(hex);
  print("转换后的Base64: $base64Str");
}

String hexToBase64(String hex) {
  // 移除十六进制字符串中的空格
  var arr = hex.split(' ');
  // 将十六进制字符串转换为字节数组
  List<int> bytes = [];
  for (int i = 0; i < arr.length; i ++) {
    bytes.add(int.parse(arr[i], radix: 16));
  }
  print(bytes);
  // 将字节数组编码为 Base64
  return base64Encode(Uint8List.fromList(bytes));
}