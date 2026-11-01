import 'package:divido_app/services/offline_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('stores and reads offline maps and lists', () async {
    await OfflineCache.write('test_map', {
      'saved_at': DateTime.utc(2026, 11, 1),
    });
    await OfflineCache.write('test_list', [
      {'id': 'expense-1', 'amount': 12.5},
    ]);

    expect(await OfflineCache.readMap('test_map'), {
      'saved_at': '2026-11-01T00:00:00.000Z',
    });
    expect(await OfflineCache.readList('test_list'), [
      {'id': 'expense-1', 'amount': 12.5},
    ]);
  });

  test('clears only the selected user offline data', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(OfflineCache.profileKey('user-1'), '{}');
    await preferences.setString(OfflineCache.groupsKey('user-1'), '{}');
    await preferences.setString(
      OfflineCache.expensesKey('user-1', 'group-1'),
      '[]',
    );
    await preferences.setString(
      OfflineCache.dashboardKey('user-1', 'group-1'),
      '{}',
    );
    await preferences.setString(OfflineCache.profileKey('user-2'), '{}');
    await preferences.setString('last_group_user-1', 'group-1');

    await OfflineCache.clearUser('user-1');

    expect(preferences.getKeys(), {
      'last_group_user-1',
      OfflineCache.profileKey('user-2'),
    });
  });
}
