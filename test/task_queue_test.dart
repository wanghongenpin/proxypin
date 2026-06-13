import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/util/task_queue.dart';

void main() {
  group('SequentialTaskQueue', () {
    test('executes tasks in order', () async {
      var queue = SequentialTaskQueue();
      var results = <int>[];

      queue.add(1, null, () async => results.add(1));
      queue.add(2, null, () async => results.add(2));
      queue.add(3, null, () async => results.add(3));

      await queue.waitForAll();
      expect(results, [1, 2, 3]);
    });

    test('executes dependent tasks after their dependency', () async {
      var queue = SequentialTaskQueue();
      var results = <int>[];

      queue.add(1, null, () async {
        await Future.delayed(Duration(milliseconds: 10));
        results.add(1);
      });
      queue.add(2, 1, () async => results.add(2));

      await queue.waitForAll();
      expect(results, [1, 2]);
    });

    test('cancel stops processing new tasks', () async {
      var queue = SequentialTaskQueue();
      var results = <int>[];

      queue.add(1, null, () async {
        results.add(1);
        queue.cancel();
      });
      queue.add(2, null, () async => results.add(2));

      await queue.waitForAll();
      expect(results, [1]);
    });

    test('reset allows re-use after cancel', () async {
      var queue = SequentialTaskQueue();
      var results = <int>[];

      queue.cancel();
      queue.reset();

      queue.add(1, null, () async => results.add(1));
      await queue.waitForAll();
      expect(results, [1]);
    });

    test('onError callback receives errors', () async {
      var queue = SequentialTaskQueue();
      dynamic capturedError;

      queue.add(1, null, () async {
        throw Exception('test error');
      }, onError: (error, stackTrace) {
        capturedError = error;
      });

      await queue.waitForAll();
      expect(capturedError, isA<Exception>());
    });

    test('task failure does not prevent subsequent tasks', () async {
      var queue = SequentialTaskQueue();
      var results = <int>[];

      queue.add(1, null, () async => throw Exception('fail'), onError: (_, __) {});
      queue.add(2, null, () async => results.add(2));

      await queue.waitForAll();
      expect(results, [2]);
    });

    test('completedTasks tracks finished task ids', () async {
      var queue = SequentialTaskQueue();

      queue.add(10, null, () async {});
      queue.add(20, null, () async {});

      await queue.waitForAll();
      expect(queue.completedTasks, contains(10));
      expect(queue.completedTasks, contains(20));
    });

    test('waitForAll resolves immediately when idle', () async {
      var queue = SequentialTaskQueue();
      await queue.waitForAll(); // should not hang
    });
  });
}
