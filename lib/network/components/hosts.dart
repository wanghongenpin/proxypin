/*
 * Copyright 2024 Hongen Wang All rights reserved.
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

import 'package:proxypin/network/components/manager/hosts_manager.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/util/logger.dart';

import 'interceptor.dart';

/// Hosts interceptor
/// @author wanghongen
class Hosts extends Interceptor {
  Future<HostsManager> get hostsManager async => await HostsManager.instance;

  @override
  int get priority => -1000;

  @override
  Future<HostAndPort> preConnect(HostAndPort hostAndPort) async {
    var host = hostAndPort.host;
    var hostsItem = await hostsManager.then((it) => it.getHosts(host));
    if (hostsItem != null) {
      logger.d('Hosts: $host -> ${hostsItem.toAddress}');
      return hostAndPort.copyWith(host: hostsItem.toAddress);
    }
    return hostAndPort;
  }
}
