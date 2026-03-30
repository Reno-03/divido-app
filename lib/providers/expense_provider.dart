import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExpenseProvider extends ChangeNotifier {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> get expenses => _expenses;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _currentGroupId;

  Future<void> fetchExpenses(String groupId) async {
    _isLoading = true;
    _currentGroupId = groupId;
    notifyListeners();

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

    _expenses = List<Map<String, dynamic>>.from(response).map((expense) {
      final e = Map<String, dynamic>.from(expense);

      // Parse date ONCE
      final createdAt = DateTime.parse(e['created_at'] + 'Z').toLocal();

      // Precompute searchable fields
      e['search_title'] = (e['title'] as String? ?? '').toLowerCase();

      e['search_date_str'] = DateFormat(
        'MMMM d, yyyy',
      ).format(createdAt).toLowerCase();

      e['search_date_key'] = DateFormat('yyyy-MM-dd').format(createdAt);

      // Store parsed DateTime 
      e['created_at_local'] = createdAt;

      return e;
    }).toList();
    _isLoading = false;
    notifyListeners();
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
}
