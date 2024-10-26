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

import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/path.dart';

/// 收藏存储
/// @author WangHongEn
class FavoriteStorage {
  static Queue<Favorite>? list;

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
    if (favorites.any((element) => element.request == request)) {
      return;
    }

    favorites.addFirst(Favorite(request));
    flushConfig();
    //通知
    addNotifier?.call();
  }

  static Future<void> removeFavorite(Favorite favorite) async {
    var list = await favorites;
    list.remove(favorite);
    flushConfig();
  }

  //刷新配置
  static void flushConfig() async {
    var list = await favorites;
    Paths.getPath("favorites.json").then((file) => file.writeAsString(toJson(list)));
  }

  static String toJson(Queue<Favorite> list) {
    return jsonEncode(list.map((e) => e.toJson()).toList());
  }
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

  toJson() {
    return {
      'name': name,
      'request': request.toJson(),
      'response': response?.toJson(),
    };
  }
}
