/*
 * Copyright 2024 Hongen Wang All rights reserved.
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

import 'dart:typed_data';

import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/util/attribute_keys.dart';
import 'package:proxypin/network/util/logger.dart';

import '../channel/host_port.dart';

/// @author wanghongen
class Socks5 {
  static const int version = 5;
  static const int methodNoAuth = 0;
  static const int methodNoAcceptable = 0xff;

  static const int cmdConnect = 1;

  static const int atypIpv4 = 1;

  static const int repSuccess = 0;
  static const int repCommandNotSupported = 7;
  static const int repAddressTypeNotSupported = 8;

  static const int repSocks5ServerAtypIpv4 = 0x01;
  static const int repSocks5ServerAtypDomain = 0x03;
  static const int repSocks5ServerAtypIpv6 = 0x04;

  static bool isSocks5(Uint8List data) {
    return data.length > 2 && data[0] == version;
  }
}

///Detects the version of the current SOCKS connection and initializes the pipeline with Socks5InitialRequestDecoder.
class SocksServerHandler extends ChannelHandler<Uint8List> {
  late Decoder originalDecoder;
  late Encoder originalEncoder;
  final ChannelHandler originalHandler;

  SocksState socksState = SocksState.init;

  SocksServerHandler(this.originalDecoder, this.originalEncoder, this.originalHandler);

  @override
  void channelRead(ChannelContext channelContext, Channel channel, Uint8List msg) async {
    int idx = 0;
    final int version = msg[idx++];
    if (version != Socks5.version) {
      await channel.writeBytes(Uint8List.fromList([Socks5.version, Socks5.methodNoAcceptable]));
      channel.dispatcher.exceptionCaught(channelContext, channel, Exception('Unsupported SOCKS version: $version'));
      return;
    }

    if (socksState == SocksState.init) {
      //no auth
      await channel.writeBytes(Uint8List.fromList([Socks5.version, Socks5.methodNoAuth]));
      socksState = SocksState.connect;
      return;
    }

    if (socksState == SocksState.connect) {
      final int cmd = msg[idx++];
      if (cmd != Socks5.cmdConnect) {
        var out = encodeCommandResponse(Socks5.repCommandNotSupported);
        await channel.writeBytes(out);
        channel.dispatcher.exceptionCaught(channelContext, channel, Exception('Unsupported SOCKS cmd: $cmd'));
        return;
      }

      //skip RSV
      idx++;

      final int dstAddrType = msg[idx++];
      if (dstAddrType != Socks5.atypIpv4) {
        var out = encodeCommandResponse(Socks5.repAddressTypeNotSupported);
        await channel.writeBytes(out);
        channel.dispatcher.exceptionCaught(channelContext, channel, Exception('Unsupported SOCKS atyp: $dstAddrType'));
        return;
      }

      final host = '${msg[idx++]}.${msg[idx++]}.${msg[idx++]}.${msg[idx++]}';
      final int port = msg[idx++] << 8 | msg[idx++];
      final proxyInfo = ProxyInfo.of(host, port);

      logger.d('[${channel.id}] Socks5 connect ${proxyInfo.host}:${proxyInfo.port}');
      channelContext.putAttribute(AttributeKeys.socks5Proxy, proxyInfo);

      final out = encodeCommandResponse(Socks5.repSuccess, bndAddrType: Socks5.repSocks5ServerAtypIpv4);
      await channel.writeBytes(out);

      channel.dispatcher.handle(originalDecoder, originalEncoder, originalHandler);
      socksState = SocksState.connected;
      return;
    }
  }

  Uint8List encodeCommandResponse(int status, {int bndAddrType = 0, String? bndAddr, int bndPort = 0}) {
    var out = BytesBuilder();
    out.addByte(Socks5.version);
    out.addByte(status);
    out.addByte(0x00); //RSV
    out.addByte(bndAddrType);

    if (bndAddr != null) {
      out.add(Int8List.fromList(bndAddr.split('.').map((e) => int.parse(e)).toList()));
    } else {
      out.add(Int8List.fromList([0, 0, 0, 0]));
    }
    out.addByte(bndPort >> 8);
    out.addByte(bndPort & 0xff);
    return out.takeBytes();
  }
}

enum SocksState {
  init,
  auth,
  connect,
  connected,
}
