import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/ui/component/app_colors.dart';
import 'package:proxypin/ui/component/multi_window.dart';
import 'package:proxypin/ui/desktop/left_menus/replay_tasks.dart' as desktop;
import 'package:proxypin/ui/mobile/request/replay_tasks.dart';
import 'package:proxypin/ui/mobile/request/request_editor.dart';
import 'package:proxypin/ui/toolbox/qr_code_page.dart';
import 'package:proxypin/ui/toolbox/regexp.dart';
import 'package:proxypin/ui/toolbox/timestamp.dart';
import 'package:proxypin/utils/platform.dart';

import 'aes_page.dart';
import 'cert_hash.dart';
import 'encoder.dart';
import 'js_run.dart';
import 'json_viewer.dart';
import 'text_diff.dart';
import 'text_editor.dart';
import 'websocket_request.dart';
import 'xml_viewer.dart';

class Toolbox extends StatefulWidget {
  final ProxyServer? proxyServer;

  const Toolbox({super.key, this.proxyServer});

  @override
  State<StatefulWidget> createState() {
    return _ToolboxState();
  }
}

class _ToolboxState extends State<Toolbox> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  /// 手机端宫格横向收紧（间距 4、项水平 padding 8、按内容定宽），保证 4 项一行整屏放下；桌面端不变
  bool get mobile => Platforms.isMobile();

  /// 分组容器：手机端 = 设计稿 p-sec2 小灰标题 + p-tbcard 白卡宫格（与配置/设置页白卡同一语言）；
  /// 桌面端 = Divider + 14px 标题 + 裸宫格（首组无标题，[desktopHeader] 控制）
  Widget _group(String label, List<Widget> items, {bool desktopHeader = true}) {
    var theme = Theme.of(context);
    if (mobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 5),
            child: Text(label,
                style:
                    TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurfaceVariant))),
        Container(
            // start 对齐的 Column 里必须显式拉满，否则 Wrap 按内容收缩、4 列变 3 列
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 2),
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
            decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.55)),
                borderRadius: BorderRadius.circular(10)),
            child: Wrap(children: items)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (desktopHeader) ...[
        const Divider(thickness: 0.3),
        // 设计稿 .tb-sec：12px 灰标签
        Text(label,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurfaceVariant)),
      ],
      Wrap(spacing: 6, children: items),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return IconTheme(
        // 设计稿 .tb-item svg：20px（全局 IconTheme 统一，移动端共用）
        data: IconTheme.of(context).copyWith(color: IconTheme.of(context).color?.withValues(alpha: 0.65), size: 20),
        child: SingleChildScrollView(
            child: Container(
          // 手机端卡片/标题自带水平留白（桌面端保持 10）
          padding: mobile ? EdgeInsets.zero : const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _group(localizations.request, [
                  IconText(
                    icon: Icons.http,
                    text: "HTTP",
                    color: AppColors.toolHttp,
                    onTap: httpRequest,
                    tooltip: localizations.httpRequest,
                  ),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context)
                              .push(MaterialPageRoute(builder: (context) => const WebSocketRequestPage()));
                          return;
                        }
                        MultiWindow.openWindow('WebSocket', 'WebSocketRequestPage', size: const Size(800, 600));
                      },
                      icon: Icons.wifi_tethering,
                      text: 'WebSocket',
                      color: AppColors.toolWebSocket,
                      tooltip: 'WebSocket'),
                  IconText(
                    icon: Icons.javascript,
                    text: 'JavaScript',
                    color: AppColors.toolJavaScript,
                    tooltip: 'JavaScript',
                    onTap: () async {
                      if (Platforms.isMobile()) {
                        Navigator.of(context).push(MaterialPageRoute(builder: (context) => const JavaScript()));
                        return;
                      }

                      var size = MediaQuery.of(context).size;
                      MultiWindow.openWindow('JavaScript', 'JavaScript', size: Size(960, size.height));
                    },
                  ),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context)
                              .push(MaterialPageRoute(builder: (context) => const ReplayTasksPage()));
                          return;
                        }
                        desktop.showReplayTasksDialog(context);
                      },
                      icon: Icons.schedule_outlined,
                      text: localizations.replayTasks,
                      color: AppColors.toolReplayTasks,
                      tooltip: localizations.replayTasks),
              ], desktopHeader: false),
              _group(localizations.view, [
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const JsonViewerPage()));
                          return;
                        }
                        MultiWindow.openWindow("JSON Viewer", 'JsonViewerPage', size: const Size(780, 820));
                      },
                      icon: Icons.data_object,
                      text: 'JSON',
                      color: AppColors.toolJson),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const XmlViewerPage()));
                          return;
                        }
                        MultiWindow.openWindow("XML Viewer", 'XmlViewerPage', size: const Size(900, 700));
                      },
                      icon: Icons.code,
                      text: 'XML',
                      color: AppColors.toolXml),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TextDiffPage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.textDiff, 'TextDiffPage', size: const Size(1100, 720));
                      },
                      icon: Icons.difference_outlined,
                      text: localizations.textDiff,
                      color: AppColors.toolTextDiff),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TextEditorPage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.textEditor, 'TextEditorPage', size: const Size(900, 800));
                      },
                      icon: Icons.note_alt_outlined,
                      text: localizations.textEditor,
                      color: AppColors.toolTextEditor,
                      tooltip: localizations.textEditor),
              ]),
              _group(localizations.encode, [
                  IconText(
                    onTap: () => encodeWindow(EncoderType.url, context),
                    icon: Icons.link,
                    text: 'URL',
                    color: AppColors.toolUrlEncoder,
                    tooltip: 'URL Encode/Decode',
                  ),
                  IconText(
                    onTap: () => encodeWindow(EncoderType.base64, context),
                    icon: Icons.format_bold_outlined,
                    text: 'Base64',
                    color: AppColors.toolBase64,
                    tooltip: 'Base64 Encode/Decode',
                  ),
                  IconText(
                    onTap: () => encodeWindow(EncoderType.unicode, context),
                    icon: Icons.format_underline_outlined,
                    text: 'Unicode',
                    color: AppColors.toolUnicode,
                    tooltip: 'Unicode Encode/Decode',
                  ),
                  IconText(
                    onTap: () => encodeWindow(EncoderType.md5, context),
                    icon: Icons.tag_outlined,
                    text: 'MD5',
                    color: AppColors.toolMd5,
                    tooltip: 'MD5 Hash',
                  ),
              ]),
              _group(localizations.cipher, [
                  IconText(
                    onTap: () {
                      if (Platforms.isMobile()) {
                        Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AesPage()));
                        return;
                      }
                      MultiWindow.openWindow("AES", "AesPage", size: const Size(700, 672));
                    },
                    icon: Icons.enhanced_encryption_outlined,
                    text: 'AES',
                    color: AppColors.toolAes,
                    tooltip: 'AES Encrypt/Decrypt',
                  ),
              ]),
              _group(localizations.other, [
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TimestampPage()));
                          return;
                        }

                        MultiWindow.openWindow(localizations.timestamp, 'TimestampPage', size: const Size(700, 350));
                      },
                      icon: Icons.av_timer,
                      text: localizations.timestamp,
                      color: AppColors.toolTimestamp,
                      tooltip: localizations.timestamp),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const CertHashPage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.certHashName, 'CertHashPage');
                      },
                      icon: Icons.key_outlined,
                      color: AppColors.toolCertHash,
                      // 宫格列宽有限，手机端用短名（tooltip 仍是全称）
                      text: mobile ? localizations.certHashShort : localizations.certHashName,
                      tooltip: localizations.certHashName),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const RegExpPage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.regExp, 'RegExpPage', size: const Size(800, 720));
                      },
                      icon: Icons.find_in_page_outlined,
                      text: localizations.regExp,
                      color: AppColors.toolRegExp,
                      tooltip: localizations.regExp),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const QrCodePage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.qrCode, 'QrCodePage');
                      },
                      icon: Icons.qr_code_2,
                      text: localizations.qrCode,
                      color: AppColors.toolQrCode,
                      tooltip: localizations.qrCode),
              ]),
            ],
          ),
        )));
  }

  Future<void> httpRequest() async {
    if (Platforms.isMobile()) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (context) => MobileRequestEditor(proxyServer: widget.proxyServer)));
      return;
    }

    var size = MediaQuery.of(context).size;

    MultiWindow.openWindow(localizations.httpRequest, "RequestEditor", size: Size(960, size.height));
  }
}

class IconText extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? tooltip;

  /// 手机端宫格块的语义色（AppColors，设计稿 tic 彩色淡色块）；桌面端不使用
  final Color color;

  /// Called when the user taps this part of the material.
  final GestureTapCallback? onTap;

  const IconText({super.key, required this.icon, required this.text, required this.color, this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = text;
    final mobile = Platforms.isMobile();
    // 手机端按设计稿 p-tbt：卡内 25% 定宽（卡 margin 12*2 + 卡 padding 4*2），
    // 图标收进 48px 语义色淡色块（8–10% 淡底 + 降饱和彩色图标，设计稿 38/19 按真机可读性放大 1.25），
    // 12.5px 标签；图标沿用现有 Material 图标
    // （卡 margin 12*2 + 卡 padding 4*2 + 卡 border 1*2 ≈ 34，再留 6px 防浮点舍入折行）
    final cellWidth = mobile ? (MediaQuery.of(context).size.width - 40) / 4 : null;
    return Tooltip(
      message: tooltip ?? label,
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: theme.colorScheme.primary.withValues(alpha: 0.06),
          splashColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: Container(
            width: cellWidth,
            // 桌面端按设计稿 .tb-item 收紧：宽 84、内边距 8/9、12.5px 标签（原 92 / 12/10 / 14px 偏大）
            padding: EdgeInsets.symmetric(horizontal: mobile ? 4 : 8, vertical: mobile ? 4 : 9),
            constraints: mobile ? null : const BoxConstraints(minWidth: 84),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (mobile)
                  Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: AppColors.tint(color, theme.brightness),
                          borderRadius: BorderRadius.circular(12)),
                      child: Center(
                          child: IconTheme(
                              data: IconThemeData(size: 24, color: AppColors.icon(color, theme.brightness)),
                              child: Icon(icon))))
                else
                  Icon(icon),
                SizedBox(height: mobile ? 5 : 6),
                Text(label, style: const TextStyle(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
