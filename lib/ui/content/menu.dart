import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/storage/favorites.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/utils/curl.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:share_plus/share_plus.dart';

import '../../utils/export_request.dart';
import '../../utils/python.dart';
import '../component/widgets.dart';
import '../mobile/menu/bottom_navigation.dart';
import '../mobile/request/request_editor.dart';
import '../mobile/setting/request_map.dart';

///分享按钮
class ShareWidget extends StatelessWidget {
  final ProxyServer? proxyServer;
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
            onTap: () async {
              if (request == null) {
                FlutterToastr.show("Request is empty", context);
                return;
              }
              if (context.mounted) {
                SharePlus.instance.share(ShareParams(
                  text: request!.requestUrl,
                  subject: localizations.proxyPinSoftware,
                  sharePositionOrigin: await _sharePositionOrigin(context),
                ));
              }
            },
          ),
          PopupMenuItem(
              padding: const EdgeInsets.only(left: 10, right: 2),
              child: Text(localizations.shareRequestResponse),
              onTap: () async {
                if (request == null) {
                  FlutterToastr.show("Request is empty", context);
                  return;
                }
                var file = XFile.fromData(utf8.encode(copyRequest(request!, response)),
                    name: localizations.captureDetail, mimeType: "txt");

                if (context.mounted) {
                  SharePlus.instance.share(ShareParams(
                    files: [file],
                    fileNameOverrides: ['request.txt'],
                    text: localizations.proxyPinSoftware,
                    sharePositionOrigin: await _sharePositionOrigin(context),
                  ));
                }
              }),
          PopupMenuItem(
              padding: const EdgeInsets.only(left: 10, right: 2),
              child: Text(localizations.shareCurl),
              onTap: () async {
                if (request == null) {
                  return;
                }
                var text = curlRequest(request!);
                var file = XFile.fromData(utf8.encode(text), name: "cURL.txt", mimeType: "txt");

                if (context.mounted) {
                  SharePlus.instance.share(ShareParams(
                    files: [file],
                    fileNameOverrides: ["cURL.txt"],
                    text: localizations.proxyPinSoftware,
                    sharePositionOrigin: await _sharePositionOrigin(context),
                  ));
                }
              }),
        ];
      },
    );
  }

  Future<Rect?> _sharePositionOrigin(BuildContext context) async {
    RenderBox? box;
    if (await Platforms.isIpad() && context.mounted) {
      box = context.findRenderObject() as RenderBox?;
    }
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }
}

class DetailMenuWidget extends StatelessWidget {
  final HttpRequest? request;

  const DetailMenuWidget({
    super.key,
    this.request,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return PopupMenuButton(
        offset: const Offset(0, 30),
        padding: const EdgeInsets.all(0),
        itemBuilder: (context) => [
              PopupMenuItem(
                  child: Text(localizations.favorite),
                  onTap: () {
                    if (request == null) return;

                    FavoriteStorage.addFavorite(request!);
                    FlutterToastr.show(localizations.addSuccess, context);
                  }),
              PopupMenuItem(
                  child: Text(localizations.save),
                  onTap: () {
                    if (request == null) return;

                    showDialog(
                        context: context,
                        builder: (menuContext) {
                          return AlertDialog(
                              title: Text(localizations.save),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    ListTile(
                                      visualDensity: const VisualDensity(vertical: -3),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                      title: Text(localizations.request),
                                      onTap: () {
                                        Navigator.of(menuContext).pop();
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          exportRequest(request!);
                                        });
                                      },
                                    ),
                                    ListTile(
                                      visualDensity: const VisualDensity(vertical: -3),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                      title: Text(localizations.requestBody),
                                      onTap: () {
                                        Navigator.of(menuContext).pop();
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          exportRequestBody(request!);
                                        });
                                      },
                                    ),
                                    ListTile(
                                      visualDensity: const VisualDensity(vertical: -3),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                      title: Text(localizations.response),
                                      onTap: () {
                                        Navigator.of(menuContext).pop();
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          exportResponse(request?.response);
                                        });
                                      },
                                    ),
                                    ListTile(
                                      visualDensity: const VisualDensity(vertical: -3),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                      title: Text(localizations.responseBody),
                                      onTap: () {
                                        Navigator.of(menuContext).pop();
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          exportResponseBody(request?.response);
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ));
                        });
                  }),
              PopupMenuItem(
                  child: Text(localizations.requestEdit),
                  onTap: () {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) =>
                              MobileRequestEditor(request: request, proxyServer: ProxyServer.current)));
                    });
                  }),
              PopupMenuItem(
                  child: Text(localizations.requestMap),
                  onTap: () {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      navigator(
                          context, MobileRequestMapEdit(url: request?.domainPath, title: request?.hostAndPort?.host));
                    });
                  }),
              CustomPopupMenuItem(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(localizations.copyRawRequest),
                  onTap: () {
                    if (request == null) return;

                    var text = copyRawRequest(request!);
                    Clipboard.setData(ClipboardData(text: text));
                    FlutterToastr.show(localizations.copied, context);
                  }),
              CustomPopupMenuItem(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(localizations.copyAsPythonRequests),
                  onTap: () {
                    if (request == null) return;

                    var text = copyAsPythonRequests(request!);
                    Clipboard.setData(ClipboardData(text: text));
                    FlutterToastr.show(localizations.copied, context);
                  })
            ],
        child: const SizedBox(height: 38, width: 38, child: Icon(Icons.more_vert, size: 28)));
  }
}
