/*
 * Server-Sent Events (text/event-stream) incremental decoder
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:proxypin/network/http/websocket.dart';

/// Parse SSE stream chunks into message frames.
/// We reuse WebSocketFrame as a generic message container so UI and listeners work.
class SseDecoder {
  final StringBuffer _lineBuf = StringBuffer();

  // current event fields
  final StringBuffer _data = StringBuffer();
  String? _event;
  String? _id;
  int? _retry;

  /// Feed a chunk of bytes and return zero or more frames assembled.
  List<WebSocketFrame> feed(Uint8List bytes) {
    final List<WebSocketFrame> frames = [];

    // Append decoded text to buffer; allowMalformed to survive split UTF-8 sequences.
    _lineBuf.write(utf8.decode(bytes, allowMalformed: true));

    while (true) {
      final String current = _lineBuf.toString();
      final int nl = current.indexOf('\n');
      if (nl == -1) break;

      String line = current.substring(0, nl);
      _lineBuf.clear();
      if (nl + 1 < current.length) _lineBuf.write(current.substring(nl + 1));

      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);

      if (line.isEmpty) {
        // End of event: emit if any data collected
        if (_data.isNotEmpty) {
          String dataValue = _data.toString();
          if (dataValue.endsWith('\n')) dataValue = dataValue.substring(0, dataValue.length - 1);

          // Build a text frame from the SSE event. Include event/id headers if present as a prefix comment.
          final String payloadText = _event == null && _id == null
              ? dataValue
              : _buildLabeledPayload(dataValue, event: _event, id: _id, retry: _retry);

          frames.add(_textFrame(payloadText));
        }
        _resetEventState();
        continue;
      }

      if (line.startsWith(':')) {
        // comment line – ignore
        continue;
      }

      final int colon = line.indexOf(':');
      final String field = (colon == -1) ? line : line.substring(0, colon);
      String value = (colon == -1) ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);

      switch (field) {
        case 'data':
          _data.write(value);
          _data.write('\n');
          break;
        case 'event':
          _event = value;
          break;
        case 'id':
          _id = value;
          break;
        case 'retry':
          _retry = int.tryParse(value);
          break;
        default:
          // ignore unknown fields
          break;
      }
    }

    return frames;
  }

  void _resetEventState() {
    _data.clear();
    _event = null;
    _id = null;
    _retry = null;
  }

  String _buildLabeledPayload(String data, {String? event, String? id, int? retry}) {
    final StringBuffer b = StringBuffer();
    if (event != null && event.isNotEmpty) b.writeln('event: $event');
    if (id != null && id.isNotEmpty) b.writeln('id: $id');
    if (retry != null) b.writeln('retry: $retry');
    b.write(data);
    return b.toString();
  }

  WebSocketFrame _textFrame(String text) {
    final bytes = utf8.encode(text);
    return WebSocketFrame(
      fin: true,
      opcode: 0x01, // text
      mask: false,
      payloadLength: bytes.length,
      maskingKey: 0,
      payloadData: Uint8List.fromList(bytes),
    );
  }
}

