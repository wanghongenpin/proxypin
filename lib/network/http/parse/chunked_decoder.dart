/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 */

import 'dart:typed_data';

/// Incremental HTTP/1.1 `Transfer-Encoding: chunked` decoder.
///
/// Feed arbitrary byte slices (including ones that split a chunk-size line
/// or the trailing CRLF across calls) via [feed] and receive the de-chunked
/// payload bytes. State is preserved across calls until [isDone] flips true.
class ChunkedDecoder {
  static const int _cr = 0x0D;
  static const int _lf = 0x0A;

  final BytesBuilder _carry = BytesBuilder(copy: false);
  int _remaining = 0;
  _ChunkState _state = _ChunkState.readSize;
  bool _done = false;

  bool get isDone => _done;

  /// Feed a new slice of chunk-encoded bytes; return whatever payload bytes
  /// could be decoded from what has been seen so far. May return empty.
  Uint8List feed(Uint8List data) {
    if (_done || data.isEmpty && _carry.isEmpty) return Uint8List(0);

    _carry.add(data);
    final Uint8List all = _carry.takeBytes();
    final BytesBuilder out = BytesBuilder(copy: false);
    int offset = 0;

    while (offset < all.length) {
      switch (_state) {
        case _ChunkState.readSize:
          {
            final int lf = _indexOf(all, _lf, offset);
            if (lf == -1) {
              _carry.add(Uint8List.sublistView(all, offset));
              return out.takeBytes();
            }
            int lineEnd = lf;
            if (lineEnd > offset && all[lineEnd - 1] == _cr) lineEnd--;
            String line = String.fromCharCodes(all, offset, lineEnd);
            offset = lf + 1;

            // Strip chunk-extension after ';'
            final int semi = line.indexOf(';');
            final String sizeHex = (semi == -1 ? line : line.substring(0, semi)).trim();
            if (sizeHex.isEmpty) continue; // tolerate stray blank line

            final int? size = int.tryParse(sizeHex, radix: 16);
            if (size == null) {
              throw FormatException('Invalid chunk size: "$sizeHex"');
            }
            _remaining = size;
            _state = size == 0 ? _ChunkState.readTrailer : _ChunkState.readData;
            break;
          }
        case _ChunkState.readData:
          {
            final int avail = all.length - offset;
            final int take = _remaining < avail ? _remaining : avail;
            if (take > 0) {
              out.add(Uint8List.sublistView(all, offset, offset + take));
              offset += take;
              _remaining -= take;
            }
            if (_remaining == 0) _state = _ChunkState.readDataCrlf;
            break;
          }
        case _ChunkState.readDataCrlf:
          {
            final int avail = all.length - offset;
            if (avail < 2) {
              // Need to see both bytes before deciding; keep the byte we have.
              // If it's a lone LF we still consume 2 to be safe on next feed.
              _carry.add(Uint8List.sublistView(all, offset));
              return out.takeBytes();
            }
            if (all[offset] == _cr && all[offset + 1] == _lf) {
              offset += 2;
            } else if (all[offset] == _lf) {
              // Tolerate LF-only line ending.
              offset += 1;
            } else {
              // Malformed — attempt to resync by advancing one byte.
              offset += 1;
            }
            _state = _ChunkState.readSize;
            break;
          }
        case _ChunkState.readTrailer:
          {
            final int lf = _indexOf(all, _lf, offset);
            if (lf == -1) {
              _carry.add(Uint8List.sublistView(all, offset));
              return out.takeBytes();
            }
            int lineEnd = lf;
            if (lineEnd > offset && all[lineEnd - 1] == _cr) lineEnd--;
            final bool empty = lineEnd == offset;
            offset = lf + 1;
            if (empty) {
              _done = true;
              _state = _ChunkState.finished;
              return out.takeBytes();
            }
            // otherwise a trailer header line — ignore its content.
            break;
          }
        case _ChunkState.finished:
          return out.takeBytes();
      }
    }

    return out.takeBytes();
  }

  static int _indexOf(Uint8List data, int byte, int from) {
    for (int i = from; i < data.length; i++) {
      if (data[i] == byte) return i;
    }
    return -1;
  }
}

enum _ChunkState { readSize, readData, readDataCrlf, readTrailer, finished }
