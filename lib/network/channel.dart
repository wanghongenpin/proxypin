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
import 'dart:typed_data';

import 'package:proxypin/network/host_port.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/h2/setting.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http_client.dart';
import 'package:proxypin/network/util/attribute_keys.dart';
import 'package:proxypin/network/util/byte_buf.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/process_info.dart';
import 'package:proxypin/network/util/socket_address.dart';
import 'package:proxypin/utils/lang.dart';

import 'handler.dart';

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
  final ChannelPipeline pipeline = ChannelPipeline();
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
    pipeline.listen(this, channelContext);

    return secureSocket;
  }

  serverSecureSocket(SecureSocket secureSocket, ChannelContext channelContext) {
    _socket = secureSocket;
    _socket.done.then((value) => isOpen = false);
    pipeline.listen(this, channelContext);
  }

  String? get selectedProtocol => isSsl ? (_socket as SecureSocket).selectedProtocol : null;

  ///是否是ssl链接
  bool get isSsl => _socket is SecureSocket;

  Future<void> write(Object obj) async {
    var data = pipeline._encoder.encode(obj);
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

///
class ChannelContext {
  final Map<String, Object> _attributes = {};

  //和本地客户端的连接
  Channel? clientChannel;

  //和远程服务端的连接
  Channel? serverChannel;

  EventListener? listener;

  //http2 stream
  final Map<int, Pair<HttpRequest, ValueWrap<HttpResponse>>> _streams = {};

  ChannelContext();

  //创建服务端连接
  Future<Channel> connectServerChannel(HostAndPort hostAndPort, ChannelHandler channelHandler) async {
    serverChannel = await HttpClients.startConnect(hostAndPort, channelHandler, this);
    putAttribute(clientChannel!.id, serverChannel);
    putAttribute(serverChannel!.id, clientChannel);
    return serverChannel!;
  }

  T? getAttribute<T>(String key) {
    if (!_attributes.containsKey(key)) {
      return null;
    }
    return _attributes[key] as T;
  }

  void putAttribute(String key, Object? value) {
    if (value == null) {
      _attributes.remove(key);
      return;
    }
    _attributes[key] = value;
  }

  HostAndPort? get host => getAttribute(AttributeKeys.host);

  set host(HostAndPort? host) => putAttribute(AttributeKeys.host, host);

  HttpRequest? get currentRequest => getAttribute(AttributeKeys.request);

  set currentRequest(HttpRequest? request) => putAttribute(AttributeKeys.request, request);

  set processInfo(ProcessInfo? processInfo) => putAttribute(AttributeKeys.processInfo, processInfo);

  ProcessInfo? get processInfo => getAttribute(AttributeKeys.processInfo);

  StreamSetting? setting;

  HttpRequest? putStreamRequest(int streamId, HttpRequest request) {
    var old = _streams[streamId]?.key;
    _streams[streamId] = Pair(request, ValueWrap());
    return old;
  }

  void putStreamResponse(int streamId, HttpResponse response) {
    var stream = _streams[streamId]!;
    stream.key.response = response;
    response.request = stream.key;
    stream.value.set(response);
  }

  HttpRequest? getStreamRequest(int streamId) {
    return _streams[streamId]?.key;
  }

  HttpResponse? getStreamResponse(int streamId) {
    return _streams[streamId]?.value.get();
  }

  void removeStream(int streamId) {
    _streams.remove(streamId);
  }
}

class ChannelPipeline extends ChannelHandler<Uint8List> {
  late Decoder _decoder;
  late Encoder _encoder;
  late ChannelHandler handler;

  final ByteBuf buffer = ByteBuf();

  handle(Decoder decoder, Encoder encoder, ChannelHandler handler) {
    _encoder = encoder;
    _decoder = decoder;
    this.handler = handler;
  }

  /// 监听
  void listen(Channel channel, ChannelContext channelContext) {
    buffer.clear();
    channel.socket.listen((data) => channel.pipeline.channelRead(channelContext, channel, data),
        onError: (error, trace) => channel.pipeline.exceptionCaught(channelContext, channel, error, trace: trace),
        onDone: () => channel.pipeline.channelInactive(channelContext, channel));
  }

  @override
  void channelActive(ChannelContext context, Channel channel) {
    handler.channelActive(context, channel);
  }

  ///远程转发请求
  remoteForward(ChannelContext channelContext, HostAndPort remote) async {
    var clientChannel = channelContext.clientChannel!;
    Channel? remoteChannel =
        channelContext.serverChannel ?? await channelContext.connectServerChannel(remote, RelayHandler(clientChannel));
    ProxyInfo? proxyInfo = channelContext.getAttribute(AttributeKeys.proxyInfo);
    if (clientChannel.isSsl && !remoteChannel.isSsl) {
      //代理认证
      if (proxyInfo?.isAuthenticated == true) {
        await HttpClients.connectRequest(remote, remoteChannel, proxyInfo: proxyInfo);
      }

      await remoteChannel.secureSocket(channelContext, host: channelContext.getAttribute(AttributeKeys.domain));
    }

    relay(channelContext, clientChannel, remoteChannel);
  }

  /// 转发请求
  void relay(ChannelContext channelContext, Channel clientChannel, Channel remoteChannel) {
    var rawCodec = RawCodec();
    clientChannel.pipeline.handle(rawCodec, rawCodec, RelayHandler(remoteChannel));
    remoteChannel.pipeline.handle(rawCodec, rawCodec, RelayHandler(clientChannel));

    var body = buffer.bytes;
    buffer.clear();
    handler.channelRead(channelContext, clientChannel, body);
  }

  @override
  void channelRead(ChannelContext channelContext, Channel channel, Uint8List msg) async {
    try {
      //手机扫码连接转发远程
      HostAndPort? remote = channelContext.getAttribute(AttributeKeys.remote);
      buffer.add(msg);

      if (remote != null) {
        await remoteForward(channelContext, remote);
        return;
      }

      Channel? remoteChannel = channelContext.getAttribute(channel.id);

      //大body 不解析直接转发
      if (buffer.length > Codec.maxBodyLength && handler is! RelayHandler && remoteChannel != null) {
        logger.w("[$channel] forward large body");
        relay(channelContext, channel, remoteChannel);
        return;
      }

      var decodeResult = _decoder.decode(channelContext, buffer);
      if (!decodeResult.isDone) {
        return;
      }

      if (decodeResult.forward != null) {
        if (remoteChannel != null) {
          await remoteChannel.writeBytes(decodeResult.forward!);
        } else {
          logger.w("[$channel] forward remoteChannel is null");
        }
        buffer.clearRead();
        return;
      }

      var length = buffer.length;
      buffer.clearRead();

      var data = decodeResult.data;
      if (data is HttpMessage) {
        data.packageSize = length;
        data.remoteHost = channel.remoteSocketAddress.host;
        data.remotePort = channel.remoteSocketAddress.port;
      }

      if (data is HttpRequest) {
        channelContext.currentRequest = data;
        data.hostAndPort = channelContext.host ?? getHostAndPort(data, ssl: channel.isSsl);
        if (data.headers.host != null && data.headers.host?.contains(":") == false) {
          data.hostAndPort?.host = data.headers.host!;
        }

        if (data.method != HttpMethod.connect) {
          try {
            data.processInfo ??=
                await ProcessInfoUtils.getProcessByPort(channel.remoteSocketAddress, data.remoteDomain()!);
          } catch (ignore) {
            /*ignore*/
          }
        }
      }

      if (data is HttpResponse) {
        data.requestId = channelContext.currentRequest?.requestId ?? data.requestId;
        data.request ??= channelContext.currentRequest;
      }

      //websocket协议
      if (data is HttpResponse && data.isWebSocket && remoteChannel != null) {
        data.request?.response = data;
        channelContext.host = channelContext.host?.copyWith(scheme: channel.isSsl ? HostAndPort.wssScheme : HostAndPort.wsScheme);
        channelContext.currentRequest?.hostAndPort = channelContext.host;

        logger.d("webSocket ${data.request?.hostAndPort}");
        remoteChannel.write(data);

        channelContext.listener?.onResponse(channelContext, data);

        var rawCodec = RawCodec();
        channel.pipeline.handle(rawCodec, rawCodec, WebSocketChannelHandler(remoteChannel, data));
        remoteChannel.pipeline.handle(rawCodec, rawCodec, WebSocketChannelHandler(channel, data.request!));
        return;
      }

      handler.channelRead(channelContext, channel, data!);
    } catch (error, trace) {
      buffer.clear();
      exceptionCaught(channelContext, channel, error, trace: trace);
    }
  }

  @override
  exceptionCaught(ChannelContext channelContext, Channel channel, dynamic error, {StackTrace? trace}) {
    handler.exceptionCaught(channelContext, channel, error, trace: trace);
  }

  @override
  channelInactive(ChannelContext channelContext, Channel channel) {
    handler.channelInactive(channelContext, channel);
  }
}

class RawCodec extends Codec<dynamic> {
  @override
  DecoderResult<dynamic> decode(ChannelContext channelContext, ByteBuf byteBuf, {bool resolveBody = true}) {
    var decoderResult = DecoderResult()..data = byteBuf.readAvailableBytes();
    return decoderResult;
  }

  @override
  List<int> encode(dynamic data) {
    return data as List<int>;
  }
}

abstract interface class ChannelInitializer {
  void initChannel(Channel channel);
}
