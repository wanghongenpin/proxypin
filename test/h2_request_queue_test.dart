import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/http/h2/request_queue.dart';

void main() {
  test('ready bodies retain header order while responses remain independent', () async {
    final queue = Http2RequestQueue();
    final sent = <int>[];
    for (final id in [1, 3, 5]) {
      queue.register(id);
    }
    final third = queue.submit(5, () async {
      sent.add(5);
    });
    final second = queue.submit(3, () async {
      sent.add(3);
    });
    expect(sent, isEmpty);
    final first = queue.submit(1, () async {
      sent.add(1);
    });
    await Future.wait([first, second, third]);
    expect(sent, [1, 3, 5]);
  });

  test('cancelled body releases a ready successor and late body is not sent', () async {
    final queue = Http2RequestQueue();
    queue.register(1);
    queue.register(3);
    var sent = false;
    final next = queue.submit(3, () async {
      sent = true;
    });
    queue.cancel(1);
    await next;
    expect(sent, isTrue);
    await queue.submit(1, () async {
      fail('已取消流不能在稍后发送');
    });
  });

  test('cancel during asynchronous preparation revokes permission', () async {
    final queue = Http2RequestQueue();
    queue.register(1);
    queue.register(3);
    final unblock = Completer<void>();
    final first = queue.submit(1, () async {
      await unblock.future;
      expect(queue.canForward(1), isFalse);
    });
    var nextSent = false;
    final second = queue.submit(3, () async {
      nextSent = true;
    });
    queue.cancel(1);
    unblock.complete();
    await Future.wait([first, second]);
    expect(nextSent, isTrue);
  });

  test('closing releases pending callbacks without forwarding new requests', () async {
    final queue = Http2RequestQueue();
    queue.register(1);
    queue.register(3);
    final second = queue.submit(3, () async {
      fail('断开的客户端不能再提交请求');
    });
    queue.close();
    await second;
    queue.register(5);
    await queue.submit(5, () async {
      fail('关闭后的新流不能发送');
    });
  });

  test('a failed send is reported and does not strand later work', () async {
    final queue = Http2RequestQueue();
    queue.register(1);
    queue.register(3);
    final first = queue.submit(1, () async {
      throw StateError('测试错误');
    });
    final assertion = expectLater(first, throwsStateError);
    var sent = false;
    await queue.submit(3, () async {
      sent = true;
    });
    await assertion;
    expect(sent, isTrue);
  });
}
