/*
 * Copyright 2026 Hongen Wang All rights reserved.
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
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// macOS libproc FFI bindings used to look up the local process that owns a
/// TCP socket and the executable path of a PID, without spawning child
/// processes.
///
/// Previously this functionality was implemented via
/// `Process.run('bash', ['-c', 'lsof -nP -iTCP:<port> ...'])` and
/// `Process.run('bash', ['-c', 'ps -p <pid> -o comm='])`, which were invoked
/// from the proxy request handling hot path. On macOS, Dart's `Process.run`
/// goes through `fork() + execvp()`; in a multi-threaded Dart VM, mutexes
/// held by other threads at fork time are cloned into the child with no
/// owner, so the child can deadlock before exec on `malloc`, libdispatch,
/// or Objective-C runtime locks. Such children stay alive forever, inherit
/// every fd of the parent (including the listening proxy socket), and pin
/// the bound port even after the parent exits. See issue #763 for repro
/// and full root-cause analysis.
///
/// libproc syscalls are pure system calls with no process spawning, so they
/// avoid the fork problem entirely and are about an order of magnitude
/// faster than spawning `lsof` per request.
///
/// Field offsets within `struct socket_fdinfo` were extracted via a small
/// C probe against `<sys/proc_info.h>` on macOS SDK 14+. The struct has
/// been ABI-stable since macOS 10.7; defensive checks verify the returned
/// size before reading offsets so a hypothetical layout change in a future
/// macOS release surfaces as a null return instead of memory corruption.

// FFI signatures
typedef _ProcListPidsC = Int32 Function(Uint32, Uint32, Pointer<Void>, Int32);
typedef _ProcListPidsDart = int Function(int, int, Pointer<Void>, int);

typedef _ProcPidInfoC = Int32 Function(Int32, Int32, Uint64, Pointer<Void>, Int32);
typedef _ProcPidInfoDart = int Function(int, int, int, Pointer<Void>, int);

typedef _ProcPidFdInfoC = Int32 Function(Int32, Int32, Int32, Pointer<Void>, Int32);
typedef _ProcPidFdInfoDart = int Function(int, int, int, Pointer<Void>, int);

typedef _ProcPidPathC = Int32 Function(Int32, Pointer<Void>, Uint32);
typedef _ProcPidPathDart = int Function(int, Pointer<Void>, int);

class MacosProcessInfo {
  // libproc constants (from <libproc.h> / <sys/proc_info.h>)
  static const int _kProcAllPids = 1;
  static const int _kProcPidListFds = 1;
  static const int _kProcPidFdSocketInfo = 3;
  static const int _kProxFdTypeSocket = 2;
  static const int _kSockInfoTcp = 2;
  static const int _kProcPidPathInfoMaxSize = 4096;

  // Struct sizes (verified via sizeof() probe)
  static const int _kSizeofProcFdInfo = 8;
  static const int _kSizeofSocketFdInfo = 792;

  // proc_fdinfo field offsets
  static const int _kOffProcFd = 0; // int32
  static const int _kOffProcFdType = 4; // uint32

  // socket_fdinfo field offsets
  static const int _kOffSoiKind = 256; // int32, value == _kSockInfoTcp means TCP
  static const int _kOffInsiFPort = 264; // int32 (htons(uint16) in low 16 bits); 0 for LISTEN sockets
  static const int _kOffInsiLPort = 268; // int32 (htons(uint16) in low 16 bits, network byte order)

  // libproc symbols live in libSystem which is already linked into every
  // macOS process, so DynamicLibrary.process() finds them.
  static final DynamicLibrary _libproc = DynamicLibrary.process();
  static late final _procListPids = _libproc.lookupFunction<_ProcListPidsC, _ProcListPidsDart>('proc_listpids');
  static late final _procPidInfo = _libproc.lookupFunction<_ProcPidInfoC, _ProcPidInfoDart>('proc_pidinfo');
  static late final _procPidFdInfo = _libproc.lookupFunction<_ProcPidFdInfoC, _ProcPidFdInfoDart>('proc_pidfdinfo');
  static late final _procPidPath = _libproc.lookupFunction<_ProcPidPathC, _ProcPidPathDart>('proc_pidpath');

  /// Returns the PID that owns a TCP socket whose local port equals
  /// [localPort], or null if no such socket is found or the lookup fails.
  ///
  /// Walks all PIDs and their fds via libproc syscalls. No child processes
  /// are spawned. Typical cost on a desktop with ~500 processes and ~10k
  /// total fds is a few milliseconds.
  static int? findPidByLocalTcpPort(int localPort) {
    // The insi_lport read below assumes a little-endian host: `(int)htons(port)`
    // stores the network-byte-order 16-bit port in the low two bytes of the
    // int32 field. All shipping macOS hardware (x86_64 / arm64) is
    // little-endian; this assert exists to fail loudly rather than return
    // wrong port values if that ever changes. Stripped in release builds.
    assert(Endian.host == Endian.little, 'libproc parsing requires little-endian host');

    final pidBufSize = _procListPids(_kProcAllPids, 0, nullptr, 0);
    if (pidBufSize <= 0) return null;

    // If proc_pidfdinfo keeps returning a size smaller than expected, the
    // struct layout has changed (e.g. a future macOS bumped the size) and
    // continuing the scan can't possibly find anything. Bail out early
    // after enough consecutive mismatches to avoid wasting syscalls.
    var consecutiveLayoutMismatch = 0;
    const layoutMismatchThreshold = 16;

    Pointer<Uint8>? pidBuf;
    Pointer<Uint8>? sockBuf;
    try {
      pidBuf = calloc<Uint8>(pidBufSize);
      sockBuf = calloc<Uint8>(_kSizeofSocketFdInfo);
      // Reuse the same ByteData view across all fds; the underlying native
      // buffer is overwritten in place by each proc_pidfdinfo call.
      final sockView = ByteData.sublistView(sockBuf.asTypedList(_kSizeofSocketFdInfo));
      final actual = _procListPids(_kProcAllPids, 0, pidBuf.cast(), pidBufSize);
      if (actual <= 0) return null;

      final pidView = pidBuf.cast<Int32>().asTypedList(actual ~/ 4);

      for (final pid in pidView) {
        if (pid <= 0) continue;
        if (consecutiveLayoutMismatch >= layoutMismatchThreshold) break;

        final fdSize = _procPidInfo(pid, _kProcPidListFds, 0, nullptr, 0);
        if (fdSize <= 0) continue;

        final fdBuf = calloc<Uint8>(fdSize);
        try {
          final fdActual = _procPidInfo(pid, _kProcPidListFds, 0, fdBuf.cast(), fdSize);
          if (fdActual <= 0) continue;

          final fdView = ByteData.sublistView(fdBuf.asTypedList(fdActual));
          final fdCount = fdActual ~/ _kSizeofProcFdInfo;

          for (int j = 0; j < fdCount; j++) {
            final entryOff = j * _kSizeofProcFdInfo;
            final fdType = fdView.getUint32(entryOff + _kOffProcFdType, Endian.host);
            if (fdType != _kProxFdTypeSocket) continue;

            final fd = fdView.getInt32(entryOff + _kOffProcFd, Endian.host);

            final n = _procPidFdInfo(pid, fd, _kProcPidFdSocketInfo, sockBuf.cast(), _kSizeofSocketFdInfo);
            if (n < _kSizeofSocketFdInfo) {
              consecutiveLayoutMismatch++;
              continue;
            }
            consecutiveLayoutMismatch = 0;

            final soiKind = sockView.getInt32(_kOffSoiKind, Endian.host);
            if (soiKind != _kSockInfoTcp) continue;

            // Skip LISTEN sockets. The original implementation filtered
            // them via `lsof -iTCP:port | grep "${port}->"`, since LISTEN
            // entries render as `*:port (LISTEN)` (no `->` separator) and
            // were excluded. Without this skip, a long-running daemon
            // LISTENing on a port that coincides with a client's ephemeral
            // source port would be returned instead of the real client.
            // LISTEN sockets have insi_fport == 0 (no peer endpoint).
            final fport = sockView.getUint16(_kOffInsiFPort, Endian.big);
            if (fport == 0) continue;

            // insi_lport is stored as `(int)htons(port)` per xnu's
            // fill_socketinfo(): the 16-bit network-byte-order port number
            // sits in the low two bytes of the int32 field with the upper
            // two bytes zero. On little-endian (all current macOS hosts)
            // those low bytes are at offset 0/1 of the int32, and reading
            // them as a big-endian uint16 yields the host port directly.
            final port = sockView.getUint16(_kOffInsiLPort, Endian.big);
            if (port == localPort) {
              return pid;
            }
          }
        } finally {
          calloc.free(fdBuf);
        }
      }
      return null;
    } finally {
      if (pidBuf != null) calloc.free(pidBuf);
      if (sockBuf != null) calloc.free(sockBuf);
    }
  }

  /// Returns the absolute executable path of [pid], or null if not
  /// accessible (e.g. permission denied, process gone).
  static String? getProcessPath(int pid) {
    final buf = calloc<Uint8>(_kProcPidPathInfoMaxSize);
    try {
      final ret = _procPidPath(pid, buf.cast(), _kProcPidPathInfoMaxSize);
      if (ret <= 0) return null;
      // proc_pidpath returns the byte length excluding the trailing NUL.
      return buf.cast<Utf8>().toDartString(length: ret);
    } finally {
      calloc.free(buf);
    }
  }
}
