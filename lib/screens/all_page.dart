import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For formatting dates
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';

class AllPage extends StatefulWidget {
  const AllPage({super.key});

  @override
  State<AllPage> createState() => _AllPageState();
}

class _AllPageState extends State<AllPage> {
  final supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> fetchExpenses() async {
    final response = await supabase
        .from('expenses')
        .select('''
          id,
          title,
          description,
          total,
          created_at,
          users (id, firstname, lastname),
          expense_breakdowns (
            payer_id,
            amount,
            users (id, firstname, lastname)
          )
        ''')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Widget build(BuildContext context) {
    final expenseProvider = Provider.of<ExpenseProvider>(context);
    final expenses = expenseProvider.expenses;

    if (expenses.isEmpty) {
      return const Center(child: Text('No expenses found'));
    }

    // Group by date
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var expense in expenses) {
      final createdAt = DateTime.parse(expense['created_at']);
      final dateKey = DateFormat('yyyy-MM-dd').format(createdAt);

      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(expense);
    }

    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        
        SizedBox(height: 16),

        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'All Expenses',
            style: TextStyle(
              fontSize: 35,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        SizedBox(height: 16),

        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await expenseProvider.refresh();
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: sortedDates.length,
              itemBuilder: (context, index) {
                final dateKey = sortedDates[index];
                final expensesForDate = grouped[dateKey]!;
          
                final formattedDate = DateFormat(
                  'MMMM d, yyyy',
                ).format(DateTime.parse(dateKey));
          
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              formattedDate,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                    ),
                    ...expensesForDate.map((expense) {
                      final owner = expense['users'];
                      final ownerId = owner?['id'];
                      final breakdowns =
                          expense['expense_breakdowns'] as List<dynamic>? ?? [];
          
                      final ownerName = owner != null
                          ? '${owner['firstname']} ${owner['lastname']}'
                          : 'Unknown';
          
                      final filteredBreakdowns = breakdowns
                          .where((b) => b['payer_id'] != ownerId)
                          .toList();
          
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(25),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          expense['title'] ?? '',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 20,
                                          ),
                                        ),
                                        Text(ownerName),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '₱${expense['total']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 33,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Payers:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              ...filteredBreakdowns.map((b) {
                                final user = b['users'];
                                final payerName = user != null
                                    ? '${user['firstname']} ${user['lastname']}'
                                    : 'Unknown';
          
                                return Padding(
                                  padding: const EdgeInsets.only(left: 8, top: 4),
                                  child: Text('• $payerName — ₱${b['amount']}'),
                                );
                              }),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
