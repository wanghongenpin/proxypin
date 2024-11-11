/*
 * Copyright Copyright 2024 Hongen Wang All rights reserved.
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

import 'package:proxypin/network/util/cache.dart';

///content type
///@author WangHongEn
enum ContentType {
  json,
  formUrl,
  formData,
  js,
  html,
  text,
  css,
  font,
  image,
  video,
  http;

  static ContentType valueOf(String name) {
    return ContentType.values.firstWhere((element) => element.name == name.toLowerCase(), orElse: () => http);
  }

  //是否是二进制
  bool get isBinary {
    return this == image || this == font || this == video;
  }
}

class MediaType {
  static const String wildcardType = "*/*";
  static LruCache<String, MediaType> cachedMediaTypes = LruCache(64);

  ///默认编码类型
  static List<MediaType> defaultCharsetMediaTypes = [
    MediaType("text", "plain", charset: "utf-8"),
    MediaType("text", "html", charset: "utf-8"),
    MediaType("text", "javascript", charset: "utf-8"),
    MediaType("text", "css", charset: "utf-8"),
    MediaType("application", "json", charset: "utf-8"),
    MediaType("application", "problem+json", charset: "utf-8"),
    MediaType("application", "xml", charset: "utf-8"),
    MediaType("application", "xhtml+xml", charset: "utf-8"),
    MediaType("application", "octet-stream", charset: "utf-16"),
    MediaType("image", "*", charset: "utf-16"),
  ];

  final String type;
  final String subtype;
  final Map<String, String> parameters;

  MediaType(this.type, this.subtype, {Map<String, String>? parameters, String? charset})
      : parameters = parameters ?? {} {
    if (charset != null) {
      this.parameters["charset"] = charset;
    }
  }

  factory MediaType.valueOf(String mediaType) {
    if (mediaType.isEmpty) {
      throw InvalidMediaTypeException(mediaType, "'mediaType' must not be empty");
    }
    // do not cache multipart mime types with random boundaries
    if (mediaType.startsWith("multipart")) {
      return _parseMediaTypeInternal(mediaType);
    }

    return cachedMediaTypes.pubIfAbsent(mediaType, () => _parseMediaTypeInternal(mediaType));
  }

  ///编码
  String? get charset {
    return parameters["charset"]?.toLowerCase();
  }

  ///获取默认编码
  static String? defaultCharset(MediaType mediaType) {
    for (var defaultMediaType in defaultCharsetMediaTypes) {
      if (defaultMediaType.equalsTypeAndSubtype(mediaType)) {
        return defaultMediaType.charset;
      }
    }
    return null;
  }

  static MediaType _parseMediaTypeInternal(String mediaType) {
    int index = mediaType.indexOf(';');
    String fullType = (index >= 0 ? mediaType.substring(0, index) : mediaType).trim();
    if (fullType.isEmpty) {
      throw InvalidMediaTypeException(mediaType, "'mediaType' must not be empty");
    }

    if (MediaType.wildcardType == fullType) {
      fullType = "*/*";
    }
    int subIndex = fullType.indexOf('/');
    if (subIndex == -1) {
      throw InvalidMediaTypeException(mediaType, "does not contain '/'");
    }
    if (subIndex == fullType.length - 1) {
      throw InvalidMediaTypeException(mediaType, "does not contain subtype after '/'");
    }
    String type = fullType.substring(0, subIndex);
    String subtype = fullType.substring(subIndex + 1);
    if (MediaType.wildcardType == type && MediaType.wildcardType != subtype) {
      throw InvalidMediaTypeException(mediaType, "wildcard type is legal only in '*/*' (all mime types)");
    }

    Map<String, String> parameters = {};
    do {
      int nextIndex = index + 1;
      bool quoted = false;
      while (nextIndex < mediaType.length) {
        var ch = mediaType[nextIndex];
        if (ch == ';') {
          if (!quoted) {
            break;
          }
        } else if (ch == '"') {
          quoted = !quoted;
        }
        nextIndex++;
      }

      String parameter = mediaType.substring(index + 1, nextIndex).trim();
      if (parameter.isNotEmpty) {
        int eqIndex = parameter.indexOf('=');
        if (eqIndex >= 0) {
          String attribute = parameter.substring(0, eqIndex).trim();
          String value = parameter.substring(eqIndex + 1).trim();
          parameters[attribute] = value;
        }
      }
      index = nextIndex;
    } while (index < mediaType.length);

    try {
      return MediaType(type, subtype, parameters: parameters);
    } catch (e) {
      throw InvalidMediaTypeException(mediaType, e.toString());
    }
  }

  ///类似于equals（Object），但仅基于类型和子类型，即忽略参数。
  bool equalsTypeAndSubtype(MediaType other) {
    return type.toLowerCase() == other.type.toLowerCase() && subtype.toLowerCase() == other.subtype.toLowerCase();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is MediaType) {
      return type == other.type && subtype == other.subtype && parameters == other.parameters;
    }
    return false;
  }

  @override
  int get hashCode => type.hashCode ^ subtype.hashCode ^ parameters.hashCode;
}

class InvalidMediaTypeException implements Exception {
  final String mediaType;
  final String message;

  InvalidMediaTypeException(this.mediaType, this.message);

  @override
  String toString() {
    return "InvalidMediaTypeException: $message (mediaType: $mediaType)";
  }
}
