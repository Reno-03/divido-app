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
            style: TextStyle(fontSize: 35, fontWeight: FontWeight.bold),
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

                      // Get owner color
                      final ownerRawColor =
                          expense['users']?['color'] as String? ?? '#6366F1';
                      final ownerColor = Color(
                        int.parse(
                          'FF${ownerRawColor.replaceAll('#', '')}',
                          radix: 16,
                        ),
                      );

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: ownerColor.withValues(alpha: 0.1), // subtle tint
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: ownerColor, width: 5),
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(25),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            expense['title'] ?? '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 20,
                                            ),
                                          ),
                                          Text(
                                            ownerName,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Color.fromARGB(
                                                137,
                                                255,
                                                255,
                                                255,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '₱ ${expense['total']}',
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
                                  final firstName = user?['firstname'] ?? '';
                                  final lastName = user?['lastname'] ?? '';
                                  final payerName = user != null
                                      ? '$firstName $lastName'
                                      : 'Unknown';

                                  // Generate initials
                                  final initials = [
                                    firstName.isNotEmpty ? firstName[0] : '',
                                    lastName.isNotEmpty ? lastName[0] : '',
                                  ].join().toUpperCase();

                                  // Generate a consistent color from the name
                                  final colors = [
                                    [
                                      Color(0xFF6366F1),
                                      Color(0xFF8B5CF6),
                                    ], // indigo-purple
                                    [
                                      Color(0xFF0EA5E9),
                                      Color(0xFF06B6D4),
                                    ], // sky-cyan
                                    [
                                      Color(0xFF10B981),
                                      Color(0xFF059669),
                                    ], // emerald
                                    [
                                      Color(0xFFF59E0B),
                                      Color(0xFFEF4444),
                                    ], // amber-red
                                    [
                                      Color(0xFFEC4899),
                                      Color(0xFFA855F7),
                                    ], // pink-purple
                                  ];
                                  // final colorPair = colors[(firstName.codeUnitAt(0) + lastName.codeUnitAt(0)) % colors.length];
                                  // Get color from user data
                                  final rawColor =
                                      user?['color'] as String? ?? '#6366F1';
                                  final userColor = Color(
                                    int.parse(
                                      'FF${rawColor.replaceAll('#', '')}',
                                      radix: 16,
                                    ),
                                  );

                                  // // Get owner color
                                  // final ownerRawColor =
                                  //     expense['users']?['color'] as String? ??
                                  //     '#6366F1';
                                  // final ownerColor = Color(
                                  //   int.parse(
                                  //     'FF${ownerRawColor.replaceAll('#', '')}',
                                  //     radix: 16,
                                  //   ),
                                  // );

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
                                              color: Colors.white.withOpacity(
                                                0.65,
                                              ),
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
