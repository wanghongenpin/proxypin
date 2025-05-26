/*
 * Copyright 2023 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

enum FrameType { data, headers, priority, rstStream, settings, pushPromise, ping, goaway, windowUpdate, continuation }

class FrameHeader {
  static const flagsEndStream = 0x01;
  static const flagsEndHeaders = 0x04;
  static const flagsPriority = 0x20;

  final int length;
  final FrameType type;
  int flags; // 8 bits
  final int streamIdentifier;

  FrameHeader(this.length, this.type, this.flags, this.streamIdentifier);

  bool get hasPaddedFlag => (flags & 0x08) == 0x08;

  bool get hasPriorityFlag => (flags & flagsPriority) == flagsPriority;

  bool get hasEndHeadersFlag => (flags & flagsEndHeaders) == flagsEndHeaders;

  bool get hasEndStreamFlag => (flags & flagsEndStream) == flagsEndStream;

  bool get hasAckFlag => (flags & 0x01) == 0x01;

  List<int> encode() {
    var result = <int>[];
    result.addAll(_intToBytes(length, 3)); // length is 24 bits
    result.add(type.index); // type is 8 bits
    result.add(flags); // flags is 8 bits
    result.addAll(_intToBytes(streamIdentifier, 4)); // streamIdentifier is 32 bits
    return result;
  }

  List<int> _intToBytes(int value, int byteCount) {
    var bytes = <int>[];
    for (var i = 0; i < byteCount; i++) {
      bytes.insert(0, value & 0xff);
      value >>= 8;
    }
    return bytes;
  }
}

class Frame {
  final FrameHeader header;

  Frame(this.header);

  Map toJson() => {
        'length': header.length,
        'type': header.type.toString().split('.')[1],
        'flags': header.flags,
        'streamIdentifier': header.streamIdentifier
      };
}

class HeadersFrame extends Frame {
  final int padLength;
  final bool exclusiveDependency;
  final int? streamDependency;
  final int? weight;
  List<int> headerBlockFragment;

  HeadersFrame(super.header, this.padLength, this.exclusiveDependency, this.streamDependency, this.weight,
      this.headerBlockFragment);

  @override
  String toString() {
    return "HeadersFrame{padLength: $padLength, exclusiveDependency: $exclusiveDependency, streamDependency: $streamDependency, weight: $weight, headerBlockFragment: ${headerBlockFragment.length}}";
  }
}

class DataFrame extends Frame {
  final int padLength;
  final List<int> data;

  DataFrame(super.header, this.padLength, this.data);
}
