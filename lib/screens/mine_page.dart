import 'dart:async';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:divido_app/providers/expense_provider.dart';
import 'package:divido_app/providers/group_provider.dart';
import 'package:divido_app/screens/edit_expense_modal.dart';
import 'package:divido_app/services/current_user.dart';
import 'package:divido_app/widgets/dashboard_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // Metrics and realtime state variables
  bool _metricsLoading = true;
  double _totalOwedToYou = 0.0;
  int _requestId = 0;
  RealtimeChannel? _paymentsSubscription;
  Timer? _metricsDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchDashboardMetrics();
      _setupRealtimeSubscription();
    });
  }

  @override
  void dispose() {
    _metricsDebounce?.cancel();
    final paymentsSubscription = _paymentsSubscription;
    if (paymentsSubscription != null) {
      unawaited(supabase.removeChannel(paymentsSubscription));
    }
    super.dispose();
  }

  void _setupRealtimeSubscription() {
    final groupProvider = Provider.of<GroupProvider>(context, listen: false);
    final groupId = groupProvider.selectedGroupId;
    if (groupId == null) return;

    _paymentsSubscription = supabase
        .channel('public:payments:group_id=eq.$groupId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (payload) {
            _metricsDebounce?.cancel();
            _metricsDebounce = Timer(const Duration(milliseconds: 180), () {
              if (mounted) {
                _fetchDashboardMetrics();
              }
            });
          },
        )
        .subscribe();
  }

  Future<void> _fetchDashboardMetrics() async {
    final currentRequestId = ++_requestId;
    final groupProvider = Provider.of<GroupProvider>(context, listen: false);
    final groupId = groupProvider.selectedGroupId;
    final currentUserId = CurrentUser.instance.id;

    if (groupId == null || currentUserId == null) {
      if (mounted) {
        setState(() {
          _metricsLoading = false;
          _totalOwedToYou = 0.0;
        });
      }
      return;
    }

    try {
      final responses = await Future.wait([
        supabase.from('payments').select().eq('group_id', groupId),
        supabase.from('expenses').select('id, total, owner_id, expense_breakdowns(payer_id, amount)').eq('group_id', groupId),
      ]);

      if (currentRequestId != _requestId || !mounted) return;

      final paymentsData = responses[0] as List<dynamic>;
      final expensesData = responses[1] as List<dynamic>;

      double paidToYou = 0;
      double paidByYou = 0;

      for (var payment in paymentsData) {
        final payerId = payment['payer_id'];
        final payeeId = payment['payee_id'];
        final amount = _toDouble(payment['amount']);

        if (payeeId == currentUserId) {
          paidToYou += amount;
        }
        if (payerId == currentUserId) {
          paidByYou += amount;
        }
      }

      double totalOwedToOthers = 0;
      double computedOwedToYou = 0;

      for (var expense in expensesData) {
        final ownerId = expense['owner_id'];
        final breakdowns = expense['expense_breakdowns'] as List<dynamic>? ?? [];

        if (ownerId == currentUserId) {
          for (var b in breakdowns) {
            if (b['payer_id'] != currentUserId) {
              computedOwedToYou += _toDouble(b['amount']);
            }
          }
        } else {
          for (var b in breakdowns) {
            if (b['payer_id'] == currentUserId) {
              totalOwedToOthers += _toDouble(b['amount']);
            }
          }
        }
      }

      final netOwedToYou = (computedOwedToYou - paidToYou) - (totalOwedToOthers - paidByYou);

      if (mounted && currentRequestId == _requestId) {
        setState(() {
          _totalOwedToYou = netOwedToYou;
          _metricsLoading = false;
        });
      }
    } catch (_) {
      if (mounted && currentRequestId == _requestId) {
        setState(() {
          _metricsLoading = false;
        });
      }
    }
  }

  Future<void> _toggleExpensePaid(
    String expenseId,
    bool current,
    ExpenseProvider provider,
  ) async {
    provider.toggleExpensePaidLocally(expenseId, !current);
    try {
      await supabase
          .from('expenses')
          .update({
            'is_paid': !current,
            'paid_at': !current ? DateTime.now().toIso8601String() : null,
          })
          .eq('id', expenseId);
      _fetchDashboardMetrics();
    } catch (e) {
      provider.toggleExpensePaidLocally(expenseId, current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update. Please try again.'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 0, left: 16, right: 16),
          ),
        );
      }
    }
  }

  Future<void> _markAllPaid(List<String> ids, {required bool paid}) async {
    if (ids.isEmpty) return;
    final provider = Provider.of<ExpenseProvider>(context, listen: false);

    provider.setExpensesPaidLocally(ids, paid);

    try {
      await supabase
          .from('expenses')
          .update({
            'is_paid': paid,
            'paid_at': paid ? DateTime.now().toIso8601String() : null,
          })
          .inFilter('id', ids);

      _fetchDashboardMetrics();

      if (mounted && paid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${ids.length} expenses marked as paid'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 0, left: 16, right: 16),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => _markAllPaid(ids, paid: false),
            ),
          ),
        );
      }
    } catch (e) {
      provider.setExpensesPaidLocally(ids, !paid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update. Please try again.'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 0, left: 16, right: 16),
          ),
        );
      }
    }
  }

  void _showMarkAllPaidConfirmation(List<Map<String, dynamic>> unpaidExpenses) {
    final ids = unpaidExpenses.map((e) => e['id'].toString()).toList();
    double totalAmount = 0;
    for (var exp in unpaidExpenses) {
      totalAmount += _toDouble(exp['total']);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      backgroundColor: const Color(0xFF171A3F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Mark all as paid',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    child: const Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'This will mark ${ids.length} unpaid expenses totaling ₱${dashMoney(totalAmount, trimZeros: true)} as paid.',
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 24),
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
                    onPressed: () {
                      Navigator.pop(context);
                      _markAllPaid(ids, paid: true);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: kDashNavy,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Mark ${ids.length} as paid',
                      style: const TextStyle(
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
    );
  }

  void _confirmDelete(
    String expenseId,
    String expenseTitle,
    ExpenseProvider provider,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      backgroundColor: const Color(0xFF171A3F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Delete Expense',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    child: const Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: const TextStyle(fontSize: 14, color: Colors.white70),
                children: [
                  const TextSpan(text: 'Are you sure you want to delete the expense '),
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
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.pop(context);
                      try {
                        await supabase.from('expenses').delete().eq('id', expenseId);
                        await provider.refresh(null);
                        _fetchDashboardMetrics();
                      } catch (e) {
                        if (mounted) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Failed to delete expense.'),
                              behavior: SnackBarBehavior.floating,
                              margin: EdgeInsets.only(bottom: 0, left: 16, right: 16),
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
      backgroundColor: const Color(0xFF171A3F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => EditExpenseModal(
        expenseId: expenseId,
        initialTitle: currentTitle,
        initialTotal: currentTotal,
        initialBreakdowns: breakdowns,
        initialDescription: currentDescription,
        onSaved: () async {
          await provider.refresh(null);
          await _fetchDashboardMetrics();
        },
      ),
    );
  }

  List<_FeedRow> _buildRows(List<Map<String, dynamic>> expenses) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var expense in expenses) {
      final dynamic rawDate = expense['created_at_local'];
      final DateTime createdAt = rawDate is DateTime
          ? rawDate
          : (DateTime.tryParse('$rawDate') ?? DateTime.now());
      final dateKey = DateFormat('yyyy-MM-dd').format(createdAt);
      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(expense);
    }

    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final yesterdayStr = DateFormat('yyyy-MM-dd').format(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    final dateFormat = DateFormat('MMMM d, yyyy');

    final List<_FeedRow> rows = [];
    for (var dateKey in sortedDates) {
      final expensesForDate = grouped[dateKey]!;

      String dateLabel;
      if (dateKey == todayStr) {
        dateLabel = 'Today';
      } else if (dateKey == yesterdayStr) {
        dateLabel = 'Yesterday';
      } else {
        try {
          dateLabel = dateFormat.format(DateTime.parse(dateKey));
        } catch (_) {
          dateLabel = dateKey;
        }
      }

      rows.add(_FeedRow.header(label: dateLabel));

      for (var expense in expensesForDate) {
        rows.add(_FeedRow.expense(expenseMap: expense));
      }
    }

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final expenseProvider = Provider.of<ExpenseProvider>(context);
    final currentUserId = CurrentUser.instance.id;
    final groupProvider = Provider.of<GroupProvider>(context);
    final selectedGroup = groupProvider.selectedGroup;
    final inviteCode = selectedGroup?['invite_code'] as String?;
    final groupId = groupProvider.selectedGroupId;

    if (expenseProvider.isLoading) {
      return Shimmer.fromColors(
        baseColor: Colors.white.withValues(alpha: 0.06),
        highlightColor: Colors.white.withValues(alpha: 0.15),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
          children: const [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DashSkeleton(height: 28, radius: 6),
                SizedBox(height: 6),
                DashSkeleton(height: 16, radius: 4),
              ],
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: DashSkeleton(height: 110, radius: 20)),
                SizedBox(width: 14),
                Expanded(child: DashSkeleton(height: 110, radius: 20)),
              ],
            ),
            SizedBox(height: 16),
            DashSkeleton(height: 130, radius: 16),
            SizedBox(height: 12),
            DashSkeleton(height: 130, radius: 16),
            SizedBox(height: 12),
            DashSkeleton(height: 130, radius: 16),
          ],
        ),
      );
    }

    final myExpenses = expenseProvider.expenses
        .where((expense) => expense['owner_id'] == currentUserId)
        .toList();

    double totalSum = 0;
    double leftToCollect = 0;
    int unpaidCount = 0;
    final List<Map<String, dynamic>> unpaidMyExpenses = [];

    for (var exp in myExpenses) {
      final t = _toDouble(exp['total']);
      totalSum += t;
      final isPaid = exp['is_paid'] == true;
      if (!isPaid) {
        unpaidCount++;
        unpaidMyExpenses.add(exp);
        final breakdowns = exp['expense_breakdowns'] as List<dynamic>? ?? [];
        for (var b in breakdowns) {
          if (b['payer_id'] != currentUserId) {
            leftToCollect += _toDouble(b['amount']);
          }
        }
      }
    }

    final feedRows = _buildRows(myExpenses);
    final everyoneHasPaid = !_metricsLoading && groupId != null && currentUserId != null && _totalOwedToYou < 0.01;
    final showAllCollectedPill = everyoneHasPaid && unpaidCount > 0;
    final showMarkAllButton = !showAllCollectedPill && unpaidCount > 0;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: RefreshIndicator(
            onRefresh: () async {
              if (groupId != null) {
                await expenseProvider.refresh(groupId);
                await _fetchDashboardMetrics();
              }
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // HEADER
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'My expenses',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${myExpenses.length} expenses, $unpaidCount to collect',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // SUMMARY TILES
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryTile(
                                icon: Icons.account_balance_wallet_outlined,
                                label: 'Total',
                                amount: totalSum,
                                caption: '${myExpenses.length} expenses',
                                amountColor: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _SummaryTile(
                                icon: Icons.request_quote_outlined,
                                label: 'Left to collect',
                                amount: leftToCollect,
                                caption: '$unpaidCount unpaid',
                                amountColor: leftToCollect > 0 ? kDashPositive : Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // MARK ALL AS PAID OR ALL COLLECTED PILL
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: showAllCollectedPill
                                ? Padding(
                                    key: const ValueKey('all_collected'),
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: _AllCollectedPill(
                                      unpaidCount: unpaidCount,
                                      onTap: () => _showMarkAllPaidConfirmation(unpaidMyExpenses),
                                    ),
                                  )
                                : showMarkAllButton
                                    ? Padding(
                                        key: const ValueKey('mark_all_button'),
                                        padding: const EdgeInsets.only(bottom: 16),
                                        child: SizedBox(
                                          width: double.infinity,
                                          height: 48,
                                          child: FilledButton.icon(
                                            onPressed: () => _showMarkAllPaidConfirmation(unpaidMyExpenses),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: kDashPositive.withValues(alpha: 0.15),
                                              foregroundColor: kDashPositive,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(14),
                                                side: BorderSide(
                                                  color: kDashPositive.withValues(alpha: 0.25),
                                                ),
                                              ),
                                            ),
                                            icon: const Icon(Icons.done_all_rounded, size: 20),
                                            label: Text(
                                              'Mark all as paid ($unpaidCount)',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(key: ValueKey('empty')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (myExpenses.isEmpty)
                  SliverToBoxAdapter(
                    child: _buildNoExpensesState(inviteCode),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final row = feedRows[index];
                        if (row.isHeader) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
                            child: Text(
                              row.headerLabel!,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.65),
                              ),
                            ),
                          );
                        } else {
                          final expense = row.expenseMap!;
                          return RepaintBoundary(
                            key: ValueKey(expense['id']),
                            child: _MineExpenseCard(
                              expense: expense,
                              currentUserId: currentUserId,
                              onTogglePaid: (id, current) => _toggleExpensePaid(id, current, expenseProvider),
                              onDelete: (id, title) => _confirmDelete(id, title, expenseProvider),
                              onEdit: (id, title, total, breakdowns, desc) => _showEditExpenseModal(
                                expenseId: id,
                                currentTitle: title,
                                currentTotal: total,
                                breakdowns: breakdowns,
                                provider: expenseProvider,
                                currentDescription: desc,
                              ),
                            ),
                          );
                        }
                      }, childCount: feedRows.length),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.of(context).padding.bottom + 110,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoExpensesState(String? inviteCode) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            const Text(
              'No expenses yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create an expense to see it here',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
            if (inviteCode != null) ...[
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: inviteCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invite code copied!'),
                      behavior: SnackBarBehavior.floating,
                      margin: EdgeInsets.only(bottom: 0, left: 16, right: 16),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.copy,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Invite Code: $inviteCode',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeedRow {
  final bool isHeader;
  final String? headerLabel;
  final Map<String, dynamic>? expenseMap;

  const _FeedRow._({
    required this.isHeader,
    this.headerLabel,
    this.expenseMap,
  });

  factory _FeedRow.header({required String label}) {
    return _FeedRow._(
      isHeader: true,
      headerLabel: label,
    );
  }

  factory _FeedRow.expense({required Map<String, dynamic> expenseMap}) {
    return _FeedRow._(
      isHeader: false,
      expenseMap: expenseMap,
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final double amount;
  final String caption;
  final Color amountColor;

  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.amount,
    required this.caption,
    required this.amountColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kDashGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: DashAmount(
              amount,
              size: 22,
              color: amountColor,
              weight: FontWeight.w800,
              trimZeros: true,
              animate: true,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

class _AllCollectedPill extends StatelessWidget {
  final int unpaidCount;
  final VoidCallback onTap;

  const _AllCollectedPill({
    required this.unpaidCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: kDashPositive.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kDashPositive.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kDashPositive.withValues(alpha: 0.2),
              ),
              child: const Icon(Icons.check_rounded, color: kDashPositive, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Everyone has paid you',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Mark your $unpaidCount unpaid expenses as paid',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Mark paid',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kDashNavy,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MineExpenseCard extends StatefulWidget {
  final Map<String, dynamic> expense;
  final String? currentUserId;
  final Function(String id, bool current) onTogglePaid;
  final Function(String id, String title) onDelete;
  final Function(String id, String title, double total, List<Map<String, dynamic>> breakdowns, String desc) onEdit;

  const _MineExpenseCard({
    required this.expense,
    required this.currentUserId,
    required this.onTogglePaid,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  State<_MineExpenseCard> createState() => _MineExpenseCardState();
}

class _MineExpenseCardState extends State<_MineExpenseCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final expense = widget.expense;
    final currentUserId = widget.currentUserId;
    final isPaid = expense['is_paid'] == true;
    final expenseId = expense['id'] as String;
    final title = expense['title'] ?? '';
    final description = expense['description'] ?? '';
    final total = _toDouble(expense['total']);

    final owner = expense['profiles'];
    final ownerRawColor = owner?['color'] as String? ?? '#6366F1';
    final ownerColor = dashParseColor(ownerRawColor);

    final breakdowns = expense['expense_breakdowns'] as List<dynamic>? ?? [];
    final filteredBreakdowns = breakdowns
        .where((b) => b['payer_id'] != currentUserId)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: ownerColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: ownerColor, width: 5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: isPaid ? 0.45 : 1.0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + Edit Button + Total
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: Colors.white,
                                  decoration: isPaid ? TextDecoration.lineThrough : null,
                                  decorationColor: Colors.white54,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => widget.onEdit(
                                expenseId,
                                title,
                                total,
                                breakdowns
                                    .map((e) => Map<String, dynamic>.from(e as Map))
                                    .toList(),
                                description,
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                                child: Icon(
                                  Icons.edit_outlined,
                                  size: 18,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      DashAmount(
                        total,
                        size: 22,
                        weight: FontWeight.w800,
                        trimZeros: true,
                        animate: false,
                        color: Colors.white,
                      ),
                    ],
                  ),

                  // Description block
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        description,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),
                  const SizedBox(height: 12),

                  // Footer row
                  Row(
                    children: [
                      _buildAvatarStack(filteredBreakdowns),
                      if (filteredBreakdowns.isNotEmpty) const SizedBox(width: 10),
                      Text(
                        filteredBreakdowns.length == 1
                            ? '1 payer'
                            : '${filteredBreakdowns.length} payers',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isPaid
                              ? kDashPositive.withValues(alpha: 0.15)
                              : Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          isPaid ? 'Paid' : 'Unpaid',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isPaid ? kDashPositive : Colors.amber.shade300,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() {
                            _expanded = !_expanded;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: AnimatedRotation(
                            turns: _expanded ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              Icons.expand_more,
                              color: Colors.white.withValues(alpha: 0.65),
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Expandable payer details
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: _expanded
                        ? Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Column(
                              children: filteredBreakdowns.map((b) {
                                final user = b['profiles'];
                                final fName = user?['firstname'] ?? '';
                                final lName = user?['lastname'] ?? '';
                                final pName = user != null ? '$fName $lName' : 'Unknown';
                                final amount = _toDouble(b['amount']);

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      _PayerAvatar(
                                        user: user,
                                        size: 32,
                                        fontSize: 12,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          pName,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '₱${dashMoney(amount, trimZeros: true)}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white.withValues(alpha: 0.65),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Action Bar (un-dimmed)
          Row(
            children: [
              Expanded(
                flex: 3,
                child: GestureDetector(
                  onTap: () => widget.onTogglePaid(expenseId, isPaid),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isPaid
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.green.withValues(alpha: 0.15),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                      ),
                      border: Border(
                        top: BorderSide(
                          color: isPaid
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.green.withValues(alpha: 0.25),
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isPaid ? Icons.undo_rounded : Icons.check_circle_outline_rounded,
                          size: 22,
                          color: isPaid ? Colors.white.withValues(alpha: 0.3) : Colors.green.shade400,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isPaid ? 'Undo' : 'Mark as Paid',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isPaid ? Colors.white.withValues(alpha: 0.3) : Colors.green.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 50,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              Expanded(
                flex: 1,
                child: GestureDetector(
                  onTap: () => widget.onDelete(expenseId, title.isNotEmpty ? title : 'Untitled'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.10),
                      borderRadius: const BorderRadius.only(
                        bottomRight: Radius.circular(16),
                      ),
                      border: Border(
                        top: BorderSide(
                          color: Colors.red.withValues(alpha: 0.25),
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
    );
  }

  Widget _buildAvatarStack(List<dynamic> breakdowns) {
    if (breakdowns.isEmpty) {
      return const SizedBox.shrink();
    }

    const int maxVisible = 3;
    final int count = breakdowns.length;
    final int visible = min(count, maxVisible);
    final int slots = visible + (count > maxVisible ? 1 : 0);
    const double size = 22.0;
    const double step = 14.0;
    final double totalWidth = size + (slots - 1) * step;

    return SizedBox(
      width: totalWidth,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < visible; i++)
            Positioned(
              left: i * step,
              child: _PayerAvatar(
                user: breakdowns[i]['profiles'],
                size: size,
                fontSize: 8,
                borderColor: kDashNavy,
              ),
            ),
          if (count > maxVisible)
            Positioned(
              left: maxVisible * step,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: kDashNavy, width: 1.5),
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                child: const Center(
                  child: Text(
                    '+',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PayerAvatar extends StatelessWidget {
  final Map? user;
  final double size;
  final double fontSize;
  final Color? borderColor;

  const _PayerAvatar({
    this.user,
    required this.size,
    this.fontSize = 12,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final rawColor = user?['color'] as String? ?? '#6366F1';
    final userColor = dashParseColor(rawColor);
    final avatarUrl = user?['avatar_url'] as String?;
    final f = (user?['firstname'] ?? '').toString();
    final l = (user?['lastname'] ?? '').toString();
    final initials =
        '${f.isNotEmpty ? f[0] : ''}${l.isNotEmpty ? l[0] : ''}'.toUpperCase();

    Widget initialsWidget() {
      return Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: borderColor != null
              ? Border.all(color: borderColor!, width: 1.5)
              : null,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [userColor, userColor.withValues(alpha: 0.7)],
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: avatarUrl != null && avatarUrl.isNotEmpty
            ? ClipOval(
                child: CachedNetworkImage(
                  imageUrl: avatarUrl,
                  fit: BoxFit.cover,
                  width: size,
                  height: size,
                  memCacheWidth: 96,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (_, _) => initialsWidget(),
                  errorWidget: (_, _, _) => initialsWidget(),
                ),
              )
            : initialsWidget(),
      ),
    );
  }
}

double _toDouble(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;