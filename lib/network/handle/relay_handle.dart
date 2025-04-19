import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';

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
