import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/utils/har.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:share_plus/share_plus.dart';

enum ExportType {
  request,
  response,
  requestResponse,
  har,
}

void exportRequest(HttpRequest request) async {
  String fileName = "request_${request.hostAndPort?.host}_${request.requestId}.txt";
  var json = copyRawRequest(request);

  var path = await FilePicker.saveFile(fileName: fileName, bytes: utf8.encode(json));
  logger.d("Export request to $path");
}

void exportRequestBody(HttpRequest request) async {
  String fileName = "request_body_${request.hostAndPort?.host}_${request.requestId}.txt";

  var path = await FilePicker.saveFile(
      fileName: fileName, bytes: request.body == null ? Uint8List(0) : Uint8List.fromList(request.body!));
  logger.d("Export request body to $path");
}

void exportResponse(HttpResponse? response) async {
  if (response == null) {
    logger.d("No response to export");
    return;
  }

  String fileName = "response_${response.request?.hostAndPort?.host}_${response.requestId}.txt";
  var json = await copyRawResponse(response);
  var path = await FilePicker.saveFile(fileName: fileName, bytes: utf8.encode(json));
  logger.d("Export response to $path");
}

void exportResponseBody(HttpResponse? response) async {
  if (response == null) {
    return;
  }

  String fileName = "response_body_${response.request?.hostAndPort?.host}_${response.requestId}.txt";

  var path = await FilePicker.saveFile(
      fileName: fileName, bytes: response.body == null ? Uint8List(0) : Uint8List.fromList(response.body!));
  logger.d("Export response body to $path");
}

void exportRequestAndResponse(HttpRequest request, HttpResponse? response) async {
  String fileName = "request_response_${request.hostAndPort?.host ?? ''}_${request.requestId}.txt";

  var json = copyRequest(request, response);
  var path = await FilePicker.saveFile(fileName: fileName, bytes: utf8.encode(json));
  logger.d("Export request and response to $path");
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

  var path = await FilePicker.saveFile(fileName: fileName, bytes: utf8.encode(json));
  logger.d("Export har to $path");
}

/// Export response to string with decoded body
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

/// 生成单个请求的导出文件内容（bytes）
/// 返回 Map: { 'fileName': String, 'bytes': Uint8List }
Future<Map<String, dynamic>?> generateExportFileData(
  HttpRequest request,
  ExportType type,
  int index,
) async {
  var host = request.hostAndPort?.host ?? 'unknown';
  var safeHost = host.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  var prefix = '${index + 1}_$safeHost';

  switch (type) {
    case ExportType.request:
      var content = copyRawRequest(request);
      return {
        'fileName': '${prefix}_request.txt',
        'bytes': utf8.encode(content),
      };
    case ExportType.response:
      if (request.response == null) return null;
      var content = await copyRawResponse(request.response!);
      return {
        'fileName': '${prefix}_response.txt',
        'bytes': utf8.encode(content),
      };
    case ExportType.requestResponse:
      var content = copyRequest(request, request.response);
      return {
        'fileName': '${prefix}_request_response.txt',
        'bytes': utf8.encode(content),
      };
    case ExportType.har:
      return null;
  }
}

/// 批量导出请求 - 桌面端和手机端采用不同策略
/// [requests] 请求列表
/// [folderName] 文件夹名称/文件名前缀
/// [type] 导出类型
/// [context] 上下文
/// [onSuccess] 成功回调，参数为成功导出的文件数
Future<void> exportRequestsAsFiles(
  List<HttpRequest> requests,
  String folderName,
  ExportType type, {
  required BuildContext context,
  Function(int successCount)? onSuccess,
}) async {
  try {
    int successCount = 0;

    final isDesktop = Platforms.isDesktop();
    if (isDesktop || Platform.isAndroid) {
      String? selectedDirectory;

      if (isDesktop) {
        selectedDirectory = await FilePicker.saveFile(
                fileName: folderName, type: FileType.custom, allowedExtensions: [''], bytes: Uint8List(0))
            .then((path) => path != null ? "${Directory(path).parent.path}/$folderName" : null);
      } else {
        selectedDirectory = await FilePicker.getDirectoryPath();
      }
      if (selectedDirectory == null) return;

      // 创建主文件夹
      final folder = Directory(selectedDirectory);
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      for (var i = 0; i < requests.length; i++) {
        try {
          var request = requests[i];
          var host = request.hostAndPort?.host ?? 'unknown';
          var safeHost = host.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
          var prefix = '${i + 1}_$safeHost';

          switch (type) {
            case ExportType.request:
              var content = copyRawRequest(request);
              var file = File('${folder.path}/${prefix}_request.txt');
              await file.writeAsString(content);
              break;
            case ExportType.response:
              if (request.response != null) {
                var content = await copyRawResponse(request.response!);
                var file = File('${folder.path}/${prefix}_response.txt');
                await file.writeAsString(content);
              }
              break;
            case ExportType.requestResponse:
              var content = copyRequest(request, request.response);
              var file = File('${folder.path}/${prefix}_request_response.txt');
              await file.writeAsString(content);
              break;
            case ExportType.har:
              // Handled separately
              break;
          }
          successCount++;
        } catch (e) {
          logger.e('Export error: $e');
        }
      }
    } else {
      // 创建所有文件
      List<XFile> files = [];
      for (var i = 0; i < requests.length; i++) {
        var request = requests[i];
        var data = await generateExportFileData(request, type, i);
        if (data == null) continue;

        files.add(XFile.fromData(data['bytes'] as Uint8List, name: data['fileName'], mimeType: 'text/plain'));
        successCount++;
      }

      RenderBox? box;
      if (await Platforms.isIpad() && context.mounted) {
        box = context.findRenderObject() as RenderBox?;
      }
      await SharePlus.instance.share(ShareParams(
          fileNameOverrides: files.map((f) => f.name).toList(),
          files: files,
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size));
    }

    onSuccess?.call(successCount);
  } catch (e, st) {
    logger.e('Export error: ', error: e, stackTrace: st);
    if (context.mounted) FlutterToastr.show('${AppLocalizations.of(context)?.exportFailed}: $e', context);
  }
}

/// 导出 HAR 文件
Future<void> exportHarFile(
  List<HttpRequest> requests,
  String fileName, {
  required BuildContext context,
  VoidCallback? onSuccess,
  Function(dynamic error)? onError,
}) async {
  try {
    var json = await Har.writeJson(requests, title: fileName);
    var bytes = utf8.encode(json);

    if (Platforms.isDesktop() || Platform.isAndroid) {
      await FilePicker.saveFile(fileName: fileName, bytes: bytes);
    } else {
      RenderBox? box;
      if (await Platforms.isIpad() && context.mounted) {
        box = context.findRenderObject() as RenderBox?;
      }

      logger.d("Export HAR file: $fileName, size: ${bytes.length} bytes");
      await SharePlus.instance.share(ShareParams(
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
          fileNameOverrides: [fileName],
          files: [XFile.fromData(bytes, name: fileName, mimeType: "application/json")]));
    }

    onSuccess?.call();
  } catch (e) {
    logger.e('Export HAR error: $e');
    onError?.call(e);
  }
}

/// 显示导出格式选择对话框
/// [ctx] 上下文
/// [requests] 请求列表
/// [folderName] 导出文件夹/文件名前缀
/// [onExportSuccess] 导出成功回调（一般用于清除选择状态）
void showExportDialog(
  BuildContext ctx,
  List<HttpRequest> requests,
  String folderName, {
  VoidCallback? onExportSuccess,
}) {
  final localizations = AppLocalizations.of(ctx)!;

  showDialog(
    context: ctx,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(localizations.export),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(localizations.request),
              onTap: () {
                Navigator.pop(context);
                exportRequestsAsFiles(
                  requests,
                  '${folderName}_request',
                  ExportType.request,
                  context: ctx,
                  onSuccess: (count) {
                    onExportSuccess?.call();
                    if (ctx.mounted) {
                      FlutterToastr.show('${localizations.exportSuccess}: $count ${localizations.request}', ctx);
                    }
                  },
                );
              },
            ),
            ListTile(
              title: Text(localizations.response),
              onTap: () {
                Navigator.pop(context);
                exportRequestsAsFiles(
                  requests,
                  '${folderName}_response',
                  ExportType.response,
                  context: ctx,
                  onSuccess: (count) {
                    onExportSuccess?.call();
                    if (ctx.mounted) {
                      FlutterToastr.show('${localizations.exportSuccess}: $count ${localizations.request}', ctx);
                    }
                  },
                );
              },
            ),
            ListTile(
              title: Text(localizations.requestResponse),
              onTap: () {
                Navigator.pop(context);
                exportRequestsAsFiles(
                  requests,
                  '${folderName}_request_response',
                  ExportType.requestResponse,
                  context: ctx,
                  onSuccess: (count) {
                    onExportSuccess?.call();
                    if (ctx.mounted) {
                      FlutterToastr.show('${localizations.exportSuccess}: $count ${localizations.request}', ctx);
                    }
                  },
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('HAR'),
              onTap: () {
                Navigator.pop(context);
                exportHarFile(
                  requests,
                  '$folderName.har',
                  context: ctx,
                  onSuccess: () {
                    onExportSuccess?.call();
                    if (ctx.mounted) {
                      FlutterToastr.show(localizations.exportSuccess, ctx);
                    }
                  },
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.cancel),
          ),
        ],
      );
    },
  );
}
