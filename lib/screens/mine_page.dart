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

          if (!grouped.containsKey(dateKey)) {
            grouped[dateKey] = [];
          }
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
            final formattedDate =
                DateFormat('MMMM d, yyyy').format(DateTime.parse(dateKey));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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

                  // final ownerName = owner != null
                  //     ? '${owner['firstname'] ?? ''} ${owner['lastname'] ?? ''}'
                  //     : 'Unknown';

                  final payerNames = breakdowns
                      .where((b) => b['payer_id'] != ownerId)
                      .map((b) {
                        final user = b['users'];
                        if (user != null) {
                          return '${user['firstname'] ?? ''} ${user['lastname'] ?? ''}';
                        }
                        return 'Unknown';
                      })
                      .join(', ');

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text(
                        expense['title'] ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                      subtitle: Text('Payers: $payerNames'),
                      trailing: Text(
                        '₱ ${expense['total']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 30,
                        ),
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