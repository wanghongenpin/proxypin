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

import 'dart:io';

import 'package:proxypin/network/util/crts.dart';
import 'package:proxypin/ui/desktop/ssl/cert_installer.dart';

/// 查询桌面端根 CA 是否已安装/受信任。供 MCP get_certificate_status 调用。
///
/// @author wanghongen
class CertStatus {
  static Future<Map<String, dynamic>> query() async {
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      return {'available': false, 'platform': Platform.operatingSystem};
    }
    var caCert = CertificateManager.caCert;
    if (caCert == null) {
      return {'available': true, 'installed': false, 'reason': 'CA not initialized'};
    }
    try {
      var file = await CertificateManager.certificateFile();
      var installed = await CertInstaller.isCertInstalled(file, caCert);
      return {'available': true, 'installed': installed, 'commonName': caCert.subject['2.5.4.3']};
    } catch (e) {
      return {'available': true, 'installed': false, 'error': '$e'};
    }
  }
}
