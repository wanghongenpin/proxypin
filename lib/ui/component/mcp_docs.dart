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

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// MCP 集成文档地址（桌面面板与手机设置页共用），按界面语言区分中/英文页面。
Future<void> openMcpDoc(BuildContext context) async {
  var zh = Localizations.localeOf(context).languageCode == 'zh';
  var url = zh
      ? 'https://github.com/wanghongenpin/proxypin/wiki/MCP%E6%9C%8D%E5%8A%A1'
      : 'https://github.com/wanghongenpin/proxypin/wiki/MCP';
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
