import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For formatting dates
import 'package:supabase_flutter/supabase_flutter.dart';

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
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: fetchExpenses(),
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

        // Group expenses by date (yyyy-MM-dd)
        final Map<String, List<Map<String, dynamic>>> grouped = {};
        for (var expense in expenses) {
          final createdAt = DateTime.parse(expense['created_at']);
          final dateKey = DateFormat('yyyy-MM-dd').format(createdAt);

          if (!grouped.containsKey(dateKey)) {
            grouped[dateKey] = [];
          }
          grouped[dateKey]!.add(expense);
        }

        // Sort dates descending
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
                // Date divider/header
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    formattedDate,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                ...expensesForDate.map((expense) {
                  final owner = expense['users'];
                  final ownerId = owner?['id'];
                  final breakdowns =
                      expense['expense_breakdowns'] as List<dynamic>? ?? [];

                  final ownerName = owner != null
                      ? '${owner['firstname'] ?? ''} ${owner['lastname'] ?? ''}'
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
                            crossAxisAlignment: CrossAxisAlignment.center,
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
                                    Text(ownerName)
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
                              padding: const EdgeInsets.only(left: 8, top: 4),
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