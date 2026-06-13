import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/util/logger.dart';

class RelayHandler extends ChannelHandler<Object> {
  final Channel remoteChannel;

  RelayHandler(this.remoteChannel);

  @override
  Future<void> channelRead(ChannelContext channelContext, Channel channel, Object msg) async {
    try {
      await remoteChannel.write(channelContext, msg);
    } catch (e) {
      logger.w("[${channel.id}] relay write failed to ${remoteChannel.remoteSocketAddress}: $e");
      channel.close();
    }
  }

  @override
  void channelInactive(ChannelContext channelContext, Channel channel) {
    remoteChannel.close();
  }
}
