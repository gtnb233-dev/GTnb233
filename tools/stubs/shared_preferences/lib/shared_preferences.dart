/// 静态分析桩：仅声明 AppSettings 用到的 API 形状。
library shared_preferences;

class SharedPreferences {
  SharedPreferences._();

  static Future<SharedPreferences> getInstance() async => SharedPreferences._();

  String? getString(String key) => null;
  int? getInt(String key) => null;
  bool? getBool(String key) => null;
  double? getDouble(String key) => null;
  List<String>? getStringList(String key) => null;

  Future<bool> setString(String key, String value) async => true;
  Future<bool> setInt(String key, int value) async => true;
  Future<bool> setBool(String key, bool value) async => true;
  Future<bool> setDouble(String key, double value) async => true;
  Future<bool> setStringList(String key, List<String> value) async => true;
  Future<bool> remove(String key) async => true;
  Future<bool> clear() async => true;
}
