/// 详情面板视觉预览入口（非测试）：flutter run -d macos -t test/panel_preview_main.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/content/panel.dart';

void main() {
  var request = HttpRequest(HttpMethod.post, 'https://api.example.com/v1/orders/create?source=app&lang=zh',
      protocolVersion: 'HTTP/2');
  request.headers.contentType = 'application/json';
  request.headers.set('Cookie', 'session_id=abc123def456; theme=light; uid=10086');
  request.body = utf8.encode(jsonEncode({
    'sku': 'PRO-MONTHLY',
    'qty': 1,
    'coupon': 'NEW2026',
  }));
  request.packageSize = 1230;
  request.requestTime = DateTime.now().subtract(const Duration(milliseconds: 342));

  var response = HttpResponse(HttpStatus.ok, protocolVersion: 'HTTP/2');
  response.request = request;
  response.headers.contentType = 'application/json; charset=utf-8';
  response.headers.add('Set-Cookie', 'token=xyz789; Path=/; HttpOnly');
  response.headers.add('Set-Cookie', 'refresh=qrstuv; Path=/; Max-Age=86400');
  response.body = utf8.encode(const JsonEncoder.withIndent('  ').convert({
    'code': 0,
    'data': {
      'orderId': 'ORD-20261017-8842',
      'amount': 199.00,
      'status': 'PAID',
      'items': [
        {'sku': 'PRO-MONTHLY', 'qty': 1}
      ]
    },
    'traceId': 'b3f1c9a2e7'
  }));
  response.packageSize = 8600;
  response.remoteHost = '203.0.113.24';
  response.remotePort = 443;
  request.response = response;

  runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
          brightness: Brightness.light,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue, primary: Colors.blue, surface: Colors.white)),
      home: NetworkTabController(httpRequest: request, httpResponse: response, initialTab: 1)));
}
