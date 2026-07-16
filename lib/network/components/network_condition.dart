/*
 * Copyright 2025 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 */

import 'dart:async';
import 'dart:math';

import 'package:proxypin/network/components/interceptor.dart';
import 'package:proxypin/network/components/manager/network_condition_manager.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';

/// 弱网模拟拦截器：在请求/响应链路中注入延迟、丢包、离线，
/// 并按上/下行带宽对 body 进行整体等效限速（延迟 = bytes / kbps）。
///
/// 支持 issue #559 「按 URL 单独配置响应超时」的场景：通过
/// [NetworkConditionManager.resolve] 拿到每条 URL 的具体参数快照，
/// 规则未设置的字段回落到全局默认。
///
/// 说明：
/// - 转发管道以整条 HttpRequest/HttpResponse 为单位处理，
///   限速通过整体等效延迟实现（首字节延迟 + 传输时间）。
/// - 请求延迟发生在 onRequest；响应延迟 + 下行限速发生在 onResponse；
///   离线/丢包发生在 execute（短路，返回合成 502）。
///
/// @author wanghongen
class NetworkConditionInterceptor extends Interceptor {
  static final NetworkConditionInterceptor instance = NetworkConditionInterceptor._();

  NetworkConditionInterceptor._();

  final Random _random = Random();

  /// 尽量在末尾执行：延迟应发生在 rewrite / map / block 之后，
  /// 只对真正会真实转发的请求生效。priority 大于 block(1000)。
  @override
  int get priority => 1100;

  Future<NetworkConditionManager> get _manager async => NetworkConditionManager.instance;

  int _applyJitter(int base, int jitter) {
    if (jitter <= 0 || base < 0) return base < 0 ? 0 : base;
    final delta = _random.nextInt(jitter * 2 + 1) - jitter;
    final v = base + delta;
    return v < 0 ? 0 : v;
  }

  /// 根据带宽估算 body 的传输耗时。kbps 视作 kilobits/s（1 kbps = 125 B/s）。
  int _throttleMs(int bytes, int? kbps) {
    if (kbps == null || kbps <= 0 || bytes <= 0) return 0;
    return (bytes * 8 / kbps).ceil();
  }

  @override
  Future<HttpResponse?> execute(HttpRequest request) async {
    final mgr = await _manager;
    final eff = mgr.resolve(request.requestUrl);
    if (eff == null) return null;

    // 离线：直接返回 502，请求不会真的发出
    if (eff.offline) {
      logger.d('[${request.requestId}] weak-network offline: ${request.requestUrl}');
      return null;
    }

    // 丢包：按概率整包丢弃 -> 合成 502（模拟连接失败/超时）
    if (eff.lossRate > 0 && _random.nextDouble() < eff.lossRate) {
      logger.d('[${request.requestId}] weak-network loss: ${request.requestUrl}');
      final resp = HttpResponse(HttpStatus.newStatus(502, 'Weak Network: Packet Loss'),
          protocolVersion: request.protocolVersion)
        ..request = request;
      resp.headers.set('X-ProxyPin-Weak-Network', 'loss');
      return resp;
    }

    return null;
  }

  @override
  Future<HttpRequest?> onRequest(HttpRequest request) async {
    final mgr = await _manager;
    final eff = mgr.resolve(request.requestUrl);
    if (eff == null) return request;

    int delay = _applyJitter(eff.requestLatencyMs, eff.jitterMs);
    final bodyBytes = request.body?.length ?? 0;
    delay += _throttleMs(bodyBytes, eff.uploadKbps);
    if (delay > 0) {
      await Future.delayed(Duration(milliseconds: delay));
    }
    return request;
  }

  @override
  Future<HttpResponse?> onResponse(HttpRequest request, HttpResponse response) async {
    final mgr = await _manager;
    final eff = mgr.resolve(request.requestUrl);
    if (eff == null) return response;

    int delay = _applyJitter(eff.responseLatencyMs, eff.jitterMs);
    final bodyBytes = response.body?.length ?? 0;
    delay += _throttleMs(bodyBytes, eff.downloadKbps);
    if (delay > 0) {
      await Future.delayed(Duration(milliseconds: delay));
    }
    return response;
  }
}
