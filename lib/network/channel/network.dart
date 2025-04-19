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
import 'dart:typed_data';

import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/channel_dispatcher.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/handle/relay_handle.dart';
import 'package:proxypin/network/socks/socks5.dart';
import 'package:proxypin/network/util/attribute_keys.dart';
import 'package:proxypin/network/util/crts.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/process_info.dart';
import 'package:proxypin/network/util/tls.dart';

import '../bin/listener.dart';
import 'host_port.dart';

abstract class Network {
  late Function _channelInitializer;

  Network initChannel(void Function(Channel channel) initializer) {
    _channelInitializer = initializer;
    return this;
  }

  Channel listen(Channel channel, ChannelContext channelContext) {
    _channelInitializer.call(channel);
    channel.dispatcher.channelActive(channelContext, channel);

    channel.socket.listen((data) => onEvent(data, channelContext, channel),
        onError: (error, StackTrace trace) =>
            channel.dispatcher.exceptionCaught(channelContext, channel, error, trace: trace),
        onDone: () => channel.dispatcher.channelInactive(channelContext, channel));
    return channel;
  }

  Future<void> onEvent(Uint8List data, ChannelContext channelContext, Channel channel);

  /// 转发请求
  void relay(Channel clientChannel, Channel remoteChannel) {
    var rawCodec = RawCodec();
    clientChannel.dispatcher.channelHandle(rawCodec, RelayHandler(remoteChannel));
    remoteChannel.dispatcher.channelHandle(rawCodec, RelayHandler(clientChannel));
  }
}

class Server extends Network {
  Configuration configuration;

  late ServerSocket serverSocket;
  bool isRunning = false;
  EventListener? listener;

  Server(this.configuration, {this.listener});

  Future<ServerSocket> bind(int port) async {
    serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    serverSocket.listen((socket) {
      var channel = Channel(socket);
      ChannelContext channelContext = ChannelContext();
      channelContext.clientChannel = channel;
      channelContext.listener = listener;
      listen(channel, channelContext);
    });
    isRunning = true;
    return serverSocket;
  }

  Future<ServerSocket> stop() async {
    if (!isRunning) return serverSocket;
    isRunning = false;
    await serverSocket.close();
    return serverSocket;
  }

  @override
  Future<void> onEvent(Uint8List data, ChannelContext channelContext, Channel channel) async {
    //手机扫码转发远程地址
    if (configuration.remoteHost != null) {
      channelContext.putAttribute(AttributeKeys.remote, HostAndPort.of(configuration.remoteHost!));
    }

    //外部代理信息
    if (configuration.externalProxy?.enabled == true) {
      ProxyInfo externalProxy = configuration.externalProxy!;
      channelContext.putAttribute(AttributeKeys.proxyInfo, externalProxy);

      if (externalProxy.capturePacket == false) {
        //不抓包直接转发
        channelContext.putAttribute(AttributeKeys.remote, HostAndPort.host(externalProxy.host, externalProxy.port!));
      }
    }

    HostAndPort? hostAndPort = channelContext.host;

    //黑名单 或 没开启https 直接转发
    if ((HostFilter.filter(hostAndPort?.host)) || (hostAndPort?.isSsl() == true && configuration.enableSsl == false)) {
      var remoteChannel = channelContext.serverChannel ??
          await channelContext.connectServerChannel(hostAndPort!, RelayHandler(channel));
      relay(channel, remoteChannel);
      channel.dispatcher.channelRead(channelContext, channel, data);
      return;
    }

    //ssl握手
    if (hostAndPort?.isSsl() == true || TLS.isTLSClientHello(data)) {
      ssl(channelContext, channel, data);
      return;
    }

    //socks5
    if (configuration.enableSocks5 && Socks5.isSocks5(data) && channel.dispatcher.handler is! SocksServerHandler) {
      channel.dispatcher.channelHandle(RawCodec(),
          SocksServerHandler(channel.dispatcher.decoder, channel.dispatcher.encoder, channel.dispatcher.handler));
    }

    channel.dispatcher.channelRead(channelContext, channel, data);
  }

  /// ssl握手
  void ssl(ChannelContext channelContext, Channel channel, Uint8List data) async {
    var hostAndPort = channelContext.host;
    try {
      String? serviceName = TLS.getDomain(data) ?? hostAndPort?.host;

      if (hostAndPort == null) {
        var domain = serviceName;
        var port = 443;
        if (domain == null) {
          var process = await ProcessInfoUtils.getProcessByPort(
              channel.remoteSocketAddress, channel.remoteSocketAddress.toString());
          domain = process?.remoteHost;
          port = process?.remotePost ?? port;
        }
        hostAndPort = HostAndPort.host(domain!, port, scheme: HostAndPort.httpsScheme);
      }

      hostAndPort.scheme = HostAndPort.httpsScheme;
      channelContext.putAttribute(AttributeKeys.domain, hostAndPort.host);

      Channel? remoteChannel = channelContext.serverChannel;

      if (HostFilter.filter(hostAndPort.host) || !configuration.enableSsl) {
        remoteChannel = remoteChannel ?? await channelContext.connectServerChannel(hostAndPort, RelayHandler(channel));
        relay(channel, remoteChannel);
        channel.dispatcher.channelRead(channelContext, channel, data);
        return;
      }

      if (remoteChannel != null && !remoteChannel.isSsl) {
        var supportProtocols = configuration.enabledHttp2 ? TLS.supportProtocols(data) : null;
        await remoteChannel.secureSocket(channelContext, host: serviceName, supportedProtocols: supportProtocols);
      }

      //ssl自签证书
      var certificate = await CertificateManager.getCertificateContext(serviceName!);
      var selectedProtocol = remoteChannel?.selectedProtocol;
      if (selectedProtocol != null) certificate.setAlpnProtocols([selectedProtocol], true);

      //处理客户端ssl握手
      var secureSocket = await SecureSocket.secureServer(channel.socket, certificate, bufferedData: data);
      channel.serverSecureSocket(secureSocket, channelContext);
    } catch (error, trace) {
      logger.e('$hostAndPort ssl error', error: error);
      try {
        channelContext.processInfo ??=
            await ProcessInfoUtils.getProcessByPort(channel.remoteSocketAddress, hostAndPort?.domain ?? 'unknown');
      } catch (ignore) {
        /*ignore*/
      }

      channelContext.host ??= hostAndPort;
      channel.dispatcher.exceptionCaught(channelContext, channel, error, trace: trace);
    }
  }
}

class Client extends Network {
  Future<Channel> connect(HostAndPort hostAndPort, ChannelContext channelContext,
      {Duration timeout = const Duration(seconds: 3)}) async {
    String host = hostAndPort.host;
    //说明支持ipv6
    if (host.startsWith("[") && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }

    return Socket.connect(host, hostAndPort.port, timeout: timeout).then((socket) {
      if (socket.address.type != InternetAddressType.unix) {
        socket.setOption(SocketOption.tcpNoDelay, true);
      }
      var channel = Channel(socket);
      channelContext.serverChannel = channel;
      return listen(channel, channelContext);
    });
  }

  /// ssl连接
  Future<Channel> secureConnect(HostAndPort hostAndPort, ChannelContext channelContext) async {
    return SecureSocket.connect(hostAndPort.host, hostAndPort.port,
        timeout: const Duration(seconds: 3), onBadCertificate: (certificate) => true).then((socket) {
      var channel = Channel(socket);
      channelContext.serverChannel = channel;
      return listen(channel, channelContext);
    });
  }

  @override
  Future<void> onEvent(Uint8List data, ChannelContext channelContext, Channel channel) async {
    channel.dispatcher.channelRead(channelContext, channel, data);
  }
}
