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

    return Column(
      children: [

        SizedBox(height: 16),

        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'My Expenses',
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
                                      fontSize: 33,
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
                                final firstName = user?['firstname'] ?? '';
                                final lastName = user?['lastname'] ?? '';
                                final payerName = user != null ? '$firstName $lastName' : 'Unknown';

                                // Generate initials
                                final initials = [
                                  firstName.isNotEmpty ? firstName[0] : '',
                                  lastName.isNotEmpty ? lastName[0] : '',
                                ].join().toUpperCase();

                                // Generate a consistent color from the name
                                final colors = [
                                  [Color(0xFF6366F1), Color(0xFF8B5CF6)], // indigo-purple
                                  [Color(0xFF0EA5E9), Color(0xFF06B6D4)], // sky-cyan
                                  [Color(0xFF10B981), Color(0xFF059669)], // emerald
                                  [Color(0xFFF59E0B), Color(0xFFEF4444)], // amber-red
                                  [Color(0xFFEC4899), Color(0xFFA855F7)], // pink-purple
                                ];
                                final colorPair = colors[(firstName.codeUnitAt(0) + lastName.codeUnitAt(0)) % colors.length];

                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.04),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: colorPair,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            initials,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            payerName,
                                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                        Text(
                                          '₱${b['amount']}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white.withOpacity(0.65),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
