import 'dart:io';
import 'package:proxypin/network/util/cert/cert_data.dart';
import 'package:proxypin/network/util/logger.dart';

class CertInstaller {
  static Future<bool> installCertificate(File certFile) async {
    try {
      if (Platform.isMacOS) {
        // 使用 security add-trusted-cert 安装证书到登录钥匙串并设为信任根
        final result = await Process.run('security', [
          'add-trusted-cert',
          '-r',
          'trustRoot',
          '-k',
          '${Platform.environment['HOME']}/Library/Keychains/login.keychain-db',
          certFile.path,
        ]);
        logger.d('security add-trusted-cert result: \\${result.stdout} \\${result.stderr}');
        return result.exitCode == 0;
      }

      if (Platform.isWindows) {
        // Windows: 使用 certutil 命令行安装证书到根证书存储区
        final result = await Process.run('certutil', [
          '-addstore',
          '-user',
          'Root',
          certFile.path,
        ]);
        logger.d('certutil addstore result: \\${result.stdout} \\${result.stderr}');
        return result.exitCode == 0;
      }

      if (Platform.isLinux) {
        return await installLinuxCertificate(certFile);
      }

      // 其他平台暂不支持
      return false;
    } catch (e) {
      logger.e('Failed to install certificate: $e');
      return false;
    }
  }

  /// 安装到系统库时使用的固定文件名，避免和用户其它 ca.crt 撞名
  static const String _anchorFileName = 'proxypin-ca.crt';
  static const String _debianAnchorDir = '/usr/local/share/ca-certificates';
  static const String _p11kitAnchorDir = '/etc/ca-certificates/trust-source/anchors';
  static const String _fedoraAnchorDir = '/etc/pki/ca-trust/source/anchors';

  static String _certFileName(File certFile) {
    final name = certFile.uri.pathSegments.last;
    return name.endsWith('.crt') ? name : '$name.crt';
  }

  /// Linux 没有统一的根证书库：
  ///  - Fedora/RHEL/openSUSE(Tumbleweed): /etc/pki/ca-trust/source/anchors + update-ca-trust
  ///  - Debian/Ubuntu: /usr/local/share/ca-certificates + update-ca-certificates
  ///  - Arch:          p11-kit 的 trust anchor + trust extract-compat
  /// 都需要 root，所以用 pkexec 触发 polkit 图形提权（只弹一次密码框）。
  static Future<bool> installLinuxCertificate(File certFile) async {
    String? anchorDir;
    List<String> refresh;
    if (File('/usr/bin/update-ca-trust').existsSync() && Directory(_fedoraAnchorDir).existsSync()) {
      anchorDir = _fedoraAnchorDir;
      refresh = ['update-ca-trust', 'extract'];
    } else if (File('/usr/bin/update-ca-certificates').existsSync()) {
      anchorDir = _debianAnchorDir;
      refresh = ['update-ca-certificates'];
    } else if (File('/usr/bin/trust').existsSync()) {
      anchorDir = _p11kitAnchorDir;
      refresh = ['trust', 'extract-compat'];
    } else {
      logger.w('No supported CA store found, please install ca-certificates-utils / ca-certificates');
      return false;
    }

    if (!Directory(anchorDir).existsSync()) {
      logger.w('CA anchor directory $anchorDir does not exist');
      return false;
    }

    final target = '$anchorDir/$_anchorFileName';
    final uid = (await Process.run('id', ['-u'])).stdout.toString().trim();
    bool success;

    if (uid == '0') {
      // 已经以 root 运行（例如自己 sudo 启动），直接装
      await certFile.copy(target);
      final result = await Process.run(refresh.first, refresh.sublist(1));
      logger.d('${refresh.first} result: ${result.stdout} ${result.stderr}');
      success = result.exitCode == 0;
    } else {
      // 一条 shell 里完成“拷贝 + 刷新”，避免弹两次密码框
      final refreshCommand = refresh.map((e) => "'$e'").join(' ');
      final script = 'install -Dm644 "\$1" "\$2" && $refreshCommand';
      try {
        final result = await Process.run('pkexec', ['sh', '-c', script, 'sh', certFile.path, target]);
        logger.d('pkexec install certificate (${result.exitCode}): ${result.stdout} ${result.stderr}');
        success = result.exitCode == 0;
        if (!success && (result.exitCode == 126 || result.exitCode == 127)) {
          logger.w('pkexec authorization failed (no polkit agent?), fall back to manual install');
        }
      } on ProcessException catch (e) {
        logger.e('pkexec not available: $e');
        success = false;
      }
    }

    if (success) {
      await installToNssDatabase(certFile);
    }
    return success;
  }

  /// Chrome/Chromium 在 Linux 上读的是 NSS 用户库（~/.pki/nssdb）而不是系统根证书库，
  /// 顺手装一份（这是用户级操作，不需要提权）。
  static Future<void> installToNssDatabase(File certFile) async {
    try {
      final home = Platform.environment['HOME'];
      if (home == null || !Directory('$home/.pki/nssdb').existsSync()) {
        return;
      }

      final result = await Process.run('certutil', [
        '-d',
        'sql:$home/.pki/nssdb',
        '-A',
        '-t',
        'C,,',
        '-n',
        'ProxyPin CA',
        '-i',
        certFile.path,
      ]);
      logger.d('certutil -A result: ${result.stdout} ${result.stderr}');
    } catch (e) {
      logger.w('Install certificate to NSS database skipped: $e');
    }
  }

  static bool _isLinuxCertInstalled(File certFile) {
    final legacyName = _certFileName(certFile);
    final names = {_anchorFileName, legacyName};
    const dirs = [
      _p11kitAnchorDir,
      '/etc/pki/trust/anchors', // openSUSE
      _debianAnchorDir,
      '/etc/ssl/certs',
    ];
    return dirs.any((dir) => names.any((name) => File('$dir/$name').existsSync()));
  }

  /// 检查证书是否已安装
  static Future<bool> isCertInstalled(File filePath, X509CertificateData caCert) async {
    String commonName = caCert.subject['2.5.4.3'] ?? 'ProxyPin CA';
    String? sha1 = caCert.sha1Thumbprint;
    logger.d('Checking if certificate is installed: CN=$commonName, SHA1=$sha1');
    try {
      if (Platform.isWindows) {
        List<String> args = ['-user', '-store', 'root'];
        if (sha1 != null) {
          args.add(sha1);
        }
        var res = await Process.run('certutil', args);
        return res.stdout.toString().toLowerCase().contains(commonName.toLowerCase());
      } else if (Platform.isMacOS) {
        var res = await Process.run('security', ['find-certificate', '-c', commonName]);

        if ((res.stdout as String).isNotEmpty) {
          // check if trusted
          var trustRes = await Process.run('security', ['verify-cert', '-c', filePath.path]);

          logger.d('security verify-cert $commonName result: ${trustRes.stdout} ${trustRes.stderr}');
          return (trustRes.stdout as String).contains('certificate verification successful');
        }
        return false;
      } else if (Platform.isLinux) {
        return _isLinuxCertInstalled(filePath);
      }
    } catch (_) {}
    return false;
  }
}
