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

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../util/logger.dart';

class WebSocketFrame {
  final bool fin;

  /*
      0x00 denotes a continuation frame
      0x01 表示一个text frame
      0x02 表示一个binary frame
      0x03 ~~ 0x07 are reserved for further non-control frames,为将来的非控制消息片段保留测操作码
      0x08 表示连接关闭
      0x09 表示 ping (心跳检测相关)
      0x0a 表示 pong (心跳检测相关)
   */
  final int opcode; //4bit
  final bool mask; //1bit
  final int maskingKey;

  final int payloadLength;
  final Uint8List payloadData;

  bool isFromClient = false;
  final DateTime time = DateTime.now();

  WebSocketFrame({
    required this.fin,
    required this.opcode,
    required this.mask,
    required this.payloadLength,
    required this.maskingKey,
    required this.payloadData,
  });

  bool get isText => opcode == 0x01;

  String get payloadDataAsString {
    if (opcode == 0x08) {
      return '[连接关闭]';
    }
    if (opcode == 0x02) {
      return '[二进制数据]';
    }
    try {
      return utf8.decode(payloadData);
    } catch (e) {
      return String.fromCharCodes(payloadData);
    }
  }
}

class WebSocketHeader {
  final bool fin; // 当前帧是否结束
  final int rsv; // 是否压缩
  final int opcode; //4bit  当前帧类型
  final bool mask; //1bit  是否有掩码
  final int maskingKey; // 掩码
  final int payloadStart; // 消息体起始位置
  final int payloadLength; // 消息体大小

  WebSocketHeader({
    required this.fin,
    required this.rsv,
    required this.opcode,
    required this.mask,
    required this.maskingKey,
    required this.payloadStart,
    required this.payloadLength,
  });
}

///websocket 解码器
class WebSocketDecoder {
  List<int> buffer = []; // 单独创建一个缓存,以解决数据帧不完整的问题

  WebSocketFrame? decode(Uint8List byteBuf) {
    WebSocketFrame? frame;
    buffer.addAll(byteBuf); // 所有的数据都从缓存中读取
    try {
      //先解析WebSocket Header
      if (buffer.length < 2) {
        // logger.w("报文缓存中的大小不够,无法解析Socket头 => ${buffer.length}");
        return null;
      }
      var reader = ByteData.sublistView(Uint8List.fromList(buffer));
      WebSocketHeader frameHeader = parseWebSocketHeader(reader);
      // 大小不足时不解析Frame
      if (buffer.length < frameHeader.payloadStart + frameHeader.payloadLength) {
        return null;
      }
      // 处理报文
      var payloadData = Uint8List.fromList(buffer).sublist(
          frameHeader.payloadStart,
          frameHeader.payloadStart + frameHeader.payloadLength);
      // 先解掩码
      if (frameHeader.mask) {
        payloadData = unmaskPayload(payloadData, frameHeader.maskingKey);
      }
      // 再解压
      if (frameHeader.rsv == 1) {
        payloadData = decompress(payloadData);
      }
      // 构建Frame
      frame = WebSocketFrame(
          fin: frameHeader.fin,
          opcode: frameHeader.opcode,
          mask: frameHeader.mask,
          payloadLength: frameHeader.payloadLength,
          maskingKey: frameHeader.maskingKey,
          payloadData: payloadData);
      // 整理buffer
      buffer =
          buffer.sublist(frameHeader.payloadStart + frameHeader.payloadLength);
    } catch (e, s) {
      logger.e("websocket decode error", error: e, stackTrace: s);
    }
    return frame;
  }

  WebSocketHeader parseWebSocketHeader(ByteData reader) {
    var fin = reader.getUint8(0) >> 7;
    //解析 rsv1 todo - 待支持rsv2,rsv3
    var rsv1 = (reader.getUint8(0) >> 6) & 0x01;

    var opcode = reader.getUint8(0) & 0x0f;

    var mask = reader.getUint8(1) >> 7;

    var payloadLength = reader.getUint8(1) & 0x7f;

    int payloadStart = 2;

    if (payloadLength == 126) {
      payloadLength = reader.getUint16(2, Endian.big);
      payloadStart += 2;
    } else if (payloadLength == 127) {
      payloadLength = reader.getUint64(2, Endian.big);
      payloadStart += 8;
    }
    var maskingKey = 0;
    if (mask == 1) {
      maskingKey = reader.getUint32(payloadStart);
      payloadStart += 4;
    }
    return WebSocketHeader(
        fin: fin == 1,
        rsv: rsv1,
        opcode: opcode,
        mask: mask == 1,
        maskingKey: maskingKey,
        payloadStart: payloadStart,
        payloadLength: payloadLength);
  }

  bool canParseWebSocketFrame(Uint8List data) {
    if (data.length < 2) {
      return false;
    }

    var reader = ByteData.sublistView(data);

    var opcode = reader.getUint8(0) & 0x0f;
    if (opcode > 0xA) {
      return false; // opCode超出范围说明是异常的
    }

    var mask = reader.getUint8(1) >> 7;
    int payloadStart = 2;
    if (mask == 1) {
      payloadStart += 4;
    }

    var payloadLength = reader.getUint8(1) & 0x7f;
    if (payloadLength == 126) {
      payloadStart += 2;
    } else if (payloadLength == 127) {
      payloadStart += 8;
    }

    if (data.length < payloadStart + payloadLength) {
      return false;
    }
    return true;
  }

  ZLibDecoder? _decoder;

  ZLibDecoder _ensureDecoder() => _decoder ?? ZLibDecoder(raw: true);

  Uint8List decompress(Uint8List msg) {
    try {
      // todo - 这个方法没有办法正确解析rsv1为1的payload.
      return Uint8List.fromList(_ensureDecoder().convert(msg));
    } catch (e) {
      return msg;
    }
  }

  Uint8List unmaskPayload(Uint8List payloadData, int maskingKey) {
    var unmaskedData = Uint8List(payloadData.length);
    for (var i = 0; i < payloadData.length; i++) {
      var keyByte = (maskingKey >> ((3 - (i % 4)) * 8)) & 0xff;
      unmaskedData[i] = payloadData[i] ^ keyByte;
    }
    return unmaskedData;
  }
}
