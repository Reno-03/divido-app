import 'package:divido_app/services/current_user.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  final supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> fetchMyExpenses() async {
    final currentUserId = CurrentUser.instance.id;

    final response = await supabase
        .from('expenses')
        .select('''
          id,
          title,
          description,
          total,
          created_at,
          owner_id,
          users (id, firstname, lastname),
          expense_breakdowns (
            payer_id,
            amount,
            users (id, firstname, lastname)
          )
        ''')
        .eq('owner_id', currentUserId!)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: fetchMyExpenses(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Center(child: Text('Error loading expenses'));
        }

        final expenses = snapshot.data ?? [];
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

        final sortedDates = grouped.keys.toList()
          ..sort((a, b) => b.compareTo(a));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sortedDates.length,
          itemBuilder: (context, index) {
            final dateKey = sortedDates[index];
            final expensesForDate = grouped[dateKey]!;

            final formattedDate = DateFormat('MMMM d, yyyy')
                .format(DateTime.parse(dateKey));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date Header
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

                // Expenses for that date
                ...expensesForDate.map((expense) {
                  final breakdowns =
                      expense['expense_breakdowns'] as List<dynamic>? ?? [];

                  final filteredBreakdowns = breakdowns
                      .where((b) => b['payer_id'] != expense['owner_id'])
                      .toList();

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(25),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title + Total
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
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
                                  fontSize: 33,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          const Text(
                            'Payers:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 4),

                          // Breakdown list
                          ...filteredBreakdowns.map((b) {
                            final user = b['users'];
                            final payerName = user != null
                                ? '${user['firstname'] ?? ''} ${user['lastname'] ?? ''}'
                                : 'Unknown';

                            final amount = b['amount'];

                            return Padding(
                              padding:
                                  const EdgeInsets.only(left: 8, top: 4),
                              child: Text(
                                '• $payerName — ₱$amount',
                                style: const TextStyle(fontSize: 14),
                              ),
                            );
                          }),

                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }
}