import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/util/crts.dart';
import 'package:proxypin/network/util/system_proxy.dart';

const proxy = 'org.gnome.system.proxy';
const original = {
  '$proxy|mode': "'auto'",
  '$proxy|autoconfig-url': "'https://example.test/proxy.pac'",
  '$proxy.http|host': "'manual.example.test'",
  '$proxy.http|port': '3128',
  '$proxy.http|enabled': 'false',
  '$proxy.https|host': "'secure.example.test'",
  '$proxy.https|port': '443',
};

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory profile;
  late File backup;
  late LinuxSystemProxy backend;
  late Map<String, String> settings;
  late List<String> writes;
  String? rejectWrite;
  String? rejectRead;

  setUp(() async {
    profile = await Directory.systemTemp.createTemp('proxypin-proxy-test-');
    backup = File('${profile.path}/.proxypin/system_proxy_backup.json');
    settings = Map.of(original);
    writes = [];
    rejectRead = null;
    rejectWrite = null;
    backend = LinuxSystemProxy(
      environment: {'HOME': profile.path, 'XDG_CURRENT_DESKTOP': 'GNOME'},
      run: (tool, args) async {
        expect(tool, 'gsettings');
        final key = '${args[1]}|${args[2]}';
        if (args.first == 'get') {
          if (key == rejectRead) return ProcessResult(1, 1, '', 'read failed');
          return ProcessResult(1, 0, '${settings[key]}\n', '');
        }
        writes.add(key);
        if (key == rejectWrite) return ProcessResult(1, 0, '', 'failed to commit changes');
        settings[key] = args[3];
        return ProcessResult(1, 0, '', '');
      },
    );
  });

  tearDown(() => profile.delete(recursive: true));

  test('restores PAC mode and existing manual endpoints', () async {
    await backend.enable(9099, true);
    expect(settings['$proxy|mode'], "'manual'");
    expect(settings['$proxy.https|port'], '9099');
    expect(backup.existsSync(), isTrue);
    await backend.restore();
    expect(settings, original);
    expect(backup.existsSync(), isFalse);
  });

  test('failed snapshot read prevents writing any proxy settings', () async {
    rejectRead = '$proxy.https|host';
    await expectLater(backend.enable(9099, true), throwsStateError);
    expect(writes, isEmpty);
    expect(backup.existsSync(), isFalse);
  });

  test('failed snapshot creation leaves all proxy settings intact', () async {
    await File(backup.parent.path).create();
    await expectLater(backend.enable(9099, true), throwsA(isA<FileSystemException>()));
    expect(writes, isEmpty);
    expect(settings, original);
  });

  test('retains the backup and retries after a failed restore', () async {
    await backend.enable(9099, false);
    final saved = await backup.readAsString();
    rejectWrite = '$proxy.https|host';
    await expectLater(backend.restore(), throwsStateError);
    expect(await backup.readAsString(), saved);
    expect(settings['$proxy|mode'], "'manual'");
    rejectWrite = null;
    await backend.restore();
    expect(settings, original);
    expect(backup.existsSync(), isFalse);
  });

  test('rolls back a partially applied proxy configuration', () async {
    rejectWrite = '$proxy.https|port';
    await expectLater(backend.enable(9099, true), throwsStateError);
    expect(settings, original);
    expect(backup.existsSync(), isFalse);
  });

  test('without a backup, stopping never disables the original PAC', () async {
    await backend.restore();
    expect(writes, isEmpty);
    expect(settings, original);
  });

  test('rejects an incomplete legacy GNOME backup before restoring', () async {
    await backup.create(recursive: true);
    await backup.writeAsString('{"gsettings":{"$proxy|mode":"none"},"kioslaverc":{}}');
    await expectLater(backend.restore(), throwsFormatException);
    expect(writes, isEmpty);
    expect(backup.existsSync(), isTrue);
  });

  test('rejects an incomplete KIO backup without treating missing keys as unset', () async {
    await backup.create(recursive: true);
    await backup.writeAsString('{"kioslaverc":{"ProxyType":"2"}}');
    await expectLater(backend.restore(), throwsFormatException);
    expect(backup.existsSync(), isTrue);
  });

  final lifecycleHome = Platform.environment['PROXYPIN_TEST_LIFECYCLE_HOME'];
  test('an immediate stop waits for startup and restores the system proxy', () async {
    final environment = Platform.environment;
    expect(lifecycleHome, startsWith('${Directory.systemTemp.path}/proxypin-lifecycle-'));
    expect(environment['HOME'], lifecycleHome);
    expect(environment['XDG_CONFIG_HOME'], '$lifecycleHome/config');
    expect(environment['XDG_DATA_HOME'], '$lifecycleHome/data');
    expect(environment['GSETTINGS_BACKEND'], 'keyfile');
    expect(environment['XDG_CURRENT_DESKTOP'], 'GNOME');

    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, (call) async {
      expect(call.method, 'getApplicationSupportDirectory');
      return '$lifecycleHome/data';
    });
    addTearDown(() => binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null));

    final originalMode = await Process.run('gsettings', ['set', proxy, 'mode', "'auto'"]);
    expect(originalMode.exitCode, 0, reason: '${originalMode.stderr}');
    final server = ProxyServer(Configuration.fromJson({'port': 0, 'enableSystemProxy': true}));
    addTearDown(server.stop);
    final lifecycleBackup = File('$lifecycleHome/.proxypin/system_proxy_backup.json');

    final start = server.start();
    final stop = server.stop();
    final listener = await start;
    expect(await stop, same(listener));
    expect(server.isRunning, isFalse);
    final mode = await Process.run('gsettings', ['get', proxy, 'mode']);
    expect(mode.stdout.toString().trim(), "'auto'");
    expect(lifecycleBackup.existsSync(), isFalse);

    await server.start();
    final enabledMode = await Process.run('gsettings', ['get', proxy, 'mode']);
    expect(enabledMode.stdout.toString().trim(), "'manual'");
    final snapshot = await lifecycleBackup.readAsString();
    try {
      await lifecycleBackup.writeAsString('{}');
      await expectLater(server.stop(), throwsFormatException);
      expect(server.isRunning, isTrue);
      expect(await lifecycleBackup.readAsString(), '{}');
    } finally {
      await lifecycleBackup.writeAsString(snapshot);
    }
    await server.stop();
    expect(server.isRunning, isFalse);
    await CertificateManager.initCAConfig();
  }, skip: !Platform.isLinux || lifecycleHome == null);

  test('real Plasma and GNOME proxy commands round-trip in isolated profiles', () async {
    final config = await Directory('${profile.path}/config').create();
    final runtime = await Directory('${profile.path}/runtime').create();
    await Process.run('chmod', ['700', runtime.path]);
    final environment = {'HOME': profile.path, 'XDG_CONFIG_HOME': config.path, 'XDG_RUNTIME_DIR': runtime.path};
    Future<ProcessResult> command(String tool, List<String> args) async {
      final result = await Process.run('dbus-run-session', ['--', tool, ...args], environment: environment);
      return ProcessResult(
        result.pid,
        result.exitCode,
        result.stdout,
        (result.stderr as String).split('\n').where((line) => !line.startsWith('dbus-daemon[')).join('\n'),
      );
    }

    Future<String> getGnome(String schema, String key) async {
      final result = await command('gsettings', ['get', schema, key]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return (result.stdout as String).trim();
    }

    final gnome = LinuxSystemProxy(environment: {...environment, 'XDG_CURRENT_DESKTOP': 'GNOME'}, run: command);
    for (final (key, value) in [('$proxy|autoconfig-url', original['$proxy|autoconfig-url']!), ('$proxy|mode', "'auto'")]) {
      final result = await command('gsettings', ['set', ...key.split('|'), value]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }
    expect(await getGnome(proxy, 'mode'), "'auto'");
    await gnome.enable(9099, true);
    expect(await getGnome('$proxy.https', 'port'), '9099');
    await gnome.restore();
    expect(await getGnome(proxy, 'mode'), "'auto'");
    expect(await getGnome(proxy, 'autoconfig-url'), original['$proxy|autoconfig-url']);

    final kde = LinuxSystemProxy(environment: {...environment, 'XDG_CURRENT_DESKTOP': 'KDE'}, run: command);
    final configFile = File('${config.path}/kioslaverc');
    await configFile.writeAsString('[Proxy Settings]\nProxyType=2\nProxy Config Script=https://example.test/kio.pac\n');
    await kde.enable(9099, true);
    expect(await configFile.readAsString(), contains('httpProxy=http://127.0.0.1:9099'));
    await kde.restore();
    final restored = await configFile.readAsString();
    expect(restored, contains('ProxyType=2'));
    expect(restored, contains('Proxy Config Script=https://example.test/kio.pac'));
    expect(restored, isNot(contains('httpProxy=')));
    expect(restored, isNot(contains('httpsProxy=')));
    expect(backup.existsSync(), isFalse);
  }, skip: Platform.environment['PROXYPIN_TEST_REAL_DESKTOP_PROXY'] != '1');
}
