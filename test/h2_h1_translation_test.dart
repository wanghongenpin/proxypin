import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/h2/h2_codec.dart';
import 'package:proxypin/network/http/http.dart';

void main() {
  test('1xx interim response HEADERS must not carry END_STREAM', () {
    var codec = Http2ResponseDecoder();
    var response = HttpResponse(HttpStatus.valueOf(100), protocolVersion: 'HTTP/1.1');
    response.streamId = 1;

    var bytes = codec.encode(ChannelContext(), response);

    // frame header: length(3) type(1) flags(1) streamId(4)
    expect(bytes[3], 1, reason: 'type must be HEADERS');
    expect(bytes[4] & 0x4, 0x4, reason: 'END_HEADERS must be set');
    expect(bytes[4] & 0x1, 0, reason: '1xx 是中间响应，不能终结 stream');
  });

  test('103 Early Hints HEADERS must not carry END_STREAM', () {
    var codec = Http2ResponseDecoder();
    var response = HttpResponse(HttpStatus.valueOf(103), protocolVersion: 'HTTP/1.1');
    response.streamId = 3;

    var bytes = codec.encode(ChannelContext(), response);
    expect(bytes[4] & 0x1, 0);
  });

  test('final response without body carries END_STREAM', () {
    var codec = Http2ResponseDecoder();
    var response = HttpResponse(HttpStatus.ok, protocolVersion: 'HTTP/1.1');
    response.streamId = 1;

    var bytes = codec.encode(ChannelContext(), response);
    expect(bytes[3], 1);
    expect(bytes[4] & 0x1, 0x1, reason: '最终空 body 响应应正常终结 stream');
  });

  test('204 No Content carries END_STREAM', () {
    var codec = Http2ResponseDecoder();
    var response = HttpResponse(HttpStatus.valueOf(204), protocolVersion: 'HTTP/1.1');
    response.streamId = 1;

    var bytes = codec.encode(ChannelContext(), response);
    expect(bytes[4] & 0x1, 0x1);
  });
}
