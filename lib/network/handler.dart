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
import 'dart:convert';
import 'dart:typed_data';

import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/components/request_rewrite_component.dart';
import 'package:proxypin/network/components/script_manager.dart';
import 'package:proxypin/network/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/proxy_helper.dart';
import 'package:proxypin/network/util/attribute_keys.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/uri.dart';
import 'package:proxypin/utils/ip.dart';

import 'channel.dart';
import 'components/request_block_manager.dart';
import 'http_client.dart';

///请求和响应事件监听
abstract class EventListener {
  void onRequest(Channel channel, HttpRequest request);

  void onResponse(ChannelContext channelContext, HttpResponse response);

  void onMessage(Channel channel, HttpMessage message, WebSocketFrame frame) {}
}

/// http请求处理器
class HttpProxyChannelHandler extends ChannelHandler<HttpRequest> {
  EventListener? listener;
  RequestRewriteComponent? requestRewriteComponent;

  HttpProxyChannelHandler({this.listener, this.requestRewriteComponent});

  @override
  void channelRead(ChannelContext channelContext, Channel channel, HttpRequest msg) async {
    //下载证书
    if (msg.uri == 'http://proxy.pin/ssl' || msg.requestUrl == 'http://127.0.0.1:${channel.socket.port}/ssl') {
      ProxyHelper.crtDownload(channel, msg);
      return;
    }
    //请求本服务
    if ((await localIps()).contains(msg.hostAndPort?.host) && msg.hostAndPort?.port == channel.socket.port) {
      ProxyHelper.localRequest(msg, channel);
      return;
    }

    //代理转发请求
    try {
      forward(channelContext, channel, msg).catchError((error, trace) {
        exceptionCaught(channelContext, channel, error, trace: trace);
      });
    } catch (error, trace) {
      exceptionCaught(channelContext, channel, error, trace: trace);
    }
  }

  @override
  void exceptionCaught(ChannelContext channelContext, Channel channel, error, {StackTrace? trace}) {
    super.exceptionCaught(channelContext, channel, error, trace: trace);
    ProxyHelper.exceptionHandler(channelContext, channel, listener, channelContext.currentRequest, error);
  }

  @override
  void channelInactive(ChannelContext channelContext, Channel channel) {
    Channel? remoteChannel = channelContext.serverChannel;
    remoteChannel?.close();
    // log.d("[${channel.id}] close  ${channel.error}");
  }

  /// 转发请求
  Future<void> forward(ChannelContext channelContext, Channel channel, HttpRequest httpRequest) async {
    // log.d("[${channel.id}] ${httpRequest.method.name} ${httpRequest.requestUrl}");
    if (channel.error != null) {
      ProxyHelper.exceptionHandler(channelContext, channel, listener, httpRequest, channel.error);
      return;
    }

    //获取远程连接
    Channel remoteChannel;
    try {
      remoteChannel = await _getRemoteChannel(channelContext, channel, httpRequest);
    } catch (error, stackTrace) {
      log.e("[${channel.id}] 连接异常 ${httpRequest.method.name} ${httpRequest.requestUrl}",
          error: error, stackTrace: stackTrace);
      if (httpRequest.method == HttpMethod.connect) {
        channel.error = error; //记录异常
        //https代理新建connect连接请求 返回ok 会继续发起正常请求 可以获取到请求内容
        await channel.write(
            HttpResponse(HttpStatus.ok.reason('Connection established'), protocolVersion: httpRequest.protocolVersion));
      } else {
        rethrow;
      }
      return;
    }

    //实现抓包代理转发
    if (httpRequest.method != HttpMethod.connect) {
      log.d("[${channel.id}] ${httpRequest.method.name} ${httpRequest.requestUrl}");
      if (HostFilter.filter(httpRequest.hostAndPort?.host)) {
        await remoteChannel.write(httpRequest);
        return;
      }

      var uri = httpRequest.domainPath;
      //脚本替换
      var scriptManager = await ScriptManager.instance;
      HttpRequest? request = await scriptManager.runScript(httpRequest);
      if (request == null) {
        listener?.onRequest(channel, httpRequest);
        return;
      }

      httpRequest = request;
      //重写请求
      await requestRewriteComponent?.requestRewrite(httpRequest);

      listener?.onRequest(channel, httpRequest);

      //屏蔽请求
      var blockRequest = (await RequestBlockManager.instance).enableBlockRequest(uri);
      if (blockRequest) {
        log.d("[${channel.id}] 屏蔽请求 $uri");
        channel.close();
        remoteChannel.close();
        return;
      }

      //重定向
      String? redirectUrl = await requestRewriteComponent?.getRedirectRule(uri);
      if (redirectUrl?.isNotEmpty == true) {
        await redirect(channelContext, channel, httpRequest, redirectUrl!);
        return;
      }
      await remoteChannel.write(httpRequest);
    }
  }

  //重定向
  Future<void> redirect(
      ChannelContext channelContext, Channel channel, HttpRequest httpRequest, String redirectUrl) async {
    var proxyHandler = HttpResponseProxyHandler(channel, listener: listener, requestRewriteComponent: requestRewriteComponent);

    var redirectUri = UriBuild.build(redirectUrl, params: httpRequest.queries.isEmpty ? null : httpRequest.queries);
    log.d("[${channel.id}] 重定向 $redirectUri");

    if (redirectUri.isScheme('https')) {
      httpRequest.uri = redirectUri.path + (redirectUri.hasQuery ? '?${redirectUri.query}' : '');
    } else {
      httpRequest.uri = redirectUri.toString();
    }
    httpRequest.headers.host = '${redirectUri.host}${redirectUri.hasPort ? ':${redirectUri.port}' : ''}';
    var redirectChannel = await HttpClients.connect(redirectUri, proxyHandler, channelContext);
    channelContext.serverChannel = redirectChannel;
    await redirectChannel.write(httpRequest);
  }

  /// 获取远程连接
  Future<Channel> _getRemoteChannel(
      ChannelContext channelContext, Channel clientChannel, HttpRequest httpRequest) async {
    //客户端连接 作为缓存
    Channel? remoteChannel = channelContext.serverChannel;
    if (remoteChannel != null) {
      return remoteChannel;
    }

    var hostAndPort = httpRequest.hostAndPort ?? getHostAndPort(httpRequest);
    channelContext.host = hostAndPort;

    //远程转发
    HostAndPort? remote = channelContext.getAttribute(AttributeKeys.remote);
    //外部代理
    ProxyInfo? proxyInfo = channelContext.getAttribute(AttributeKeys.proxyInfo);

    if (remote != null || proxyInfo != null) {
      HostAndPort connectHost = remote ?? HostAndPort.host(proxyInfo!.host, proxyInfo.port!);
      final proxyChannel = await connectRemote(channelContext, clientChannel, connectHost);

      //代理建立完连接判断是否是https 需要发起connect请求
      if (httpRequest.method == HttpMethod.connect) {
        //proxy Authorization
        if (proxyInfo?.isAuthenticated == true) {
          String auth = base64Encode(utf8.encode("${proxyInfo?.username}:${proxyInfo?.password}"));
          httpRequest.headers.set(HttpHeaders.PROXY_AUTHORIZATION, 'Basic $auth');
        }

        await proxyChannel.write(httpRequest);
      } else {
        if (clientChannel.isSsl) {
          await HttpClients.connectRequest(hostAndPort, proxyChannel, proxyInfo: proxyInfo);
          await proxyChannel.secureSocket(channelContext, host: hostAndPort.host);
        }
      }

      return proxyChannel;
    }

    final proxyChannel = await connectRemote(channelContext, clientChannel, hostAndPort);
    if (clientChannel.isSsl) {
      await proxyChannel.secureSocket(channelContext, host: hostAndPort.host);
    }

    //https代理新建连接请求
    if (httpRequest.method == HttpMethod.connect) {
      await clientChannel.write(
          HttpResponse(HttpStatus.ok.reason('Connection established'), protocolVersion: httpRequest.protocolVersion));
    }
    return proxyChannel;
  }

  /// 连接远程
  Future<Channel> connectRemote(ChannelContext channelContext, Channel clientChannel, HostAndPort connectHost) async {
    var proxyHandler = HttpResponseProxyHandler(clientChannel, listener: listener, requestRewriteComponent: requestRewriteComponent);
    var proxyChannel = await channelContext.connectServerChannel(connectHost, proxyHandler);
    return proxyChannel;
  }
}

/// http响应代理
class HttpResponseProxyHandler extends ChannelHandler<HttpResponse> {
  //客户端的连接
  final Channel clientChannel;

  EventListener? listener;
  RequestRewriteComponent? requestRewriteComponent;

  HttpResponseProxyHandler(this.clientChannel, {this.listener, this.requestRewriteComponent});

  @override
  void channelRead(ChannelContext channelContext, Channel channel, HttpResponse msg) async {
    var request = channelContext.currentRequest;
    request?.response = msg;

    //域名是否过滤
    if (HostFilter.filter(request?.hostAndPort?.host) || request?.method == HttpMethod.connect) {
      await clientChannel.write(msg);
      return;
    }

    // log.i("[${clientChannel.id}] Response $msg");
    //脚本替换
    var scriptManager = await ScriptManager.instance;
    try {
      HttpResponse? response = await scriptManager.runResponseScript(msg);
      if (response == null) {
        channel.close();
        return;
      }
      msg = response;
    } catch (e, t) {
      msg.status = HttpStatus(-1, 'Script exec error');
      msg.body = "$e\n${msg.bodyAsString}".codeUnits;
      log.e('[${clientChannel.id}] 执行脚本异常 ', error: e, stackTrace: t);
    }

    //重写响应
    try {
      await requestRewriteComponent?.responseRewrite(msg.request?.requestUrl, msg);
    } catch (e, t) {
      msg.body = "$e".codeUnits;
      log.e('[${clientChannel.id}] 响应重写异常 ', error: e, stackTrace: t);
    }
    listener?.onResponse(channelContext, msg);

    //屏蔽响应
    var uri = request?.domainPath ?? '';
    var blockResponse = (await RequestBlockManager.instance).enableBlockResponse(uri);
    if (blockResponse) {
      channel.close();
      return;
    }

    //发送给客户端
    await clientChannel.write(msg);
  }

  @override
  void channelInactive(ChannelContext channelContext, Channel channel) {
    clientChannel.close();
  }
}

class RelayHandler extends ChannelHandler<Object> {
  final Channel remoteChannel;

  RelayHandler(this.remoteChannel);

  @override
  void channelRead(ChannelContext channelContext, Channel channel, Object msg) async {
    //发送给客户端
    remoteChannel.write(msg);
  }

  @override
  void channelInactive(ChannelContext channelContext, Channel channel) {
    remoteChannel.close();
  }
}

/// websocket处理器
class WebSocketChannelHandler extends ChannelHandler<Uint8List> {
  final WebSocketDecoder decoder = WebSocketDecoder();

  final Channel proxyChannel;
  final HttpMessage message;

  WebSocketChannelHandler(this.proxyChannel, this.message);

  @override
  void channelRead(ChannelContext channelContext, Channel channel, Uint8List msg) {
    proxyChannel.write(msg);
    WebSocketFrame? frame;
    try {
      frame = decoder.decode(msg);
    } catch (e) {
      log.e("websocket decode error", error: e);
    }
    if (frame == null) {
      return;
    }
    frame.isFromClient = message is HttpRequest;

    message.messages.add(frame);
    channelContext.listener?.onMessage(channel, message, frame);
    logger.d("socket channelRead ${frame.payloadLength} ${frame.fin} ${frame.payloadDataAsString}");
  }
}
