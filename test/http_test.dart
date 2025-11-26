import 'dart:io';

Future<void> main() async {
  var contentType = ContentType.parse("application/json");
  print(contentType);
  print(contentType.charset);
  print(Uri.parse("https://www.v2ex.com").scheme);
  // await socketTest();
  await webTest();
}

Future<void> webTest() async {

  var httpClient = HttpClient();
  httpClient.findProxy = (uri) => "PROXY 127.0.0.1:7890";
  // httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  var httpClientRequest = await httpClient.getUrl(Uri.parse("https://www.v2ex.com"));
  var response = await httpClientRequest.close();
  print(response.headers);
}
