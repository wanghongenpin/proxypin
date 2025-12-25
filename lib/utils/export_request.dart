import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/utils/har.dart';

void exportRequest(HttpRequest request) async {
  String fileName = "request_${request.hostAndPort?.host}_${request.requestId}.txt";
  var json = copyRawRequest(request);

  var path = await FilePicker.platform.saveFile(fileName: fileName, bytes: utf8.encode(json));
  logger.d("Export request to $path");
}

void exportRequestBody(HttpRequest request) async {
  String fileName = "request_body_${request.hostAndPort?.host}_${request.requestId}.txt";

  var path = await FilePicker.platform
      .saveFile(fileName: fileName, bytes: request.body == null ? null : Uint8List.fromList(request.body!));
  logger.d("Export request body to $path");
}

void exportResponse(HttpResponse? response) async {
  if (response == null) {
    return;
  }

  String fileName = "response_${response.request?.hostAndPort?.host}_${response.requestId}.txt";

  Future<String> copyRawResponse(HttpResponse response) async {
    var sb = StringBuffer();
    sb.writeln("${response.protocolVersion} ${response.status.code} ${response.status.reasonPhrase}");
    sb.write(response.headers.headerLines());
    if (response.bodyAsString.isNotEmpty) {
      sb.writeln();
      sb.write(await response.decodeBodyString());
    }
    return sb.toString();
  }

  var json = await copyRawResponse(response);
  var path = await FilePicker.platform.saveFile(fileName: fileName, bytes: utf8.encode(json));
  logger.d("Export response to $path");
}

void exportResponseBody(HttpResponse? response) async {
  if (response == null) {
    return;
  }

  String fileName = "response_body_${response.request?.hostAndPort?.host}_${response.requestId}.txt";

  var path = await FilePicker.platform
      .saveFile(fileName: fileName, bytes: response.body == null ? null : Uint8List.fromList(response.body!));
  logger.d("Export response body to $path");
}

void exportHar(HttpRequest request) async {
  String fileName = "har_${request.hostAndPort?.host}_${request.requestId}.har";

  var entry = Har.toHar(request);
  print(entry);
  var har = {
    "log": {
      "version": "1.2",
      "creator": {"name": "ProxyPin", "version": AppConfiguration.version},
      "pages": [
        {
          "title": "ProxyPin Har Export",
          "id": "ProxyPin",
          "startedDateTime": request.requestTime.toUtc().toIso8601String(),
          "pageTimings": {"onContentLoad": -1, "onLoad": -1}
        }
      ],
      "entries": [entry],
    }
  };
  var json = jsonEncode(har);

  var path = await FilePicker.platform.saveFile(fileName: fileName, bytes: utf8.encode(json));
  logger.d("Export har to $path");
}
