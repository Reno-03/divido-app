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
          users (id, firstname, lastname),
          expense_breakdowns (
            payer_id,
            amount,
            users (id, firstname, lastname)
          )
        ''')
        .order('created_at', ascending: false);

    _expenses = List<Map<String, dynamic>>.from(response);

    notifyListeners(); // 🔥 triggers UI rebuild
  }

  Future<void> refresh() async {
    await fetchExpenses();
  }
}