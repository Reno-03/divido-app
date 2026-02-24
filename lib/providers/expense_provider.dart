import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExpenseProvider extends ChangeNotifier {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _expenses = [];

  List<Map<String, dynamic>> get expenses => _expenses;

  Future<void> fetchExpenses() async {
    final response = await supabase
        .from('expenses')
        .select('''
        *,
        profiles (id, firstname, lastname, color),
        expense_breakdowns (
          payer_id,
          amount,
          profiles (id, firstname, lastname, color)
        )
      ''')
        .order('created_at', ascending: false);

    _expenses = List<Map<String, dynamic>>.from(response);
    notifyListeners();
  }

  Future<void> refresh() async {
    await fetchExpenses();
  }

  void toggleExpensePaidLocally(String expenseId, bool newValue) {
    final idx = expenses.indexWhere((e) => e['id'] == expenseId);
    if (idx == -1) return;

    // expenses list items are maps from Supabase, make a mutable copy
    final updated = Map<String, dynamic>.from(expenses[idx]);
    updated['is_paid'] = newValue;
    updated['paid_at'] = newValue ? DateTime.now().toIso8601String() : null;
    expenses[idx] = updated;

    notifyListeners();
  }
}
