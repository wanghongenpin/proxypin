
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/h2/setting.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/network/util/attribute_keys.dart';
import 'package:proxypin/network/util/process_info.dart';
import 'package:proxypin/utils/lang.dart';

import '../bin/listener.dart';

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