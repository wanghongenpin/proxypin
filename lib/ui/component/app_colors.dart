/*
 * Copyright 2026 Hongen Wang
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

import 'package:flutter/material.dart';

/// 菜单/工具图标的语义色板（用户拍板，见 docs/design/homepage.html tag-6）：
/// 每功能固定一个语义色、全端一致，「8–10% 淡色底 + 降饱和彩色描边」，颜色即功能 ID；
/// 不用 iOS 实心色块，也不回退单色。不同功能复用同一色相是设计稿有意为之（色系成组）。
/// 状态类颜色（Method 语义色、运行绿、「N 条」生效绿）不在此列，仍走主题。
class AppColors {
  AppColors._();

  // ---- 配置页 ----
  static const favorite = Color(0xFFA8944F); // 收藏 · 橄榄黄
  static const history = Color(0xFF5A87AE); // 历史 · 钢蓝
  static const hosts = Color(0xFF54A396); // Hosts · 青绿
  static const requestBlock = Color(0xFFAF6052); // 请求屏蔽 · 红
  static const requestRewrite = Color(0xFFA8863E); // 请求重写 · 琥珀
  static const requestMap = Color(0xFF57916F); // 请求映射 · 绿
  static const requestCrypto = Color(0xFF8A6DB8); // 请求加密 · 紫
  static const script = Color(0xFF8080C6); // 脚本 · 靛蓝
  static const breakpoint = Color(0xFFAF6C94); // 断点 · 藕粉
  static const weakNetwork = Color(0xFFCE8359); // 弱网 · 橙
  static const environment = Color(0xFF7185D6); // 环境变量 · 蓝紫

  // ---- 设置页 ----
  static const httpsProxy = Color(0xFF57916F); // HTTPS 抓包 · 绿
  static const filter = Color(0xFFCE8359); // 域名过滤 · 橙
  static const proxyPort = Color(0xFF7185D6); // 代理端口 · 蓝紫
  static const socks5 = Color(0xFF64748B); // SOCKS5 · 石板灰（S5 字符块）
  static const http2 = Color(0xFF5A87AE); // HTTP/2 · 钢蓝（H2 字符块）
  static const proxyIgnoreDomain = Color(0xFF64748B); // 代理忽略域名 · 石板灰
  static const externalProxy = Color(0xFF54A396); // 外部代理 · 青绿
  static const mcp = Color(0xFF8A6DB8); // MCP 服务 · 紫
  static const preference = Color(0xFF8080C6); // 偏好设置 · 靛蓝
  static const about = Color(0xFF5A87AE); // 关于 · 钢蓝

  // ---- 工具箱 ----
  static const toolHttp = Color(0xFF7185D6);
  static const toolWebSocket = Color(0xFF8A6DB8);
  static const toolJavaScript = Color(0xFFA8863E);
  static const toolReplayTasks = Color(0xFF5A87AE);
  static const toolJson = Color(0xFF57916F);
  static const toolXml = Color(0xFFCE8359);
  static const toolTextDiff = Color(0xFF8080C6);
  static const toolTextEditor = Color(0xFF64748B); // 石板灰
  static const toolUrlEncoder = Color(0xFF54A396);
  static const toolBase64 = Color(0xFFAF6C94);
  static const toolUnicode = Color(0xFF9679D9);
  static const toolMd5 = Color(0xFF8A6D3B);
  static const toolAes = Color(0xFFAF6052);
  static const toolTimestamp = Color(0xFF55A0A0);
  static const toolCertHash = Color(0xFFA8944F);
  static const toolRegExp = Color(0xFF8284D2);
  static const toolQrCode = Color(0xFF3A3D42); // 近黑（暗色主题经 [icon] 提亮）

  /// 图标淡色底：浅色 10%；暗色提到 20% 保证色块可辨（只调透明度，不动色相/饱和度）
  static Color tint(Color color, Brightness brightness) =>
      color.withValues(alpha: brightness == Brightness.light ? 0.10 : 0.20);

  /// 图标描边色：暗色主题下过暗的色值（目前仅二维码近黑）提亮为中性灰，其余原样
  static Color icon(Color color, Brightness brightness) =>
      brightness == Brightness.dark && color.computeLuminance() < 0.08 ? const Color(0xFFAEB4BC) : color;
}
