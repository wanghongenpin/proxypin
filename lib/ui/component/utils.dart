/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';

import '../../utils/platform.dart';

const contentMap = {
  ContentType.json: Icons.data_object,
  ContentType.html: Icons.html,
  ContentType.js: Icons.javascript,
  ContentType.image: Icons.image,
  ContentType.video: Icons.video_call,
  ContentType.text: Icons.text_fields,
  ContentType.css: Icons.css,
  ContentType.font: Icons.font_download,
};

Widget getIcon(HttpResponse? response, {Color? color}) {
  if (response == null) {
    return SizedBox(width: 18, child: Icon(Icons.question_mark, size: 16, color: color ?? Colors.green));
  }
  if (response.status.code < 0) {
    return SizedBox(width: 18, child: Icon(Icons.error, size: 16, color: color ?? Colors.red));
  }

  var contentType = response.contentType;
  if (contentType.isImage && response.body != null) {
    return Image.memory(
      Uint8List.fromList(response.body!),
      width: Platforms.isDesktop() ? 19 : 26,
      errorBuilder: (context, error, stackTrace) => Icon(Icons.image, size: 16, color: color ?? Colors.green),
    );
  }
  return SizedBox(
      width: 18, child: Icon(contentMap[contentType] ?? Icons.http, size: 16, color: color ?? Colors.green));
}

//展示报文大小
String getPackagesSize(HttpRequest request, HttpResponse? response) {
  var package = getPackage(request.packageSize);
  var responsePackage = getPackage(response?.packageSize);
  if (responsePackage.isEmpty) {
    return package;
  }
  return "$package / $responsePackage ";
}

String getPackage(int? size) {
  if (size == null) {
    return "";
  }
  if (size < 1025) {
    return "$size B";
  }

  if (size > 1024 * 1024) {
    return "${(size / 1024 / 1024).toStringAsFixed(2)} MB";
  }
  return "${(size / 1024).toStringAsFixed(2)} KB";
}

String copyRawRequest(HttpRequest request) {
  var sb = StringBuffer();
  var uri = request.requestUri!;
  var pathAndQuery = uri.path + (uri.query.isNotEmpty ? '?${uri.query}' : '');

  sb.writeln("${request.method.name} $pathAndQuery ${request.protocolVersion}");
  sb.write(request.headers.headerLines());
  if (request.bodyAsString.isNotEmpty) {
    sb.writeln();
    sb.write(request.bodyAsString);
  }
  return sb.toString();
}

String copyRequest(HttpRequest request, HttpResponse? response) {
  var sb = StringBuffer();
  sb.writeln("Request");
  sb.writeln("${request.method.name} ${request.requestUrl} ${request.protocolVersion}");
  sb.writeln(request.headers.headerLines());
  sb.writeln();
  sb.writeln(request.bodyAsString);

  sb.writeln("--------------------------------------------------------");
  sb.writeln();
  sb.writeln("Response");
  sb.writeln("${response?.protocolVersion} ${response?.status.code}");
  sb.writeln(response?.headers.headerLines());
  sb.writeln(response?.bodyAsString);
  return sb.toString();
}

RelativeRect menuPosition(BuildContext context) {
  final RenderBox bar = context.findRenderObject() as RenderBox;
  final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  const Offset offset = Offset.zero;
  final RelativeRect position = RelativeRect.fromRect(
    Rect.fromPoints(
      bar.localToGlobal(bar.size.centerRight(offset), ancestor: overlay),
      bar.localToGlobal(bar.size.centerRight(offset), ancestor: overlay),
    ),
    offset & overlay.size,
  );
  return position;
}

Widget contextMenu(BuildContext context, EditableTextState editableTextState, {ContextMenuButtonItem? customItem}) {
  List<ContextMenuButtonItem> list = [
    ContextMenuButtonItem(
      onPressed: () {
        editableTextState.copySelection(SelectionChangedCause.tap);

        FlutterToastr.show(AppLocalizations.of(context)!.copied, context);
        unSelect(editableTextState);
        editableTextState.hideToolbar();
      },
      type: ContextMenuButtonType.copy,
    ),
    ContextMenuButtonItem(
      label: Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh') ? '复制值' : 'Copy Value',
      onPressed: () {
        unSelect(editableTextState);
        Clipboard.setData(ClipboardData(text: editableTextState.textEditingValue.text)).then((value) {
          if (context.mounted) FlutterToastr.show(AppLocalizations.of(context)!.copied, context);
          editableTextState.hideToolbar();
        });
      },
      type: ContextMenuButtonType.custom,
    ),
    ContextMenuButtonItem(
      onPressed: () {
        editableTextState.selectAll(SelectionChangedCause.tap);
      },
      type: ContextMenuButtonType.selectAll,
    ),
  ];

  if (customItem != null) {
    list.add(customItem);
  }

  if (Platform.isIOS) {
    list.add(ContextMenuButtonItem(
      onPressed: () async {
        editableTextState.shareSelection(SelectionChangedCause.toolbar);
      },
      type: ContextMenuButtonType.share,
    ));
  }

  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: list,
  );
}

void unSelect(EditableTextState editableTextState) {
  editableTextState.userUpdateTextEditingValue(
    editableTextState.textEditingValue.copyWith(selection: const TextSelection(baseOffset: 0, extentOffset: 0)),
    SelectionChangedCause.tap,
  );
}

///Future
Widget futureWidget<T>(Future<T> future, Widget Function(T data) toWidget, {T? initialData, bool loading = false}) {
  return FutureBuilder<T>(
    future: future,
    initialData: initialData,
    builder: (BuildContext context, AsyncSnapshot<T> snapshot) {
      if (snapshot.data != null) {
        return toWidget(snapshot.requireData);
      }

      if (snapshot.connectionState == ConnectionState.done) {
        if (snapshot.hasError) {
          logger.e(snapshot.error);
        }
        return toWidget(snapshot.requireData);
      }
      //加载效果
      return loading ? const Center(child: CircularProgressIndicator()) : const SizedBox();
    },
  );
}

Future showContextMenu(BuildContext context, Offset offset, {required List<PopupMenuEntry> items}) {
  return showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx + 10,
        offset.dy - 50,
        offset.dx + 10,
        offset.dy - 50,
      ),
      items: items);
}

Future<T?> showConfirmDialog<T>(BuildContext context, {String? title, String? content, VoidCallback? onConfirm}) {
  title ??= AppLocalizations.of(context)!.confirmTitle;
  content ??= AppLocalizations.of(context)!.confirmContent;
  return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: Text(content!),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                if (onConfirm != null) onConfirm();
              },
              child: Text(AppLocalizations.of(context)!.confirm),
            ),
          ],
        );
      });
}

///滚动条
ScrollController? trackingScroll(ScrollController? scrollController) {
  if (scrollController == null) {
    return null;
  }

  var trackingScroll = TrackingScrollController();
  double offset = 0;
  trackingScroll.addListener(() {
    if (trackingScroll.offset < 30 && trackingScroll.offset < offset && scrollController.offset > 0) {
      //往上滚动
      scrollController.jumpTo(scrollController.offset - max(offset - trackingScroll.offset, 15));
    } else if (trackingScroll.offset > 0 &&
        trackingScroll.offset > offset &&
        scrollController.offset < scrollController.position.maxScrollExtent) {
      //往下滚动
      scrollController.jumpTo(scrollController.offset + max(trackingScroll.offset - offset, 15));
    }

    offset = trackingScroll.offset;
  });
  return trackingScroll;
}
