import 'dart:io';

void main() {
  NetworkInterface.list(type: InternetAddressType.IPv4).then((interfaces) {
    for (var interface in interfaces) {
      print(interface.name);
      for (var address in interface.addresses) {
        print("  ${address.address}");
        print("  ${address.host}");
        print("  ${address.type}");
      }
    }
  });
}

String? ip;

/// 获取本机ip (en0 or WLAN)优先
Future<String> localIp({bool readCache = true}) async {
  if (!readCache) {
    ip = null;
  }
  ip ??= await localAddress().then((value) => value.address);
  return ip!;
}

Future<InternetAddress> localAddress() async {
  return await NetworkInterface.list(type: InternetAddressType.IPv4).then((interfaces) {
    interfaces.sort((a, b) {
      return weight(a) - weight(b);
    });
    return interfaces.first.addresses.first;
  });
}

List<String>? ipList;

/// 获取本机所有ip
Future<List<String>> localIps({bool readCache = true}) async {
  if (readCache && ipList != null) {
    return ipList!;
  }

  var list = await NetworkInterface.list(type: InternetAddressType.IPv4);
  list.sort((a, b) {
    return weight(a) - weight(b);
  });

  ipList = [];
  for (var element in list) {
    if (!ipList!.contains(element.addresses.first.address)) {
      ipList?.add(element.addresses.first.address);
    }
  }
  return ipList!;
}

Future<String> networkName() {
  return NetworkInterface.list(type: InternetAddressType.IPv4).then((interfaces) {
    interfaces.sort((a, b) {
      return weight(a) - weight(b);
    });
    return interfaces.first.name;
  });
}

// en0(macos系统) or WLAN(widows设备名)优先
int weight(NetworkInterface it) {
  if (it.name.toUpperCase().startsWith('WLAN')) {
    return -10;
  }
  if (it.name == 'en0') {
    return -1;
  }
  if (it.name.startsWith('ccmn')) {
    return 0;
  }
  return 1;
}
