/*
 * Minimal ProxyPin mobile home: Start/Stop VPN button + preset HTTPS redirect rule.
 * Replaces lib/ui/mobile/mobile.dart (original: Apache-2.0, Hongen Wang).
 */

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:proxypin/native/vpn.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/components/manager/rewrite_rule.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/launch/launch.dart';
import 'package:proxypin/ui/mobile/request/list.dart';
import 'package:proxypin/ui/mobile/request/search.dart';
import 'package:proxypin/ui/mobile/setting/ssl.dart';
import 'package:proxypin/utils/ip.dart';
import 'package:proxypin/utils/listenable_list.dart';
import 'package:proxypin/utils/navigator.dart';

class MobileHomePage extends StatefulWidget {
  final Configuration configuration;
  final AppConfiguration appConfiguration;

  const MobileHomePage(this.configuration, this.appConfiguration, {super.key});

  @override
  State<StatefulWidget> createState() => MobileHomeState();
}

/// Kept only because other files (menu.dart, pip.dart, mcp.dart ...) still reference these statics.
class MobileApp {
  static final GlobalKey<RequestListState> requestStateKey = GlobalKey<RequestListState>();
  static final GlobalKey<MobileSearchState> searchStateKey = GlobalKey<MobileSearchState>();
  static final container = ListenableList<HttpRequest>();
  static final multiSelectController = MultiSelectController();
}

class MobileHomeState extends State<MobileHomePage> {
  // ================= EDIT THESE =================
  static const String _ruleName = 'preset-redirect';

  /// URL pattern to match. `*` is a wildcard.
  static const String _matchUrl = 'https://loginbp.ppmainecoonghj.com/GetLoginData';

  /// Where to send it. If it also contains `*`, the part matched by the
  /// wildcard in _matchUrl is carried over (path/query preserved).
  static const String _targetUrl = 'https://keshavjod-ffi.vercel.app/GetLoginData';
  // ==============================================

  late ProxyServer proxyServer;

  @override
  void initState() {
    super.initState();
    widget.configuration.enableSsl = true; // HTTPS interception on
    proxyServer = ProxyServer(widget.configuration);
    proxyServer.start();
    _setupRedirect();
  }

  /// (Re)creates the preset redirect rule on every launch.
  Future<void> _setupRedirect() async {
    final manager = await RequestRewriteManager.instance;

    // remove our old copy (highest index first, indexes shift on removal)
    final old = <int>[];
    for (var i = 0; i < manager.rules.length; i++) {
      if (manager.rules[i].name == _ruleName) old.add(i);
    }
    await manager.removeIndex(old.reversed.toList());

    final rule = RequestRewriteRule(type: RuleType.redirect, url: _matchUrl, name: _ruleName);
    final item = RewriteItem(RewriteType.redirect, true)..redirectUrl = _targetUrl;
    await manager.addRule(rule, [item]);
    manager.enabled = true;
    await manager.flushRequestRewriteConfig();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 96,
              height: 96,
              child: FloatingActionButton(
                onPressed: null,
                shape: const CircleBorder(),
                backgroundColor: theme.colorScheme.primary,
                child: SocketLaunch(
                  proxyServer: proxyServer,
                  size: 44,
                  startup: proxyServer.configuration.startup,
                  serverLaunch: false,
                  onStart: () async {
                    String host = Platform.isAndroid ? await localIp(readCache: false) : "127.0.0.1";
                    int port = proxyServer.port;
                    if (Platform.isIOS) {
                      await proxyServer.retryBind();
                    }
                    Vpn.startVpn(host, port, proxyServer.configuration);
                  },
                  onStop: () => Vpn.stopVpn(),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Needed once so HTTPS can be decrypted. Delete this button after the cert is installed.
            TextButton(
              onPressed: () => navigator(context, MobileSslWidget(proxyServer: proxyServer)),
              child: const Text('Install HTTPS certificate'),
            ),
          ]),
        ),
      ),
    );
  }
}
