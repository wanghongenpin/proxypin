import 'dart:typed_data';

import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/h2/frame.dart';
import 'package:proxypin/network/http/h2/setting.dart';
import 'package:proxypin/network/http/h2/request_queue.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/attribute_keys.dart';
import 'package:proxypin/network/util/process_info.dart';
import 'package:proxypin/utils/lang.dart';

import '../bin/listener.dart';
import 'network.dart';

///
class ChannelContext {
  final Map<String, Object> _attributes = {};

  //和本地客户端的连接
  Channel? clientChannel;

  //和远程服务端的连接
  Channel? serverChannel;

  // 明文连接没有ALPN，识别完整前置帧后由两端编解码器共用此状态。
  bool isHttp2PriorKnowledge = false;
  final BytesBuilder _pendingHttp2Frames = BytesBuilder();
  Future<Channel>? _connectingServerChannel;
  bool _http2SettingsSent = false;
  bool _http2SettingsAckPending = false;
  final http2Requests = Http2RequestQueue();
  final _forwardedHttp2Streams = <int>{};
  final _pendingHttp2StreamFrames = <int, BytesBuilder>{};

  Future<Channel?> get readyServerChannel async {
    final connecting = _connectingServerChannel;
    if (connecting != null) return await connecting;
    return serverChannel;
  }

  void bufferHttp2Frames(List<int> bytes) => _pendingHttp2Frames.add(bytes);

  Future<void> sendInitialHttp2Settings() async {
    if (_http2SettingsSent) return;
    _http2SettingsSent = true;
    _http2SettingsAckPending = true;
    // 客户端可以等服务端前置帧后才发送:authority，不能双方一直等待。
    await clientChannel!.writeBytes(FrameHeader(0, FrameType.settings, 0, 0).encode());
  }

  bool consumeInitialHttp2SettingsAck() {
    if (!_http2SettingsAckPending) return false;
    _http2SettingsAckPending = false;
    return true;
  }

  EventListener? listener;

  //http2 stream
  final Map<int, Pair<HttpRequest?, HttpResponse?>> _streams = {};
  final Map<int, HeadersFrame> _streamDependency = {};

  ChannelContext();

  //创建服务端连接
  Future<Channel> connectServerChannel(HostAndPort hostAndPort, ChannelHandler channelHandler) {
    // 调用方经过异步处理后可能仍持有旧的 null；这里同时复核在建和已建连接。
    final connecting = _connectingServerChannel;
    if (connecting != null) return connecting;
    final connected = serverChannel;
    if (connected != null) return Future.value(connected);
    return _connectingServerChannel ??= _connectServerChannel(hostAndPort, channelHandler);
  }

  Future<Channel> _connectServerChannel(HostAndPort hostAndPort, ChannelHandler channelHandler) async {
    try {
      serverChannel = await startConnect(hostAndPort, channelHandler, this);
      putAttribute(clientChannel!.id, serverChannel);
      putAttribute(serverChannel!.id, clientChannel);
      // :authority到达前还不知道目标，前置帧和SETTINGS不能在此之前丢弃。
      while (_pendingHttp2Frames.isNotEmpty) {
        await serverChannel!.writeBytes(_pendingHttp2Frames.takeBytes());
      }
      return serverChannel!;
    } finally {
      _connectingServerChannel = null;
    }
  }

  /// 建立连接
  static Future<Channel> startConnect(
      HostAndPort hostAndPort, ChannelHandler handler, ChannelContext channelContext) async {
    var client = Client()..initChannel((channel) => channel.dispatcher.channelHandle(HttpClientCodec(), handler));

    return client.connect(hostAndPort, channelContext);
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
    http2Requests.register(streamId);
    _streams[streamId] = Pair(request, null);
    return old;
  }

  /// 大正文流的 DATA 不能抢在它尚未转发的 HEADERS 之前到达上游。
  bool bufferPendingHttp2StreamFrame(int streamId, List<int> bytes) {
    if (_forwardedHttp2Streams.contains(streamId)) return false;
    if (http2Requests.canForward(streamId)) {
      _pendingHttp2StreamFrames.putIfAbsent(streamId, BytesBuilder.new).add(bytes);
    }
    return true;
  }

  Future<void> writeForwardedRequest(Channel remote, HttpRequest request) async {
    if (request.protocolVersion != 'HTTP/2') {
      await remote.write(this, request);
      return;
    }
    final streamId = request.streamId!;
    if (!http2Requests.canForward(streamId)) return;
    // encode/add 在首次 await 前完成，先写 HEADERS，再写之前缓存的 DATA。
    final writes = <Future<void>>[remote.write(this, request)];
    final buffered = _pendingHttp2StreamFrames.remove(streamId);
    if (buffered != null) writes.add(remote.writeBytes(buffered.takeBytes()));
    _forwardedHttp2Streams.add(streamId);
    await Future.wait(writes);
  }

  /// 上游尚未打开的流不能收到 RST_STREAM，否则会牵连其它复用请求。
  bool cancelHttp2Request(int streamId) {
    final forwarded = _forwardedHttp2Streams.contains(streamId);
    http2Requests.cancel(streamId);
    removeStream(streamId);
    return forwarded;
  }

  void putStreamResponse(int streamId, HttpResponse response) {
    var pair = _streams[streamId];
    if (pair == null) {
      pair = Pair(null, response);
      _streams[streamId] = pair;
    }

    pair.key?.response = response;
    response.request = pair.key;
    pair.value = response;
  }

  HttpRequest? getStreamRequest(int streamId) {
    return _streams[streamId]?.key;
  }

  HttpResponse? getStreamResponse(int streamId) {
    return _streams[streamId]?.value;
  }

  void removeStream(int streamId) {
    _streams.remove(streamId);
    _streamDependency.remove(streamId);
    _forwardedHttp2Streams.remove(streamId);
    _pendingHttp2StreamFrames.remove(streamId);
  }

  void put(int streamId, HeadersFrame frame) {
    _streamDependency[streamId] = frame;
  }

  HeadersFrame? removeStreamDependency(int streamId) {
    return _streamDependency.remove(streamId);
  }

  HeadersFrame? getStreamDependency(int streamId) {
    return _streamDependency[streamId];
  }

  bool containsStreamDependency(int? streamId) {
    if (streamId == null) return false;
    return _streamDependency.containsKey(streamId);
  }
}
