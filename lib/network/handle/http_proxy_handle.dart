import 'dart:convert';

import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/components/interceptor.dart';
import 'package:proxypin/network/components/request_rewrite.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/util/proxy_helper.dart';
import 'package:proxypin/network/util/attribute_keys.dart';
import 'package:proxypin/network/util/uri.dart';
import 'package:proxypin/utils/ip.dart';

/// http请求处理器
class HttpProxyChannelHandler extends ChannelHandler<HttpRequest> {
  EventListener? listener;

  final List<Interceptor> interceptors;

  HttpProxyChannelHandler({this.listener, required this.interceptors});

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

      HttpRequest? request = httpRequest;

      //拦截器
      for (var interceptor in interceptors) {
        request = await interceptor.onRequest(request!);
        if (request == null) {
          listener?.onRequest(channel, httpRequest);
          channel.close();
          remoteChannel.close();
          return;
        }
      }

      listener?.onRequest(channel, request!);

      //重定向
      var uri = request!.domainPath;
      String? redirectUrl = await (RequestRewriteInterceptor.instance).getRedirectRule(uri);
      if (redirectUrl?.isNotEmpty == true) {
        await redirect(channelContext, channel, request, redirectUrl!);
        return;
      }
      await remoteChannel.write(request);
    }
  }

  //重定向
  Future<void> redirect(
      ChannelContext channelContext, Channel channel, HttpRequest httpRequest, String redirectUrl) async {
    var proxyHandler = HttpResponseProxyHandler(channel, interceptors, listener: listener);

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

    HostAndPort remoteAddress = hostAndPort;

    final ProxyInfo? socksProxy = channelContext.getAttribute(AttributeKeys.socks5Proxy);
    if (socksProxy != null) {
      remoteAddress = hostAndPort.copyWith(host: socksProxy.host, port: socksProxy.port!);
    }

    for (var interceptor in interceptors) {
      remoteAddress = await interceptor.preConnect(remoteAddress);
    }

    final proxyChannel = await connectRemote(channelContext, clientChannel, remoteAddress);
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
    var proxyHandler = HttpResponseProxyHandler(clientChannel, interceptors, listener: listener);
    var proxyChannel = await channelContext.connectServerChannel(connectHost, proxyHandler);
    return proxyChannel;
  }
}

/// http响应代理
class HttpResponseProxyHandler extends ChannelHandler<HttpResponse> {
  //客户端的连接
  final Channel clientChannel;

  EventListener? listener;
  final List<Interceptor> interceptors;

  HttpResponseProxyHandler(this.clientChannel, this.interceptors, {this.listener});

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

    HttpResponse? response = msg;
    //拦截器
    for (var interceptor in interceptors) {
      response = await interceptor.onResponse(request!, response!);
      if (response == null) {
        listener?.onResponse(channelContext, msg);
        channel.close();
        return;
      }
    }

    listener?.onResponse(channelContext, response!);
    //发送给客户端
    await clientChannel.write(response!);
  }

  @override
  void channelInactive(ChannelContext channelContext, Channel channel) {
    clientChannel.close();
  }
}
