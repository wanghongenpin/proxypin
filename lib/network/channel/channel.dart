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

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/socket_address.dart';

import 'channel_dispatcher.dart';

///处理I/O事件或截获I/O操作
///[T] 读取的数据类型
///@author wanghongen
abstract class ChannelHandler<T> {
  var log = logger;

  ///连接建立
  void channelActive(ChannelContext context, Channel channel) {}

  ///读取数据事件
  void channelRead(ChannelContext channelContext, Channel channel, T msg) {}

  ///连接断开
  void channelInactive(ChannelContext channelContext, Channel channel) {
    // log.i("close $channel");
  }

  void exceptionCaught(ChannelContext channelContext, Channel channel, dynamic error, {StackTrace? trace}) {
    HostAndPort? host = channelContext.host;
    log.e("[${channel.id}] error $host $channel", error: error, stackTrace: trace);
    channel.close();
  }
}

///与网络套接字或组件的连接，能够进行读、写、连接和绑定等I/O操作。
class Channel {
  final int _id;
  final ChannelDispatcher dispatcher = ChannelDispatcher();
  Socket _socket;

  //是否打开
  bool isOpen = true;

  //此通道连接到的远程地址
  final InetSocketAddress remoteSocketAddress;

  //是否写入中
  bool isWriting = false;

  Object? error; //异常

  Channel(this._socket)
      : _id = DateTime.now().millisecondsSinceEpoch + Random().nextInt(999999),
        remoteSocketAddress = InetSocketAddress(_socket.remoteAddress, _socket.remotePort);

  ///返回此channel的全局唯一标识符。
  String get id => _id.toRadixString(36);

  Socket get socket => _socket;

  Future<SecureSocket> secureSocket(ChannelContext channelContext,
      {String? host, List<String>? supportedProtocols}) async {
    SecureSocket secureSocket = await SecureSocket.secure(socket,
        host: host, supportedProtocols: supportedProtocols, onBadCertificate: (certificate) => true);

    _socket = secureSocket;
    _socket.done.then((value) => isOpen = false);
    dispatcher.listen(this, channelContext);

    return secureSocket;
  }

  serverSecureSocket(SecureSocket secureSocket, ChannelContext channelContext) {
    _socket = secureSocket;
    _socket.done.then((value) => isOpen = false);
    dispatcher.listen(this, channelContext);
  }

  String? get selectedProtocol => isSsl ? (_socket as SecureSocket).selectedProtocol : null;

  ///是否是ssl链接
  bool get isSsl => _socket is SecureSocket;

  Future<void> write(Object obj) async {
    var data = dispatcher.encoder.encode(obj);
    await writeBytes(data);
  }

  Future<void> writeBytes(List<int> bytes) async {
    if (isClosed) {
      logger.w("[$id] channel is closed");
      return;
    }

    //只能有一个写入
    int retry = 0;
    while (isWriting && retry++ < 30) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    isWriting = true;
    try {
      if (!isClosed) {
        _socket.add(bytes);
      }
      await _socket.flush();
    } catch (e, t) {
      if (e is StateError && e.message == "StreamSink is closed") {
        isOpen = false;
      } else {
        logger.e("[$id] write error", error: e, stackTrace: t);
      }
    } finally {
      isWriting = false;
    }
  }

  ///写入并关闭此channel
  Future<void> writeAndClose(Object obj) async {
    await write(obj);
    close();
  }

  ///关闭此channel
  void close() async {
    if (isClosed) {
      return;
    }

    //写入中，延迟关闭
    int retry = 0;
    while (isWriting && retry++ < 10) {
      await Future.delayed(const Duration(milliseconds: 150));
    }
    isOpen = false;
    _socket.destroy();
  }

  ///返回此channel是否打开
  bool get isClosed => !isOpen;

  @override
  String toString() {
    return 'Channel($id $remoteSocketAddress';
  }
}
