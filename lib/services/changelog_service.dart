import 'package:shared_preferences/shared_preferences.dart';

class ChangelogService {
  // bump this version string every time you have new changes to show
  static const String _currentVersion = 'v0.4.0-beta';
  static const String _key = 'changelog_seen_version';

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getString(_key);
    return seen != _currentVersion;
  }

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _currentVersion);
  }
}