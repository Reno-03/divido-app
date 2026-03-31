import 'package:divido_app/providers/expense_provider.dart';
import 'package:divido_app/providers/group_provider.dart';
import 'package:divido_app/screens/edit_expense_modal.dart';
import 'package:divido_app/services/current_user.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
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

  void _confirmDelete(
    String expenseId,
    String expenseTitle,
    ExpenseProvider provider,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (context) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF171A3F),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title
              const Text(
                'Delete Expense',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),

              // Confirmation message with expense title
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                  children: [
                    const TextSpan(
                      text: 'Are you sure you want to delete the expense ',
                    ),
                    TextSpan(
                      text: expenseTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const TextSpan(text: '? This action cannot be undone.'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        try {
                          await supabase
                              .from('expenses')
                              .delete()
                              .eq('id', expenseId);
                          await provider.refresh(null);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Failed to delete expense.'),
                              ),
                            );
                          }
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.withValues(alpha: 0.15),
                        foregroundColor: Colors.red.shade400,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditExpenseModal({
    required String expenseId,
    required String currentTitle,
    required double currentTotal,
    required List<Map<String, dynamic>> breakdowns,
    required ExpenseProvider provider,
    required String currentDescription,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => EditExpenseModal(
        expenseId: expenseId,
        initialTitle: currentTitle,
        initialTotal: currentTotal,
        initialBreakdowns: breakdowns,
        initialDescription: currentDescription,
        onSaved: () => provider.refresh(null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expenseProvider = Provider.of<ExpenseProvider>(context);
    final currentUserId = CurrentUser.instance.id;

    if (expenseProvider.isLoading) {
      return Shimmer.fromColors(
        baseColor: Colors.white.withValues(alpha: 0.06),
        highlightColor: Colors.white.withValues(alpha: 0.15),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 5,
          itemBuilder: (_, __) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // date divider skeleton
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      const Expanded(child: Divider()),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        width: 120,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                ),
                // expense card skeleton
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  height: 250,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    final myExpenses = expenseProvider.expenses
        .where((expense) => expense['owner_id'] == currentUserId)
        .toList();

    if (myExpenses.isEmpty) {
      return const Center(child: Text('No expenses found'));
    }

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var expense in myExpenses) {
      final createdAt = DateTime.parse(expense['created_at'] + 'Z').toLocal();
      // print('Expense createdAt (local): $createdAt');
      final dateKey = DateFormat('yyyy-MM-dd').format(createdAt);
      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(expense);
    }

    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              final groupId = Provider.of<GroupProvider>(
                context,
                listen: false,
              ).selectedGroupId;
              if (groupId != null) await expenseProvider.refresh(groupId);
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Row(
                                            children: [
                                              // Using flexible will wrap the text if it is too long
                                              // But the the price still has fixed size
                                              Flexible(
                                                child: Text(
                                                  expense['title'] ?? '',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 20,
                                                    decoration: isPaid
                                                        ? TextDecoration
                                                              .lineThrough
                                                        : null,
                                                    decorationColor:
                                                        Colors.white54,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              // 👈 icon right beside the title
                                              GestureDetector(
                                                onTap: () => _showEditExpenseModal(
                                                  expenseId: expenseId,
                                                  currentTitle:
                                                      expense['title'] ?? '',
                                                  currentTotal:
                                                      (expense['total'] as num)
                                                          .toDouble(),
                                                  breakdowns:
                                                      (expense['expense_breakdowns']
                                                              as List<dynamic>)
                                                          .map(
                                                            (e) =>
                                                                Map<
                                                                  String,
                                                                  dynamic
                                                                >.from(
                                                                  e as Map,
                                                                ),
                                                          )
                                                          .toList(), // 👈 cast each element
                                                  currentDescription:
                                                      expense['description'] ??
                                                      '',
                                                  provider: expenseProvider,
                                                ),
                                                child: Container(
                                                  padding: const EdgeInsets.all(
                                                    5,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: 0.08,
                                                        ),
                                                  ),
                                                  child: Icon(
                                                    Icons.edit_outlined,
                                                    size: 18,
                                                    color: Colors.white
                                                        .withValues(alpha: 0.8),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          '₱ ${expense['total']}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 33,
                                            decoration: isPaid
                                                ? TextDecoration.lineThrough
                                                : null,
                                            decorationColor: Colors.white54,
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Description block (full-width background)
                                    if (expense['description'] != null &&
                                        expense['description']
                                            .toString()
                                            .isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
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
                                          child: Text(
                                            expense['description'],
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.white.withValues(
                                                alpha: 0.65,
                                              ),
                                            ),
                                          ),
                                        ),
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
                                              () {
                                                final avatarUrl =
                                                    user?['avatar_url']
                                                        as String?;
                                                return Container(
                                                  width: 32,
                                                  height: 32,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    gradient: LinearGradient(
                                                      begin: Alignment.topLeft,
                                                      end:
                                                          Alignment.bottomRight,
                                                      colors: [
                                                        userColor,
                                                        userColor.withValues(
                                                          alpha: 0.7,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  clipBehavior: Clip.antiAlias,
                                                  child:
                                                      avatarUrl != null &&
                                                          avatarUrl.isNotEmpty
                                                      ? Image.network(
                                                          avatarUrl,
                                                          fit: BoxFit.cover,
                                                          errorBuilder:
                                                              (
                                                                _,
                                                                _,
                                                                _,
                                                              ) => Center(
                                                                child: Text(
                                                                  initials,
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                                ),
                                                              ),
                                                        )
                                                      : Center(
                                                          child: Text(
                                                            initials,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                          ),
                                                        ),
                                                );
                                              }(),
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
                              Row(
                                children: [
                                  // Mark as Paid / Undo button
                                  Expanded(
                                    flex:
                                        3, // 👈 75% of width is occupied for mark as paid
                                    child: GestureDetector(
                                      onTap: () => _toggleExpensePaid(
                                        expenseId,
                                        isPaid,
                                        expenseProvider,
                                      ),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isPaid
                                              ? Colors.white.withValues(
                                                  alpha: 0.05,
                                                )
                                              : Colors.green.withValues(
                                                  alpha: 0.15,
                                                ),
                                          borderRadius: const BorderRadius.only(
                                            bottomLeft: Radius.circular(12),
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
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
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
                                  ),

                                  // Divider
                                  Container(
                                    width: 1,
                                    height: 50,
                                    color: Colors.white.withValues(alpha: 0.08),
                                  ),

                                  // Delete button
                                  Expanded(
                                    flex:
                                        1, // 👈 25% of width is occupied for delete button
                                    child: GestureDetector(
                                      onTap: () => _confirmDelete(
                                        expenseId,
                                        expense['title'] ??
                                            'Untitled', // 👈 pass the title here
                                        expenseProvider,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 13,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withValues(
                                            alpha: 0.10,
                                          ),
                                          borderRadius: const BorderRadius.only(
                                            bottomRight: Radius.circular(12),
                                          ),
                                          border: Border(
                                            top: BorderSide(
                                              color: Colors.red.withValues(
                                                alpha: 0.25,
                                              ),
                                            ),
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.delete_outline,
                                          size: 28,
                                          color: Colors.red.shade400,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
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
