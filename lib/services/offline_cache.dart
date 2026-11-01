import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineCache {
  static String profileKey(String userId) => 'divido_offline_profile_$userId';
  static String groupsKey(String userId) => 'divido_offline_groups_$userId';
  static String expensesKey(String userId, String groupId) =>
      'divido_offline_expenses_${userId}_$groupId';
  static String dashboardKey(String userId, String groupId) =>
      'divido_offline_dashboard_${userId}_$groupId';

  static Future<Map<String, dynamic>?> readMap(String key) async {
    try {
      final value = (await SharedPreferences.getInstance()).getString(key);
      if (value == null) return null;
      final decoded = jsonDecode(value);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (error) {
      debugPrint('Offline cache read failed for $key: $error');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>?> readList(String key) async {
    try {
      final value = (await SharedPreferences.getInstance()).getString(key);
      if (value == null) return null;
      final decoded = jsonDecode(value);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (error) {
      debugPrint('Offline cache read failed for $key: $error');
      return null;
    }
  }

  static Future<void> write(String key, Object value) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        key,
        jsonEncode(
          value,
          toEncodable: (object) {
            if (object is DateTime) return object.toIso8601String();
            throw UnsupportedError(
              'Cannot cache ${object.runtimeType} in offline data.',
            );
          },
        ),
      );
    } catch (error) {
      debugPrint('Offline cache write failed for $key: $error');
    }
  }

  static Future<void> clearUser(String userId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final prefixes = [
        profileKey(userId),
        groupsKey(userId),
        'divido_offline_expenses_${userId}_',
        'divido_offline_dashboard_${userId}_',
      ];
      for (final key in preferences.getKeys()) {
        if (prefixes.any(key.startsWith)) {
          await preferences.remove(key);
        }
      }
    } catch (error) {
      debugPrint('Offline cache cleanup failed for user $userId: $error');
    }
  }
}
