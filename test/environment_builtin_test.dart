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

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/components/manager/environment_manager.dart';

void main() {
  group('EnvironmentManager.resolveBuiltIn', () {
    test(r'$date matches yyyy-MM-dd', () {
      final v = EnvironmentManager.resolveBuiltIn(r'$date')!;
      expect(v, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    test(r'$datetime matches yyyy-MM-dd HH:mm:ss', () {
      final v = EnvironmentManager.resolveBuiltIn(r'$datetime')!;
      expect(v, matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$')));
    });

    test(r'$timestamp is Unix seconds (10 digits, sane range)', () {
      final v = EnvironmentManager.resolveBuiltIn(r'$timestamp')!;
      expect(v, matches(RegExp(r'^\d{10}$')));
      final n = int.parse(v);
      // 2010-01-01 ~ 2050-01-01
      expect(n, greaterThanOrEqualTo(1262304000));
      expect(n, lessThanOrEqualTo(2524608000));
    });

    test(r'$timestampMs is Unix ms (13 digits, sane range)', () {
      final v = EnvironmentManager.resolveBuiltIn(r'$timestampMs')!;
      expect(v, matches(RegExp(r'^\d{13}$')));
      final n = int.parse(v);
      expect(n, greaterThanOrEqualTo(1262304000000));
    });

    test(r'$guid is a v4 UUID (version 4, variant 10xx)', () {
      final v = EnvironmentManager.resolveBuiltIn(r'$guid')!;
      // 8-4-4-4-12,version 4,variant 10xx
      expect(v, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });

    test(r'$uuid is alias of $guid (same format)', () {
      final v = EnvironmentManager.resolveBuiltIn(r'$uuid')!;
      expect(v, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });

    test(r'$guid 10k samples have no collisions', () {
      final set = <String>{};
      for (var i = 0; i < 10000; i++) {
        set.add(EnvironmentManager.resolveBuiltIn(r'$guid')!);
      }
      expect(set.length, 10000);
    });

    test(r'$randomString is 8 alphanumeric chars', () {
      for (var i = 0; i < 50; i++) {
        final v = EnvironmentManager.resolveBuiltIn(r'$randomString')!;
        expect(v.length, 8);
        expect(v, matches(RegExp(r'^[A-Za-z0-9]{8}$')));
      }
    });

    test(r'$randomInt is in [0, 1000000)', () {
      for (var i = 0; i < 50; i++) {
        final n = int.parse(EnvironmentManager.resolveBuiltIn(r'$randomInt')!);
        expect(n, greaterThanOrEqualTo(0));
        expect(n, lessThan(1000000));
      }
    });

    test(r'unknown built-in returns null (helps spot typos via render)', () {
      expect(EnvironmentManager.resolveBuiltIn(r'$notARealVar'), isNull);
      expect(EnvironmentManager.resolveBuiltIn('date'), isNull); // 缺 $ 前缀
    });

    test('builtInVariables list is consistent with resolveBuiltIn', () {
      final list = EnvironmentManager.builtInVariables;
      expect(list, isNotEmpty);
      // 列表里每一项都应能解析出非 null
      for (final entry in list) {
        expect(entry.key, startsWith(r'$'));
        final v = EnvironmentManager.resolveBuiltIn(entry.key);
        expect(v, isNotNull, reason: '${entry.key} should resolve');
        expect(v!.isNotEmpty, isTrue);
      }
      // 不应含重复 key
      final keys = list.map((e) => e.key).toSet();
      expect(keys.length, list.length);
    });
  });

  group('tryRender with built-in dispatch', () {
    test(r'{{$date}} embedded in template resolves', () {
      final out = EnvironmentManager.tryRender(r'today is {{$date}}')!;
      expect(out, matches(RegExp(r'^today is \d{4}-\d{2}-\d{2}$')));
    });

    test(r'{{$guid}} twice yields two different UUIDs', () {
      final out = EnvironmentManager.tryRender(r'a={{$guid}} b={{$guid}}')!;
      final matches = RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}')
          .allMatches(out)
          .toList();
      expect(matches.length, 2);
      expect(matches[0].group(0), isNot(equals(matches[1].group(0))));
    });

    test(r'{{$timestamp}} changes across calls (wait > 1s)', () async {
      final a = EnvironmentManager.tryRender(r'{{$timestamp}}')!;
      await Future.delayed(const Duration(milliseconds: 1100));
      final b = EnvironmentManager.tryRender(r'{{$timestamp}}')!;
      expect(a, isNot(equals(b)));
    }, timeout: const Timeout(Duration(seconds: 5)));

    test(r'unknown {{$bogus}} stays literal (helps spot typos)', () {
      final out = EnvironmentManager.tryRender(r'hello {{$bogus}} world')!;
      expect(out, r'hello {{$bogus}} world');
    });

    test(r'bare $date (no braces) stays literal', () {
      final out = EnvironmentManager.tryRender(r'price is $date today')!;
      expect(out, r'price is $date today');
    });

    test(r'{{us$er}} does not partial-match (regex sanity)', () {
      // 中间含 $ 的 token 不应被切成 `{{us}}` + 字面 `$er}}`。
      // 因为 `$?` 只在首字符,`[\w.\-]+` 不含 `$`。
      // 整体不匹配 → 保留字面。
      final out = EnvironmentManager.tryRender(r'{{us$er}}')!;
      expect(out, r'{{us$er}}');
    });

    test('tryRender short-circuits on null/empty/no-{{', () {
      expect(EnvironmentManager.tryRender(null), isNull);
      expect(EnvironmentManager.tryRender(''), '');
      expect(EnvironmentManager.tryRender('plain text'), 'plain text');
      expect(EnvironmentManager.tryRender(r'$date alone'), r'$date alone');
    });

    test('multiple built-ins in one string all resolve', () {
      final out = EnvironmentManager.tryRender(r'{{$date}}|{{$datetime}}|{{$timestampMs}}')!;
      final parts = out.split('|');
      expect(parts.length, 3);
      expect(parts[0], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(parts[1], matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$')));
      expect(parts[2], matches(RegExp(r'^\d{13}$')));
    });
  });
}
