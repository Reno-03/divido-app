import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/current_user.dart';
import '../services/offline_cache.dart';

class ExpenseProvider extends ChangeNotifier {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> get expenses => _expenses;

  bool _isLoading = false;
  bool get isLoading => _isLoading;
  bool _lastFetchSucceeded = false;
  bool get lastFetchSucceeded => _lastFetchSucceeded;

  String? _currentGroupId;
  int _fetchRequestId = 0;

  Future<void> fetchExpenses(String groupId) async {
    final requestId = ++_fetchRequestId;
    final groupChanged = _currentGroupId != groupId;

    _isLoading = true;
    _lastFetchSucceeded = false;
    _currentGroupId = groupId;
    if (groupChanged) {
      // Prevent stale items from previous group while the new group loads.
      _expenses = [];
    }
    notifyListeners();

    try {
      final userId = CurrentUser.instance.id;
      if (groupChanged && userId != null) {
        final cachedExpenses = await OfflineCache.readList(
          OfflineCache.expensesKey(userId, groupId),
        );
        if (requestId != _fetchRequestId || _currentGroupId != groupId) return;
        if (cachedExpenses != null) {
          _expenses = _normalizeExpenses(cachedExpenses);
          notifyListeners();
        }
      }

      final response = await supabase
          .from('expenses')
          .select('''
        *,
        profiles (id, firstname, lastname, color, avatar_url),
        expense_breakdowns (
          payer_id,
          amount,
          profiles (id, firstname, lastname, color, avatar_url)
        )
      ''')
          .eq('group_id', groupId) // filter by group
          .order('created_at', ascending: false);

      // Ignore stale responses from older requests/group selections.
      if (requestId != _fetchRequestId || _currentGroupId != groupId) return;

      final rawExpenses = response
          .map((expense) => Map<String, dynamic>.from(expense))
          .toList();
      if (userId != null) {
        await OfflineCache.write(
          OfflineCache.expensesKey(userId, groupId),
          rawExpenses,
        );
      }

      if (requestId != _fetchRequestId || _currentGroupId != groupId) return;
      _expenses = _normalizeExpenses(rawExpenses);
      _lastFetchSucceeded = true;
    } catch (error) {
      debugPrint('fetchExpenses error: $error');
    } finally {
      if (requestId == _fetchRequestId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  List<Map<String, dynamic>> _normalizeExpenses(
    List<Map<String, dynamic>> expenses,
  ) {
    final searchDateFormatter = DateFormat('MMMM d, yyyy');
    final searchDateKeyFormatter = DateFormat('yyyy-MM-dd');
    return expenses.map((expense) {
      final normalized = Map<String, dynamic>.from(expense);
      final rawCreatedAt = normalized['created_at'];
      if (rawCreatedAt is String) {
        final date = DateTime.parse(
          rawCreatedAt.endsWith('Z') ? rawCreatedAt : '${rawCreatedAt}Z',
        ).toLocal();
        normalized['search_title'] = (normalized['title'] as String? ?? '')
            .toLowerCase();
        normalized['search_date_str'] = searchDateFormatter
            .format(date)
            .toLowerCase();
        normalized['search_date_key'] = searchDateKeyFormatter.format(date);
        normalized['created_at_local'] = date;
      }
      return normalized;
    }).toList();
  }

  Future<void> refresh(String? groupId) async {
    final gid = groupId ?? _currentGroupId;
    if (gid == null) return;
    await fetchExpenses(gid);
  }

  void toggleExpensePaidLocally(String expenseId, bool newValue) {
    final idx = expenses.indexWhere((e) => e['id'] == expenseId);
    if (idx == -1) return;

    final updated = Map<String, dynamic>.from(expenses[idx]);
    updated['is_paid'] = newValue;
    updated['paid_at'] = newValue ? DateTime.now().toIso8601String() : null;
    expenses[idx] = updated;

    notifyListeners();
  }

  void setExpensesPaidLocally(List<String> expenseIds, bool newValue) {
    final ids = expenseIds.toSet();
    final paidAt = newValue ? DateTime.now().toIso8601String() : null;
    var changed = false;

    for (var i = 0; i < _expenses.length; i++) {
      if (!ids.contains(_expenses[i]['id'])) continue;

      _expenses[i] = {..._expenses[i], 'is_paid': newValue, 'paid_at': paidAt};
      changed = true;
    }

    if (changed) notifyListeners();
  }
}
