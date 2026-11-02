/*
 * Server-Sent Events (text/event-stream) incremental decoder
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/util/compress.dart';

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
        final pending = _takeEvent();
        if (pending != null) frames.add(pending);
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
          // Chat APIs often send `15:{...}` or `0:"token"` instead of `data:`.
          // Those lines are the body; dropping them leaves the panel empty.
          frames.add(_textFrame(line));
          break;
      }
    }

    return frames;
  }

  /// Emit a `data:` event that ended without a blank line, including a
  /// trailing line that never received its newline.
  List<WebSocketFrame> flush() {
    final frames = <WebSocketFrame>[];
    if (_lineBuf.isNotEmpty) {
      frames.addAll(feed(Uint8List.fromList(utf8.encode('\n'))));
    }
    final pending = _takeEvent();
    if (pending != null) frames.add(pending);
    _resetEventState();
    return frames;
  }

  WebSocketFrame? _takeEvent() {
    if (_data.isEmpty) return null;
    String dataValue = _data.toString();
    if (dataValue.endsWith('\n')) dataValue = dataValue.substring(0, dataValue.length - 1);
    _data.clear();
    if (dataValue.isEmpty) return null;
    final String payloadText = _event == null && _id == null
        ? dataValue
        : _buildLabeledPayload(dataValue, event: _event, id: _id, retry: _retry);
    return _textFrame(payloadText);
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

/// True when the event-stream body is not plaintext and must be buffered
/// until it can be inflated. Parsing those bytes as SSE yields no events.
bool sseBodyIsEncoded(String? contentEncoding) {
  switch (contentEncoding) {
    case 'gzip':
    case 'x-gzip':
    case 'br':
    case 'deflate':
    case 'zstd':
      return true;
    default:
      return false;
  }
}

/// Inflate a finished event-stream body and split it into events.
/// Returns an empty list when [contentEncoding] is unsupported or the bytes
/// are not valid compressed data. Callers keep the original headers.
Future<List<WebSocketFrame>> decodeEncodedEventStream(Uint8List encoded, String? contentEncoding) async {
  final List<int>? plain = await _inflateSse(encoded, contentEncoding);
  if (plain == null) return const [];
  final parsed = SseDecoder();
  final frames = parsed.feed(Uint8List.fromList(plain));
  frames.addAll(parsed.flush());
  return frames;
}

Future<List<int>?> _inflateSse(Uint8List encoded, String? contentEncoding) async {
  if (encoded.isEmpty) return null;

  final List<int> out;
  switch (contentEncoding) {
    case 'gzip':
    case 'x-gzip':
      out = gzipDecode(encoded);
      break;
    case 'br':
      out = brDecode(encoded);
      break;
    case 'deflate':
      out = zlibDecode(encoded);
      break;
    case 'zstd':
      final decoded = await zstdDecode(encoded);
      if (decoded == null || identical(decoded, encoded)) return null;
      out = decoded;
      break;
    default:
      return null;
  }
  // The decoders return the input unchanged when inflation fails.
  if (identical(out, encoded)) return null;
  return out;
}
