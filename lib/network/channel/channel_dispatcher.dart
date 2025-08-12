import 'dart:async';
import 'dart:typed_data';

import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/handle/relay_handle.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/handle/websocket_handle.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/network/util/attribute_keys.dart';
import 'package:proxypin/network/util/byte_buf.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/process_info.dart';

import '../util/task_queue.dart';

class ChannelDispatcher extends ChannelHandler<Uint8List> {
  late Decoder decoder;
  late Encoder encoder;
  late ChannelHandler handler;

  final ByteBuf buffer = ByteBuf();

  //h2 stream dependency Sequential exec
  SequentialTaskQueue taskQueue = SequentialTaskQueue();

  void handle(Decoder decoder, Encoder encoder, ChannelHandler handler) {
    this.encoder = encoder;
    this.decoder = decoder;
    this.handler = handler;
  }

  void channelHandle(Codec codec, ChannelHandler handler) {
    handle(codec, codec, handler);
  }

  /// 监听
  void listen(Channel channel, ChannelContext channelContext) {
    buffer.clear();
    channel.socket.listen((data) => channel.dispatcher.channelRead(channelContext, channel, data),
        onError: (error, trace) => channel.dispatcher.exceptionCaught(channelContext, channel, error, trace: trace),
        onDone: () => channel.dispatcher.channelInactive(channelContext, channel));
  }

  @override
  void channelActive(ChannelContext context, Channel channel) {
    handler.channelActive(context, channel);
  }

  ///远程转发请求
  Future<void> remoteForward(ChannelContext channelContext, HostAndPort remote) async {
    var clientChannel = channelContext.clientChannel!;
    Channel? remoteChannel =
        channelContext.serverChannel ?? await channelContext.connectServerChannel(remote, RelayHandler(clientChannel));
    ProxyInfo? proxyInfo = channelContext.getAttribute(AttributeKeys.proxyInfo);
    if (clientChannel.isSsl && !remoteChannel.isSsl) {
      //代理认证
      if (proxyInfo?.isAuthenticated == true) {
        await HttpClients.connectRequest(channelContext, remote, remoteChannel, proxyInfo: proxyInfo);
      }

      await remoteChannel.secureSocket(channelContext, host: channelContext.getAttribute(AttributeKeys.domain));
    }

    relay(channelContext, clientChannel, remoteChannel);
  }

  /// 转发请求
  void relay(ChannelContext channelContext, Channel clientChannel, Channel remoteChannel) {
    var rawCodec = RawCodec();
    clientChannel.dispatcher.channelHandle(rawCodec, RelayHandler(remoteChannel));
    remoteChannel.dispatcher.channelHandle(rawCodec, RelayHandler(clientChannel));

    var body = buffer.bytes;
    buffer.clear();
    handler.channelRead(channelContext, clientChannel, body);
  }

  @override
  Future<void> channelRead(ChannelContext channelContext, Channel channel, Uint8List msg) async {
    //手机扫码连接转发远程
    HostAndPort? remote = channelContext.getAttribute(AttributeKeys.remote);
    buffer.add(msg);

    try {
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

      var decodeResult = decoder.decode(channelContext, buffer);

      //If the body does not support parsing, forward directly
      if (decodeResult.supportedParse == false) {
        notSupportedForward(channelContext, channel, decodeResult);
        return;
      }

      if (decodeResult.forward != null) {
        buffer.clearRead();

        if (remoteChannel != null) {
          await remoteChannel.writeBytes(decodeResult.forward!);
        } else {
          logger.w("[$channel] forward remoteChannel is null");
        }

        if (decodeResult.data == null) {
          return;
        }
      }

      if (!decodeResult.isDone) {
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
        data.hostAndPort ??= channelContext.host ?? getHostAndPort(data, ssl: channel.isSsl);
        if (data.headers.host != null && data.headers.host?.contains(":") == false) {
          data.hostAndPort?.host = data.headers.host!;
        }

        data.processInfo ??= await ProcessInfoUtils.getProcessByPort(channel.remoteSocketAddress, data.remoteDomain()!);
      }

      if (data is HttpResponse) {
        data.requestId = channelContext.currentRequest?.requestId ?? data.requestId;
        data.request ??= channelContext.currentRequest;
      }

      //websocket协议
      if (data is HttpResponse && data.isWebSocket && remoteChannel != null) {
        onWebSocketHandle(channelContext, channel, data);
        return;
      }

      if (data is HttpMessage && channelContext.containsStreamDependency(data.streamId)) {
        taskQueue.add(data.streamId!, channelContext.getStreamDependency(data.streamId!)?.streamDependency,
            () => handler.channelRead(channelContext, channel, data),
            onError: (error, stackTrace) => onError(channelContext, channel, error, trace: stackTrace));
      } else {
        await handler.channelRead(channelContext, channel, data!);
      }
    } catch (error, trace) {
      onError(channelContext, channel, error, trace: trace);
    }
  }

  void onError(ChannelContext channelContext, Channel channel, dynamic error, {StackTrace? trace}) {
    logger.e(
        "[${channelContext.clientChannel?.id}] channelRead error isSsl:${channel.isSsl} client: ${channelContext.clientChannel?.selectedProtocol} server: ${channelContext.serverChannel?.selectedProtocol} ${String.fromCharCodes(buffer.bytes)}",
        error: error,
        stackTrace: trace);
    buffer.clear();
    exceptionCaught(channelContext, channel, error, trace: trace);
  }

  /// websocket 处理
  void onWebSocketHandle(ChannelContext channelContext, Channel channel, HttpResponse data) {
    Channel remoteChannel = channelContext.getAttribute(channel.id);

    data.request?.response = data;
    channelContext.host =
        channelContext.host?.copyWith(scheme: channel.isSsl ? HostAndPort.wssScheme : HostAndPort.wsScheme);
    channelContext.currentRequest?.hostAndPort = channelContext.host;

    logger.d("webSocket ${data.request?.hostAndPort}");
    remoteChannel.write(channelContext, data);

    channelContext.listener?.onResponse(channelContext, data);

    var rawCodec = RawCodec();
    channel.dispatcher.channelHandle(rawCodec, WebSocketChannelHandler(remoteChannel, data));
    remoteChannel.dispatcher.channelHandle(rawCodec, WebSocketChannelHandler(channel, data.request!));
  }

  void notSupportedForward(ChannelContext channelContext, Channel channel, DecoderResult decodeResult) {
    Channel? remoteChannel = channelContext.getAttribute(channel.id);
    buffer.add(decodeResult.forward ?? []);
    relay(channelContext, channel, remoteChannel!);
    if (decodeResult.data is HttpResponse) {
      var response = decodeResult.data as HttpResponse;
      logger.w("[$channel] not supported parse ${response.headers.contentType}");
      response.request ??= channelContext.currentRequest;
      channelContext.currentRequest?.response = response;
      channelContext.listener?.onResponse(channelContext, response);
    }
  }

  @override
  exceptionCaught(ChannelContext channelContext, Channel channel, dynamic error, {StackTrace? trace}) {
    handler.exceptionCaught(channelContext, channel, error, trace: trace);
  }

  @override
  channelInactive(ChannelContext channelContext, Channel channel) async {
    await taskQueue.waitForAll();
    handler.channelInactive(channelContext, channel);
  }
}

class RawCodec extends Codec<Uint8List, List<int>> {
  @override
  DecoderResult<Uint8List> decode(ChannelContext channelContext, ByteBuf byteBuf, {bool resolveBody = true}) {
    var decoderResult = DecoderResult<Uint8List>()..data = byteBuf.readAvailableBytes();
    return decoderResult;
  }

  @override
  List<int> encode(ChannelContext channelContext, dynamic data) {
    return data as List<int>;
  }
}

abstract interface class ChannelInitializer {
  void initChannel(Channel channel);
}
