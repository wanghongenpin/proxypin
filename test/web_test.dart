import 'dart:async';
import 'dart:io';

import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/http.dart';

main() async {
  await socketTest();
}

socketTest() async {
  var task = await Socket.startConnect("127.0.0.1", 7890);
  var socket = await task.socket;
  if (socket.address.type != InternetAddressType.unix) {
    socket.setOption(SocketOption.tcpNoDelay, true);
  }

  Completer<bool> completer = Completer<bool>();
  StreamSubscription? subscription;
  subscription = socket.listen((event) {
    subscription!.pause();
    print(String.fromCharCodes(event));
    completer.complete(true);
  });

  String host = 'www.v2ex.com:443';

  var httpRequest = HttpRequest(HttpMethod.connect, host);
  httpRequest.headers.set('user-agent', 'Dart/3.0 (dart:io)');
  httpRequest.headers.set('accept-encoding', 'gzip');
  httpRequest.headers.set(HttpHeaders.hostHeader, host);
  ChannelContext channelContext = ChannelContext();
  var codec = HttpRequestCodec();
  print(String.fromCharCodes(codec.encode(channelContext, httpRequest)));
  socket.add(codec.encode(channelContext, httpRequest));
  await socket.flush();

  // subscription.resume();

  await completer.future;
  // await Future.delayed(const Duration(milliseconds: 1600));

  var secureSocket = await SecureSocket.secure(socket, host: 'www.v2ex.com', onBadCertificate: (certificate) => true);
  print("secureSocket");
  // await subscription.cancel();

  completer = Completer<bool>();
  subscription = secureSocket.listen((event) {
    subscription?.pause();
    print(String.fromCharCodes(event));
    completer.complete(true);
    subscription?.resume();
  });

  httpRequest = HttpRequest(HttpMethod.get, "/");
  httpRequest.headers.set(HttpHeaders.hostHeader, host);

  secureSocket.add(codec.encode(channelContext, httpRequest));
  await secureSocket.flush();
  await completer.future;
}
