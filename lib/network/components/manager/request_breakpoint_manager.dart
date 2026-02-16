import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:path_provider/path_provider.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';


class RequestBreakpointRule {
  bool enabled;
  String? name;
  String url;

  bool interceptRequest;
  bool interceptResponse;

  // Optional HTTP method matching; null means match any method
  HttpMethod? method;

  RequestBreakpointRule({
    this.enabled = true,
    this.name,
    required this.url,
    this.interceptRequest = true,
    this.interceptResponse = true,
    this.method,
  });

  bool match(String url, {HttpMethod? method}) {
    if (!enabled) return false;
    if (this.method != null && method != null && this.method != method) return false;
    return url.contains(this.url);
  }

  factory RequestBreakpointRule.fromJson(Map<dynamic, dynamic> map) {
    HttpMethod? method;
    try {
      if (map['method'] != null) {
        method = HttpMethod.valueOf(map['method']);
      }
    } catch (e) {
      logger.e('Failed to parse HTTP method from request intercept rule', error: e);
    }

    return RequestBreakpointRule(
      enabled: map['enabled'] ?? true,
      name: map['name'],
      url: map['url'] ?? '',
      interceptRequest: map['interceptRequest'] ?? true,
      interceptResponse: map['interceptResponse'] ?? true,
      method: method,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'name': name,
      'url': url,
      'interceptRequest': interceptRequest,
      'interceptResponse': interceptResponse,
      'method': method?.name,
    };
  }
}

class RequestBreakpointManager {
  static RequestBreakpointManager? _instance;

  RequestBreakpointManager._();

  static Future<RequestBreakpointManager> get instance async {
    if (_instance == null) {
      _instance = RequestBreakpointManager._();
      await _instance!.load();
    }
    return _instance!;
  }

  bool enabled = true;
  List<RequestBreakpointRule> list = [];

  static Future<String> homePath() async {
    if (Platform.isMacOS) {
      return await DesktopMultiWindow.invokeMethod(0, "getApplicationSupportDirectory");
    }
    return await getApplicationSupportDirectory().then((it) => it.path);
  }

  Future<void> load() async {
    try {
      var home = await homePath();
      var file = File('$home${Platform.pathSeparator}request_intercept.json');
      if (await file.exists()) {
        var json = jsonDecode(await file.readAsString());
        enabled = json['enabled'] ?? false;
        list = (json['list'] as List? ?? []).map((e) => RequestBreakpointRule.fromJson(e)).toList();
      }
    } catch (e) {
      logger.e('Failed to load request intercept config', error: e);
    }
  }

  Future<void> save() async {
    try {
      var home = await homePath();
      var file = File('$home${Platform.pathSeparator}request_intercept.json');
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      var json = {
        'enabled': enabled,
        'list': list.map((e) => e.toJson()).toList(),
      };
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      logger.e('Failed to save request intercept config', error: e);
    }
  }

  void add(RequestBreakpointRule rule) {
    list.add(rule);
    save();
  }

  void remove(RequestBreakpointRule rule) {
    list.remove(rule);
    save();
  }
}
