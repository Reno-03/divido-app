import 'package:divido_app/providers/expense_provider.dart';
import 'package:divido_app/services/current_user.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  @override
  Widget build(BuildContext context) {
    final expenseProvider = Provider.of<ExpenseProvider>(context);
    final currentUserId = CurrentUser.instance.id;

    final myExpenses = expenseProvider.expenses
        .where((expense) => expense['owner_id'] == currentUserId)
        .toList();

    if (myExpenses.isEmpty) {
      return const Center(child: Text('No expenses found'));
    }

    // Group by date
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var expense in myExpenses) {
      final createdAt = DateTime.parse(expense['created_at']);
      final dateKey = DateFormat('yyyy-MM-dd').format(createdAt);

      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(expense);
    }

    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
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
                child: Text(
                  formattedDate,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
      
              ...expensesForDate.map((expense) {
                final breakdowns =
                    expense['expense_breakdowns'] as List<dynamic>? ?? [];
      
                final filteredBreakdowns = breakdowns
                    .where((b) => b['payer_id'] != currentUserId)
                    .toList();
      
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title + Total
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                expense['title'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                            Text(
                              '₱${expense['total']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                              ),
                            ),
                          ],
                        ),
      
                        const SizedBox(height: 12),
      
                        const Text(
                          'Payers:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
      
                        const SizedBox(height: 6),
      
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
    );
  }
}
