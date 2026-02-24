import 'package:divido_app/providers/expense_provider.dart';
import 'package:divido_app/services/current_user.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  final supabase = Supabase.instance.client;

  Future<void> _toggleExpensePaid(
    String expenseId,
    bool current,
    ExpenseProvider provider,
  ) async {
    // 1. Update UI instantly
    provider.toggleExpensePaidLocally(expenseId, !current);

    // 2. Sync to Supabase in background
    try {
      await supabase
          .from('expenses')
          .update({
            'is_paid': !current,
            'paid_at': !current ? DateTime.now().toIso8601String() : null,
          })
          .eq('id', expenseId);
    } catch (e) {
      // Revert on failure
      provider.toggleExpensePaidLocally(expenseId, current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update. Please try again.')),
        );
      }
    }
  }

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

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var expense in myExpenses) {
      final createdAt = DateTime.parse(expense['created_at'] + 'Z').toLocal();
      print('Expense createdAt (local): $createdAt');
      final dateKey = DateFormat('yyyy-MM-dd').format(createdAt);
      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(expense);
    }

    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'My Expenses',
            style: TextStyle(fontSize: 35, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => await expenseProvider.refresh(),
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
                      final isPaid = expense['is_paid'] == true;
                      final expenseId = expense['id'] as String;
                      final breakdowns =
                          expense['expense_breakdowns'] as List<dynamic>? ?? [];
                      final filteredBreakdowns = breakdowns
                          .where((b) => b['payer_id'] != currentUserId)
                          .toList();

                      final ownerRawColor =
                          expense['profiles']?['color'] as String? ?? '#6366F1';
                      final ownerColor = Color(
                        int.parse(
                          'FF${ownerRawColor.replaceAll('#', '')}',
                          radix: 16,
                        ),
                      );

                      return Card(
                        color: ownerColor.withValues(alpha: 0.1), // subtle tint
                        margin: const EdgeInsets.only(bottom: 12),
                        child: AnimatedOpacity(
                          opacity: isPaid ? 0.45 : 1.0,
                          duration: const Duration(milliseconds: 300),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(25),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Title + Total
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            expense['title'] ?? '',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 20,
                                              decoration: isPaid
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                              decorationColor: Colors.white54,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          '₱ ${expense['total']}',
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
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),

                                    const SizedBox(height: 6),

                                    ...filteredBreakdowns.map((b) {
                                      final user = b['profiles'];
                                      final firstName =
                                          user?['firstname'] ?? '';
                                      final lastName = user?['lastname'] ?? '';
                                      final payerName = user != null
                                          ? '$firstName $lastName'
                                          : 'Unknown';

                                      final initials = [
                                        firstName.isNotEmpty
                                            ? firstName[0]
                                            : '',
                                        lastName.isNotEmpty ? lastName[0] : '',
                                      ].join().toUpperCase();

                                      // Get color from user data
                                      final rawColor =
                                          user?['color'] as String? ??
                                          '#6366F1';
                                      final userColor = Color(
                                        int.parse(
                                          'FF${rawColor.replaceAll('#', '')}',
                                          radix: 16,
                                        ),
                                      );
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.04,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
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
                                                    colors: [
                                                      userColor,
                                                      userColor.withValues(
                                                        alpha: 0.7,
                                                      ),
                                                    ],
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
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                '₱${b['amount']}',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.65),
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

                              // Full-width CTA at the bottom
                              GestureDetector(
                                onTap: () => _toggleExpensePaid(
                                  expenseId,
                                  isPaid,
                                  expenseProvider,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isPaid
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Colors.green.withValues(alpha: 0.15),
                                    borderRadius: const BorderRadius.only(
                                      bottomLeft: Radius.circular(12),
                                      bottomRight: Radius.circular(12),
                                    ),
                                    border: Border(
                                      top: BorderSide(
                                        color: isPaid
                                            ? Colors.white.withValues(
                                                alpha: 0.06,
                                              )
                                            : Colors.green.withValues(
                                                alpha: 0.25,
                                              ),
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isPaid
                                            ? Icons.undo_rounded
                                            : Icons
                                                  .check_circle_outline_rounded,
                                        size: 22,
                                        color: isPaid
                                            ? Colors.white.withValues(
                                                alpha: 0.3,
                                              )
                                            : Colors.green.shade400,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        isPaid ? 'Undo' : 'Mark as Paid',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          color: isPaid
                                              ? Colors.white.withValues(
                                                  alpha: 0.3,
                                                )
                                              : Colors.green.shade400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
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
