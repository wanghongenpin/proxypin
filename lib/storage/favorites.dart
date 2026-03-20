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
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/path.dart';
import 'package:proxypin/utils/har.dart';

/// 收藏存储
/// @author WangHongEn
class FavoriteStorage {
  static Queue<Favorite>? list;

  // Keep only recent websocket/sse messages per favorite to control favorites.json size.
  static const int maxWebSocketMessagesPerFavorite = 200;
  static const int maxWebSocketPayloadBytesPerFavorite = 1 * 1024 * 1024; //  1 MB

  static Function()? addNotifier;

  /// 获取收藏列表
  static Future<Queue<Favorite>> get favorites async {
    if (list == null) {
      list = ListQueue();
      var file = await Paths.getPath("favorites.json");
      if (await file.exists()) {
        var value = await file.readAsString();
        if (value.isEmpty) {
          return list!;
        }
        try {
          var config = jsonDecode(value) as List<dynamic>;
          for (var element in config) {
            list?.add(Favorite.fromJson(element));
          }
        } catch (e, t) {
          logger.e('收藏列表解析失败', error: e, stackTrace: t);
        }
      }
    }
    return list!;
  }

  /// 添加收藏
  static Future<void> addFavorite(HttpRequest request) async {
    var favorites = await FavoriteStorage.favorites;
    if (favorites.any((element) => element.request.requestId == request.requestId)) {
      return;
    }

    // Snapshot to avoid mutating the live request/response when trimming persisted messages.
    final favorite = _snapshotFavorite(request);
    trimFavoriteMessages(favorite);
    favorites.addFirst(favorite);
    flushConfig();
    //通知
    addNotifier?.call();
  }

  static Favorite _snapshotFavorite(HttpRequest request) {
    final copiedRequest = request.copy();
    final copiedResponse = request.response?.copy();
    return Favorite(copiedRequest, response: copiedResponse);
  }

  static Future<void> removeFavorite(Favorite favorite) async {
    var list = await favorites;
    list.remove(favorite);
    flushConfig();
  }

  //刷新配置
  static Future<void> flushConfig() async {
    var list = await favorites;
    await Paths.getPath("favorites.json").then((file) => file.writeAsString(toJson(list)));
  }

  static String toJson(Queue<Favorite> list) {
    return jsonEncode(list.map((e) => e.toJson()).toList());
  }

  /// Export all favorites to a given file path
  static Future<void> exportToFile(String path) async {
    var current = await favorites;
    var content = toJson(current);
    await File(path).writeAsString(content, flush: true);
  }

  /// Export all favorites as HAR to a given file path
  static Future<void> exportToHarFile(String path, {String title = 'Favorites'}) async {
    var current = await favorites;
    final requests = current.map((f) => f.request).toList(growable: false);
    await Har.writeFile(requests, File(path), title: title);
  }

  /// Import favorites from a JSON or HAR file (merges with current list, de-duping by requestId)
  static Future<void> importFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('File not found');
    }

    final lower = path.toLowerCase();
    List<Favorite> imported;
    if (lower.endsWith('.har')) {
      // HAR import
      final requests = await Har.readFile(file);
      imported = requests.map((r) => Favorite(r)).toList(growable: false);
    } else {
      // JSON import (old format)
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return;
      }
      final decoded = jsonDecode(content) as List<dynamic>;
      imported = decoded.map((e) => Favorite.fromJson(e as Map<String, dynamic>)).toList(growable: false);
    }

    final current = await favorites;
    final existingIds = current.map((e) => e.request.requestId).toSet();

    // Merge without replacing current entries; skip duplicates by requestId
    for (var fav in imported.reversed) {
      final rid = fav.request.requestId;
      if (existingIds.contains(rid)) {
        continue;
      }
      trimFavoriteMessages(fav);
      existingIds.add(rid);
      current.addFirst(fav);
    }

    await flushConfig();
    addNotifier?.call();
  }

  static bool trimFavoriteMessages(Favorite favorite) {
    final response = favorite.response;
    final requestFrames = List.of(favorite.request.messages);
    final responseFrames = List.of(response?.messages ?? const []);

    if (requestFrames.isEmpty && responseFrames.isEmpty) {
      return false;
    }

    final refs = <_FrameRef>[
      ...requestFrames.map((e) => _FrameRef(isRequest: true, frame: e)),
      ...responseFrames.map((e) => _FrameRef(isRequest: false, frame: e)),
    ]..sort((a, b) => a.frame.time.compareTo(b.frame.time));

    final totalBytes = refs.fold<int>(0, (sum, e) => sum + e.frame.payloadData.length);
    if (refs.length <= maxWebSocketMessagesPerFavorite && totalBytes <= maxWebSocketPayloadBytesPerFavorite) {
      return false;
    }

    final kept = <_FrameRef>[];
    int keptBytes = 0;
    for (int i = refs.length - 1; i >= 0; i--) {
      final ref = refs[i];
      final bytes = ref.frame.payloadData.length;
      final hitCount = kept.length >= maxWebSocketMessagesPerFavorite;
      final hitBytes = kept.isNotEmpty && (keptBytes + bytes > maxWebSocketPayloadBytesPerFavorite);
      if (hitCount || hitBytes) {
        continue;
      }
      kept.add(ref);
      keptBytes += bytes;
      if (kept.length >= maxWebSocketMessagesPerFavorite) {
        break;
      }
    }

    kept.sort((a, b) => a.frame.time.compareTo(b.frame.time));
    favorite.request.messages = kept.where((e) => e.isRequest).map((e) => e.frame).toList(growable: false);
    response?.messages = kept.where((e) => !e.isRequest).map((e) => e.frame).toList(growable: false);
    return true;
  }
}

class _FrameRef {
  final bool isRequest;
  final WebSocketFrame frame;

  _FrameRef({required this.isRequest, required this.frame});
}

class Favorite {
  String? name;
  final HttpRequest request;
  HttpResponse? response;

  Favorite(this.request, {this.name, this.response}) {
    response ??= request.response;
    request.response = response;
    response?.request = request;
  }

  factory Favorite.fromJson(Map<String, dynamic> json) {
    return Favorite(HttpRequest.fromJson(json['request']),
        name: json['name'], response: json['response'] == null ? null : HttpResponse.fromJson(json['response']));
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'request': request.toJson(),
      'response': response?.toJson(),
    };
  }

  int get websocketMessageCount => request.messages.length + (response?.messages.length ?? 0);
}
