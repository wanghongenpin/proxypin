import 'package:flutter/services.dart';

class InstalledApps {
  static const MethodChannel _methodChannel = MethodChannel('com.proxy/installedApps');

  static Future<List<AppInfo>> getInstalledApps(bool withIcon, {String? packageNamePrefix}) {
    return _methodChannel
        .invokeListMethod<Map>('getInstalledApps', {"withIcon": withIcon, "packageNamePrefix": packageNamePrefix}).then(
            (value) => value?.map((e) => AppInfo.formJson(e)).toList() ?? []);
  }

  static Future<AppInfo> getAppInfo(String packageName) async {
    return _methodChannel
        .invokeMethod<Map>('getAppInfo', {"packageName": packageName}).then((value) => AppInfo.formJson(value!));
  }
}

class AppInfo {
  String? name;
  String? packageName;
  String? versionName;

  //icon
  Uint8List? icon;

  bool? inValid;

  AppInfo({
    this.name,
    this.packageName,
    this.versionName,
    this.icon,
    this.inValid,
  });

  AppInfo.formJson(Map<dynamic, dynamic> json) {
    name = json['name'];
    packageName = json['packageName'];
    versionName = json['versionName'];
    icon = json['icon'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['name'] = name;
    data['packageName'] = packageName;
    data['versionName'] = versionName;
    data['icon'] = icon;
    return data;
  }

  @override
  String toString() {
    return toJson().toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is AppInfo) {
      return packageName == other.packageName;
    }
    return false;
  }

  @override
  int get hashCode => packageName.hashCode;
}
