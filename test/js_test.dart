import 'package:flutter/material.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:proxypin/network/components/js/file.dart';
import 'package:proxypin/network/components/js/md5.dart';

// Convert JS request
// Map<String, dynamic> convertJsRequest(HttpRequest request) {
//   return {
//     'url': request.requestUrl,
//     'path': request.path(),
//     'headers': request.headers.toMap(),
//     'method': request.method.name,
//     'body': request.bodyAsString
//   };
// }

main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var flutterJs = getJavascriptRuntime();
  Md5Bridge.registerMd5(flutterJs);
  FileBridge.registerFile(flutterJs);

  // var httpRequest = HttpRequest(HttpMethod.get, "https://www.v2ex.com");
  // httpRequest.headers.set('user-agent', 'Dart/3.0 (dart:io)');

  const code = """
    var context ='test';
    var d = md5('value');
    console.log(d);
    var file = File('/Users/wanghongen/Downloads/test.html');
    console.log(file.path);
    // console.log(file.readAsStringSync());
   
    async function onRequest() {
       await file.writeAsString('await');
    
       var text = await file.readAsString();
       console.log(text);
       File('/Users/wanghongen/Downloads/test.txt').create();
    }
    onRequest();
  """;

  // var jsRequest = jsonEncode(convertJsRequest(httpRequest));

  var evaluate = await flutterJs.evaluateAsync(code);
  // print(evaluate.stringResult);
  await flutterJs.handlePromise(evaluate);
  flutterJs.dartContext.clear();
  flutterJs.localContext.clear();
  flutterJs.evaluate('console.log(context)');
}
