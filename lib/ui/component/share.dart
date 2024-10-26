import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/utils/curl.dart';
import 'package:share_plus/share_plus.dart';

///分享按钮
class ShareWidget extends StatelessWidget {
  final ProxyServer proxyServer;
  final HttpRequest? request;
  final HttpResponse? response;

  const ShareWidget({super.key, required this.proxyServer, this.request, this.response});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return PopupMenuButton(
      icon: const Icon(Icons.share, size: 24),
      offset: const Offset(0, 30),
      itemBuilder: (BuildContext context) {
        return [
          PopupMenuItem(
            padding: const EdgeInsets.only(left: 10, right: 2),
            child: Text(localizations.shareUrl),
            onTap: () {
              if (request == null) {
                FlutterToastr.show("Request is empty", context);
                return;
              }
              Share.share(request!.requestUrl, subject: localizations.proxyPinSoftware);
            },
          ),
          PopupMenuItem(
              padding: const EdgeInsets.only(left: 10, right: 2),
              child: Text(localizations.shareRequestResponse),
              onTap: () {
                if (request == null) {
                  FlutterToastr.show("Request is empty", context);
                  return;
                }
                var file = XFile.fromData(utf8.encode(copyRequest(request!, response)),
                    name: localizations.captureDetail, mimeType: "txt");
                Share.shareXFiles([file], fileNameOverrides: ['request.txt'], text: localizations.proxyPinSoftware);
              }),
          PopupMenuItem(
              padding: const EdgeInsets.only(left: 10, right: 2),
              child: Text(localizations.shareCurl),
              onTap: () {
                if (request == null) {
                  return;
                }
                var text = curlRequest(request!);
                var file = XFile.fromData(utf8.encode(text), name: "cURL.txt", mimeType: "txt");
                Share.shareXFiles([file], fileNameOverrides: ["cURL.txt"], text: localizations.proxyPinSoftware);
              }),
        ];
      },
    );
  }
}
