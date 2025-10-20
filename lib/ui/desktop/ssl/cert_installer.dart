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
        // Linux: 拷贝到 /usr/local/share/ca-certificates/ 并更新证书
        final certName = certFile.uri.pathSegments.last.endsWith('.crt')
            ? certFile.uri.pathSegments.last
            : '${certFile.uri.pathSegments.last}.crt';
        final destPath = '/usr/local/share/ca-certificates/$certName';
        await certFile.copy(destPath);
        final result = await Process.run('update-ca-certificates', []);
        logger.d('update-ca-certificates result: \\${result.stdout} \\${result.stderr}');
        return result.exitCode == 0;
      }

      // 其他平台暂不支持
      return false;
    } catch (e) {
      logger.e('Failed to install certificate: $e');
      return false;
    }
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
        // 只检查 /usr/local/share/ca-certificates/ 下是否有对应证书文件
        final certName = filePath.uri.pathSegments.last.endsWith('.crt')
            ? filePath.uri.pathSegments.last
            : '${filePath.uri.pathSegments.last}.crt';

        var paths = [
          '/usr/local/share/ca-certificates/$certName',
          '/etc/ssl/certs/$certName',
        ];
        for (var p in paths) {
          if (await File(p).exists()) return true;
        }
        return false;
      }
    } catch (_) {}
    return false;
  }
}
