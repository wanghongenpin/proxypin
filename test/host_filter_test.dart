import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/components/host_filter.dart';

void main() {
  setUp(() {
    HostFilter.whitelist.list.clear();
    HostFilter.whitelist.enabled = false;
    HostFilter.blacklist.list.clear();
    HostFilter.blacklist.enabled = true;
  });

  group('HostFilter.filter with blacklist', () {
    test('returns false for null host', () {
      expect(HostFilter.filter(null), false);
    });

    test('returns false when blacklist is empty', () {
      expect(HostFilter.filter('example.com'), false);
    });

    test('returns true when host matches blacklist pattern', () {
      HostFilter.blacklist.add('*.apple.com');
      expect(HostFilter.filter('store.apple.com'), true);
    });

    test('returns false when host does not match blacklist', () {
      HostFilter.blacklist.add('*.apple.com');
      expect(HostFilter.filter('google.com'), false);
    });

    test('multiple blacklist entries work', () {
      HostFilter.blacklist.add('*.apple.com');
      HostFilter.blacklist.add('*.icloud.com');
      expect(HostFilter.filter('data.icloud.com'), true);
      expect(HostFilter.filter('example.com'), false);
    });
  });

  group('HostFilter.filter with whitelist', () {
    test('when whitelist enabled, non-matching hosts are filtered', () {
      HostFilter.whitelist.enabled = true;
      HostFilter.whitelist.add('*.example.com');
      expect(HostFilter.filter('api.example.com'), false);
      expect(HostFilter.filter('other.com'), true);
    });

    test('whitelist takes priority over blacklist', () {
      HostFilter.whitelist.enabled = true;
      HostFilter.whitelist.add('*.example.com');
      HostFilter.blacklist.add('*.example.com');
      expect(HostFilter.filter('api.example.com'), false);
    });
  });

  group('HostList operations', () {
    test('add converts * to .* pattern', () {
      HostFilter.blacklist.add('*.google.com');
      expect(HostFilter.blacklist.list.first.pattern, '.*.google.com');
    });

    test('add deduplicates patterns', () {
      HostFilter.blacklist.add('*.test.com');
      HostFilter.blacklist.add('*.test.com');
      expect(HostFilter.blacklist.list.length, 1);
    });

    test('remove removes pattern', () {
      HostFilter.blacklist.add('*.test.com');
      HostFilter.blacklist.remove('*.test.com');
      expect(HostFilter.blacklist.list.length, 0);
    });

    test('load populates from map', () {
      HostFilter.blacklist.load({
        'list': ['.*\\.blocked\\.com', '.*\\.spam\\.com'],
        'enabled': true,
      });
      expect(HostFilter.blacklist.list.length, 2);
      expect(HostFilter.blacklist.enabled, true);
    });

    test('load with null does nothing', () {
      HostFilter.blacklist.add('*.keep.com');
      HostFilter.blacklist.load(null);
      expect(HostFilter.blacklist.list.length, 1);
    });

    test('toJson serializes correctly', () {
      HostFilter.blacklist.add('*.blocked.com');
      HostFilter.blacklist.enabled = true;
      var json = HostFilter.blacklist.toJson();
      expect(json['enabled'], true);
      expect(json['list'], ['.*.blocked.com']);
    });

    test('removeIndex removes by index', () {
      HostFilter.blacklist.add('*.a.com');
      HostFilter.blacklist.add('*.b.com');
      HostFilter.blacklist.add('*.c.com');
      HostFilter.blacklist.removeIndex([1]);
      expect(HostFilter.blacklist.list.length, 2);
      expect(HostFilter.blacklist.list[0].pattern, '.*.a.com');
      expect(HostFilter.blacklist.list[1].pattern, '.*.c.com');
    });
  });
}
