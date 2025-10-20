import 'package:shared_preferences/shared_preferences.dart';

class LocalStorage {
  static Future<bool?> getBool(String key, {bool? defaultValue}) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? defaultValue;
  }

  static Future<void> setBool(String key, bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}
