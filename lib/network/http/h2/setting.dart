/*
 * Copyright 2023 the original author or authors.
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

import 'package:proxypin/network/channel.dart';
import 'package:proxypin/network/http/h2/frame.dart';
import 'package:proxypin/network/util/byte_buf.dart';

class StreamSetting {
  /// 允许发送方通知远程端点用于解码头块的头压缩表的最大大小（以八位字节为单位）。
  /// 初始值为4096个八位字节。
  int headTableSize = 4096;

  ///如果一个端点接收到的这个参数设置为0，它就不能发送PUSH_PROMISE帧。
  ///初始值为1，表示允许服务器推送。
  bool enablePush = true;

  ///指示发送方允许的最大并发流数。这个限制是定向的：它适用于发送方允许接收方创建的流的数量。最初，对该值没有限制。建议此值不小于100，以免不必要地限制并行性。
  int? maxConcurrentStreams;

  /// 指示发送方用于流级流控制的初始窗口大小（以八位字节为单位）。初始值为216-1（65，535）个八位字节。
  int initialWindowSize = 65535;

  ///表示发送方愿意接收的最大帧有效负载的大小（以八位字节为单位）。
  int maxFrameSize = 16384;

  ///建议设置通知对等方发送方准备接受的头列表的最大大小（以八位字节为单位）。
  ///该值基于头字段的未压缩大小，包括名称和值的长度（以八位字节为单位）加上每个头字段32个八位字节的开销。
  int? maxHeaderListSize;
}

class SettingHandler {
  static void handleSettingsFrame(ChannelContext channelContext, FrameHeader frameHeader, ByteBuf payload) {
    // SETTINGS frames must have a length that is a multiple of 6 bytes
    if (frameHeader.length % 6 != 0) {
      throw Exception("Invalid SETTINGS frame length");
    }

    // If the SETTINGS frame has the ACK flag set, then it is an acknowledgement
    if (frameHeader.hasAckFlag) {
      // Handle SETTINGS ACK
      return;
    }
    var setting = channelContext.setting ??= StreamSetting();
    // Otherwise, it is a SETTINGS frame that carries settings
    while (payload.isReadable()) {
      int identifier = payload.readShort();
      int value = payload.readInt();
      // logger.d("SettingHandler.handleSettingsFrame identifier=$identifier value=$value");

      // Handle the setting based on its identifier
      switch (identifier) {
        case 1: // SETTINGS_HEADER_TABLE_SIZE
          setting.maxFrameSize = value;
          break;
        case 2: // SETTINGS_ENABLE_PUSH
          setting.enablePush = value == 1;
          break;
        case 3: // SETTINGS_MAX_CONCURRENT_STREAMS
          setting.maxConcurrentStreams = value;
          break;
        case 4: // SETTINGS_INITIAL_WINDOW_SIZE
          setting.initialWindowSize = value;
          break;
        case 5: // SETTINGS_MAX_FRAME_SIZE
          setting.maxFrameSize = value;
          break;
        case 6: // SETTINGS_MAX_HEADER_LIST_SIZE
          setting.maxHeaderListSize = value;
        default:
          break;
      }
    }
  }
}
