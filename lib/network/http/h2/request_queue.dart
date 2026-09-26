import 'dart:async';
import 'dart:collection';

/// 按首次 HEADERS 顺序打开新流，不等待服务端响应。
/// 正文先后完成或拦截器异步等待不能把较小流号排到较大流号后面。
class Http2RequestQueue {
  final _pending = LinkedHashMap<int, _Request>();
  bool _draining = false;
  bool _closed = false;

  void register(int streamId) {
    if (!_closed) _pending.putIfAbsent(streamId, _Request.new);
  }

  bool canForward(int streamId) => !_closed && _pending[streamId]?.cancelled == false;

  Future<void> submit(int streamId, Future<void> Function() send) {
    final request = _pending[streamId];
    if (_closed || request == null || request.cancelled) return Future.value();
    request.send = send;
    final result = request.done.future;
    _drain();
    return result;
  }

  void cancel(int streamId) {
    final request = _pending[streamId];
    if (request == null) return;
    request.cancelled = true;
    if (!request.sending) {
      _pending.remove(streamId);
      if (!request.done.isCompleted) request.done.complete();
    }
    _drain();
  }

  void close() {
    _closed = true;
    for (final id in _pending.keys.toList()) {
      cancel(id);
    }
  }

  Future<void> _drain() async {
    if (_draining || _closed) return;
    _draining = true;
    try {
      while (_pending.isNotEmpty && !_closed) {
        final id = _pending.keys.first;
        final request = _pending[id]!;
        if (request.send == null) break;
        request.sending = true;
        try {
          if (!request.cancelled) await request.send!();
          if (!request.done.isCompleted) request.done.complete();
        } catch (error, stackTrace) {
          if (!request.done.isCompleted) request.done.completeError(error, stackTrace);
        } finally {
          _pending.remove(id);
        }
      }
    } finally {
      _draining = false;
    }
  }
}

class _Request {
  Future<void> Function()? send;
  final done = Completer<void>();
  bool sending = false;
  bool cancelled = false;
}
