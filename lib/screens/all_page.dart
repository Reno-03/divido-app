import 'package:divido_app/providers/group_provider.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For formatting dates
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import 'dart:async';

class AllPage extends StatefulWidget {
  const AllPage({super.key});

  @override
  State<AllPage> createState() => _AllPageState();
}

class _AllPageState extends State<AllPage> {
  final supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (_debounce?.isActive ?? false) {
        _debounce!.cancel();
      }

      _debounce = Timer(const Duration(milliseconds: 400), () {
        if (!mounted) return;

        setState(() {
          _searchQuery = _searchController.text.trim().toLowerCase();
        });
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expenseProvider = Provider.of<ExpenseProvider>(context);
    final allExpenses = expenseProvider.expenses;
    final expenses = _searchQuery.isEmpty
        ? allExpenses
        : allExpenses.where((expense) {
            return expense['search_title'].contains(_searchQuery) ||
                expense['search_date_str'].contains(_searchQuery) ||
                expense['search_date_key'].contains(_searchQuery);
          }).toList();

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
                  height: 160,
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

    // if (expenses.isEmpty) {
    //   return const Center(child: Text('No expenses found'));
    // }

    // Group by date
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var expense in expenses) {
      final createdAt = expense['created_at_local'] as DateTime;
      final dateKey = DateFormat('yyyy-MM-dd').format(createdAt);

      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(expense);
    }

    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by title or date...',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 14,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: Colors.white.withValues(alpha: 0.35),
                size: 20,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      child: Icon(
                        Icons.close,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 18,
                      ),
                    )
                  : null,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.blue, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ),

        // empty states
        if (allExpenses.isEmpty)
          const Expanded(child: Center(child: Text('No expenses found')))
        else if (expenses.isEmpty && _searchQuery.isNotEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 48,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No results for "$_searchQuery"',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                final groupId = Provider.of<GroupProvider>(
                  context,
                  listen: false,
                ).selectedGroupId;
                await expenseProvider.refresh(groupId);
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
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
                        final owner = expense['profiles'];
                        final ownerId = owner?['id'];
                        final breakdowns =
                            expense['expense_breakdowns'] as List<dynamic>? ??
                            [];

                        final ownerName = owner != null
                            ? '${owner['firstname']} ${owner['lastname']}'
                            : 'Unknown';

                        final filteredBreakdowns = breakdowns
                            .where((b) => b['payer_id'] != ownerId)
                            .toList();

                        // Get owner color
                        final ownerRawColor =
                            expense['profiles']?['color'] as String? ??
                            '#6366F1';
                        final ownerColor = Color(
                          int.parse(
                            'FF${ownerRawColor.replaceAll('#', '')}',
                            radix: 16,
                          ),
                        );

                        return AnimatedOpacity(
                          duration: const Duration(milliseconds: 300),
                          opacity: isPaid ? 0.45 : 1.0,
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            color: ownerColor.withValues(
                              alpha: 0.1,
                            ), // subtle tint
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
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 20,
                                                  decoration: isPaid
                                                      ? TextDecoration
                                                            .lineThrough
                                                      : null, // 👈
                                                  decorationColor:
                                                      Colors.white54,
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
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 33,
                                            decoration: isPaid
                                                ? TextDecoration.lineThrough
                                                : null, // 👈
                                            decorationColor: Colors.white54,
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
                                    ...filteredBreakdowns.map((b) {
                                      final user = b['profiles'];
                                      final firstName =
                                          user?['firstname'] ?? '';
                                      final lastName = user?['lastname'] ?? '';
                                      final payerName = user != null
                                          ? '$firstName $lastName'
                                          : 'Unknown';

                                      // Generate initials
                                      final initials = [
                                        firstName.isNotEmpty
                                            ? firstName[0]
                                            : '',
                                        lastName.isNotEmpty ? lastName[0] : '',
                                      ].join().toUpperCase();

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
                                              // Use a lambda function here,  which evaluates if the avatar_url is available or not
                                              // prio: use custom image circle avatar
                                              // fallback: use user's initials and a the chosen color as bg gradient of the circle avatar
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
                                                      .withOpacity(0.65),
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
