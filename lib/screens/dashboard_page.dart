import 'package:divido_app/providers/status_provider.dart';
import 'package:divido_app/screens/status_chip.dart';
import 'package:divido_app/widgets/share_nudge_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:divido_app/services/current_user.dart';
import 'package:divido_app/providers/expense_provider.dart';
import 'package:divido_app/providers/group_provider.dart';
import 'package:divido_app/screens/balance_page.dart';
import 'package:divido_app/screens/home.dart';
import 'package:divido_app/widgets/install_nudge_card.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _supabase = Supabase.instance.client;

  bool _isLoadingMetrics = true;

  double _totalOwedToYou = 0;
  double _totalYouOwe = 0;

  double _thisWeekOwn = 0;
  double _lastWeekOwn = 0;

  List<Map<String, dynamic>> _balanceSummaries = [];

  DateTime? _lastFetch;

  double? _totalGroupExpense;
  double? _totalOwnExpense;
  double _thisWeekGroup = 0;
  double _lastWeekGroup = 0;
  List<Map<String, dynamic>> _topExpensesThisWeek = [];
  int _metricsRequestId = 0;

  @override
  void initState() {
    super.initState();
    // Re-fetch automatically if expenses change
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchMetrics();
      Provider.of<ExpenseProvider>(
        context,
        listen: false,
      ).addListener(_onExpensesChanged);
    });
  }

  @override
  void dispose() {
    Provider.of<ExpenseProvider>(
      context,
      listen: false,
    ).removeListener(_onExpensesChanged);
    super.dispose();
  }

  void _onExpensesChanged() {
    final expenseProvider = Provider.of<ExpenseProvider>(
      context,
      listen: false,
    );

    // While a new group is loading, expenses are intentionally cleared.
    // Skip recomputing here to avoid flashing/persisting zeros.
    if (expenseProvider.isLoading) return;

    final now = DateTime.now();
    if (_lastFetch != null &&
        now.difference(_lastFetch!).inMilliseconds < 500) {
      return;
    }
    _lastFetch = now;
    final expenses = expenseProvider.expenses;
    _computeExpenseMetrics(expenses);
    _fetchMetrics();
  }

  void _computeExpenseMetrics(List<Map<String, dynamic>> expenses) {
    double totalGroup = 0;
    double totalOwn = 0;
    double thisWeekGroup = 0;
    double lastWeekGroup = 0;
    double thisWeekOwn = 0;
    double lastWeekOwn = 0;
    final topExpenses = <Map<String, dynamic>>[];

    final now = DateTime.now();
    final startOfThisWeek = now.subtract(const Duration(days: 7));
    final startOfLastWeek = now.subtract(const Duration(days: 14));
    final currentUserId = CurrentUser.instance.id;

    for (final expense in expenses) {
      final total = (expense['total'] as num?)?.toDouble() ?? 0.0;
      totalGroup += total;

      double ownAmt = 0;
      final breakdowns = expense['expense_breakdowns'] as List<dynamic>? ?? [];
      for (final b in breakdowns) {
        if (b['payer_id'] == currentUserId) {
          ownAmt += (b['amount'] as num?)?.toDouble() ?? 0.0;
        }
      }
      totalOwn += ownAmt;

      final createdAt = expense['created_at'] as String?;
      if (createdAt != null) {
        final date = DateTime.parse('${createdAt}Z').toLocal();
        if (date.isAfter(startOfThisWeek)) {
          thisWeekGroup += total;
          thisWeekOwn += ownAmt;
          if (ownAmt > 0) {
            topExpenses.add({'expense': expense, 'ownAmt': ownAmt});
          }
        } else if (date.isAfter(startOfLastWeek) &&
            date.isBefore(startOfThisWeek)) {
          lastWeekGroup += total;
          lastWeekOwn += ownAmt;
        }
      }
    }

    topExpenses.sort(
      (a, b) => (b['ownAmt'] as double).compareTo(a['ownAmt'] as double),
    );

    setState(() {
      _totalGroupExpense = totalGroup;
      _totalOwnExpense = totalOwn;
      _thisWeekGroup = thisWeekGroup;
      _lastWeekGroup = lastWeekGroup;

      _thisWeekOwn = thisWeekOwn;
      _lastWeekOwn = lastWeekOwn;

      _topExpensesThisWeek = topExpenses;
    });
  }

  Future<void> _fetchMetrics() async {
    if (!mounted) return;

    final currentUserId = CurrentUser.instance.id;
    final groupProvider = Provider.of<GroupProvider>(context, listen: false);
    final groupId = groupProvider.selectedGroupId;
    final requestId = ++_metricsRequestId;
    setState(() => _isLoadingMetrics = true);

    if (currentUserId == null || groupId == null) {
      if (mounted && requestId == _metricsRequestId) {
        setState(() {
          _isLoadingMetrics = false;
          _totalOwedToYou = 0;
          _totalYouOwe = 0;
          _balanceSummaries = [];
        });
      }
      return;
    }

    final now = DateTime.now();
    final startOfThisWeek = now.subtract(const Duration(days: 7));
    final startOfLastWeek = now.subtract(const Duration(days: 14));

    // NOTE: Improved performance by running all 4 queries in parallel instead of sequentially,
    // and processing results in-memory to minimize database calls
    final results = await Future.wait([
      _supabase
          .from('expense_breakdowns')
          .select('amount, payer_id, expenses!inner(owner_id, created_at)')
          .eq('expenses.owner_id', currentUserId)
          .eq('expenses.group_id', groupId)
          .neq('payer_id', currentUserId),

      _supabase
          .from('expense_breakdowns')
          .select('amount, payer_id, expenses!inner(owner_id, created_at)')
          .eq('payer_id', currentUserId)
          .eq('expenses.group_id', groupId)
          .neq('expenses.owner_id', currentUserId),

      _supabase
          .from('payments')
          .select('amount, created_at, payee_id')
          .eq('payer_id', currentUserId)
          .eq('group_id', groupId),

      _supabase
          .from('payments')
          .select('amount, created_at, payer_id')
          .eq('payee_id', currentUserId)
          .eq('group_id', groupId),
    ]);

    final ownerBreakdowns = results[0];
    final payerBreakdowns = results[1];
    final paymentsMade = results[2];
    final paymentsReceived = results[3];

    // If user switched groups while this request was in-flight, ignore it.
    if (!mounted ||
        requestId != _metricsRequestId ||
        Provider.of<GroupProvider>(context, listen: false).selectedGroupId !=
            groupId) {
      return;
    }

    final Map<String, double> netByUser = {};
    final Map<String, double> netByUserLastWeek = {};
    final Map<String, double> netByUserTwoWeeksAgo = {};

    void process(
      List<dynamic> list,
      String userKeyField,
      bool isTheyOweMe,
      bool isExpenseBreakdown,
    ) {
      for (var row in list) {
        final uid = isExpenseBreakdown
            ? (userKeyField == 'payer_id'
                  ? row['payer_id'] as String
                  : row['expenses']['owner_id'] as String)
            : row[userKeyField] as String;

        final amount = (row['amount'] as num).toDouble();
        final dateStr = isExpenseBreakdown
            ? row['expenses']['created_at']
            : row['created_at'];
        final date = DateTime.parse(dateStr).toLocal();

        final val = isTheyOweMe ? amount : -amount;

        netByUser[uid] = (netByUser[uid] ?? 0) + val;

        if (date.isBefore(startOfThisWeek)) {
          netByUserLastWeek[uid] = (netByUserLastWeek[uid] ?? 0) + val;
        }
        if (date.isBefore(startOfLastWeek)) {
          netByUserTwoWeeksAgo[uid] = (netByUserTwoWeeksAgo[uid] ?? 0) + val;
        }
      }
    }

    process(ownerBreakdowns, 'payer_id', true, true);
    process(payerBreakdowns, 'expenses.owner_id', false, true);
    process(paymentsMade, 'payee_id', true, false);
    process(paymentsReceived, 'payer_id', false, false);

    double calcOwedToYou(Map<String, double> dict) =>
        dict.values.where((v) => v > 0).fold(0.0, (a, b) => a + b);
    double calcYouOwe(Map<String, double> dict) =>
        dict.values.where((v) => v < 0).fold(0.0, (a, b) => a + b.abs());

    double currOwedToYou = calcOwedToYou(netByUser);
    double currYouOwe = calcYouOwe(netByUser);

    final userIds = netByUser.keys.toList();
    List<Map<String, dynamic>> summaries = [];
    if (userIds.isNotEmpty) {
      final users = await _supabase
          .from('profiles')
          .select('id, firstname, lastname, color, avatar_url')
          .filter('id', 'in', userIds);

      final userMap = {for (var u in users) u['id'] as String: u};

      for (var entry in netByUser.entries) {
        final u = userMap[entry.key];
        if (u != null) {
          summaries.add({
            'uid': entry.key,
            'name': u['firstname'] != null
                ? '${u['firstname']} ${u['lastname'] ?? ''}'.trim()
                : 'Unknown',
            'avatar_url': u['avatar_url'],
            'color': u['color'],
            'net': entry.value,
          });
        }
      }

      summaries.sort(
        (a, b) =>
            (b['net'] as double).abs().compareTo((a['net'] as double).abs()),
      );
    }

    if (mounted) {
      setState(() {
        _totalOwedToYou = currOwedToYou;
        _totalYouOwe = currYouOwe;

        _balanceSummaries = summaries;

        _isLoadingMetrics = false;
      });
    }
  }

  String _getFunGreeting(String name) {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return 'Rise and shine, $name!';
    } else if (hour < 17) {
      return 'Check your balance, $name!';
    } else {
      return 'Chill time, $name!';
    }
  }

  void _showStatusEditor() {
    final controller = TextEditingController(
      text: CurrentUser.instance.status ?? '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      backgroundColor: const Color(0xFF171A3F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        bool isSaving = false;

        void setSaving(bool v) {
          setState(() => isSaving = v);
        }

        Future<void> save() async {
          if (isSaving) return;
          setSaving(true);
          final statusProvider = context.read<StatusProvider>();

          final value = controller.text.trim();

          try {
            await Supabase.instance.client
                .from('profiles')
                .update({'status': value.isEmpty ? null : value})
                .eq('id', CurrentUser.instance.id!);

            CurrentUser.instance.status = value.isEmpty ? null : value;

            statusProvider.setStatus(value.isEmpty ? null : value);

            if (ctx.mounted) Navigator.pop(ctx);
            // setState(() {});
          } finally {
            setSaving(false);
          }
        }

        Future<void> clear() async {
          if (isSaving) return;
          isSaving = true;
          final statusProvider = context.read<StatusProvider>();

          try {
            await Supabase.instance.client
                .from('profiles')
                .update({'status': null})
                .eq('id', CurrentUser.instance.id!);

            CurrentUser.instance.status = null;

            statusProvider.setStatus(null);

            if (ctx.mounted) Navigator.pop(ctx);
            setState(() {});
          } finally {
            isSaving = false;
          }
        }

        return StatefulBuilder(
          builder: (ctx, setState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // drag handle (MATCH YOUR DESIGN)
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

                    // header (MATCH CREATE EXPENSE STYLE)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Set Status',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey.withValues(alpha: 0.2),
                            ),
                            child: const Icon(Icons.close, size: 16),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // input (MATCH STYLE)
                    TextField(
                      controller: controller,
                      maxLength: 60,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'What’s on your mind?',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.04),
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
                          borderSide: const BorderSide(
                            color: Colors.blue,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Quick suggestions (optional but powerful UX)
                    Wrap(
                      spacing: 8,
                      children: [
                        StatusChip(
                          text: "💸 Pay me via GCash",
                          controller: controller,
                        ),
                        StatusChip(
                          text: "💵 Pay me via Cash only",
                          controller: controller,
                        ),
                        StatusChip(
                          text: "🍻 I’ll treat next round",
                          controller: controller,
                        ),
                        StatusChip(text: "💤 Offline", controller: controller),
                        StatusChip(
                          text: "🚫 Not enough money!",
                          controller: controller,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // buttons (MATCH YOUR PRIMARY CTA STYLE)
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: isSaving ? null : clear,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  'Clear',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: GestureDetector(
                            onTap: isSaving ? null : save,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: isSaving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF171A3F),
                                        ),
                                      )
                                    : const Text(
                                        'Save Status',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF171A3F),
                                        ),
                                      ),
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
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final firstName = CurrentUser.instance.username ?? 'there';
    final funGreeting = _getFunGreeting(firstName);

    final expenseProvider = Provider.of<ExpenseProvider>(context);
    final groupProvider = Provider.of<GroupProvider>(context);

    final groupMembers = List<Map<String, dynamic>>.from(groupProvider.members);
    final selectedGroup = groupProvider.selectedGroup;
    final createdById = selectedGroup?['created_by'];

    groupMembers.sort((a, b) {
      if (a['id'] == createdById) return -1;
      if (b['id'] == createdById) return 1;
      return 0;
    });

    double groupPct = _lastWeekGroup > 0
        ? ((_thisWeekGroup - _lastWeekGroup) / _lastWeekGroup) * 100
        : (_thisWeekGroup > 0 ? 100 : 0);
    double ownPct = _lastWeekOwn > 0
        ? ((_thisWeekOwn - _lastWeekOwn) / _lastWeekOwn) * 100
        : (_thisWeekOwn > 0 ? 100 : 0);

    final currencyFormat = NumberFormat('#,##0.00', 'en_US');

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          if (mounted) {
            await Provider.of<ExpenseProvider>(
              context,
              listen: false,
            ).refresh(null);
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),

                      Center(child: const _BreathingLogo()),

                      const SizedBox(height: 20),

                      Text(
                        funGreeting,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // _dashboardStatusBubble(CurrentUser.instance.status),
                      GestureDetector(
                        onTap: _showStatusEditor,
                        behavior: HitTestBehavior
                            .opaque, // ensures full row is clickable
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _buildAvatar(),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _dashboardStatusBubble(
                                  context.watch<StatusProvider>().status,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Install app nudge card
                      InstallNudgeCard(),
                      const SizedBox(height: 10),
                      ShareNudgeCard(),

                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: _buildCardTile(
                              'Total group expense',
                              Icons.group,
                              '₱ ${currencyFormat.format(_totalGroupExpense ?? 0)}',
                              groupPct,
                              isLoading:
                                  _isLoadingMetrics ||
                                  _totalGroupExpense == null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildCardTile(
                              'Total own expense',
                              Icons.person,
                              '₱ ${currencyFormat.format(_totalOwnExpense ?? 0)}',
                              ownPct,
                              isLoading:
                                  _isLoadingMetrics ||
                                  _totalGroupExpense == null,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      if (_isLoadingMetrics) ...[
                        Row(
                          children: [
                            Expanded(child: _buildShimmerCard()),
                            const SizedBox(width: 16),
                            Expanded(child: _buildShimmerCard()),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildShimmerCard()),
                            const SizedBox(width: 16),
                            Expanded(child: _buildShimmerCard()),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Summary shimmer
                        ...List.generate(3, (_) => _buildShimmerTile()),

                        const SizedBox(height: 24),

                        // Expenses shimmer
                        ...List.generate(3, (_) => _buildShimmerTile()),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              child: _buildCardTile(
                                'Total owes to you',
                                Icons.arrow_downward,
                                '₱ ${currencyFormat.format(_totalOwedToYou)}',
                                null,
                                iconBgColor: Colors.green.shade400,
                                iconColor: Colors.white,
                                amountValue: _totalOwedToYou,
                                isOweCard: false,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildCardTile(
                                'Total you owe',
                                Icons.arrow_upward,
                                '₱ ${currencyFormat.format(_totalYouOwe)}',
                                null,
                                iconBgColor: Colors.red.shade400,
                                iconColor: Colors.white,
                                amountValue: _totalYouOwe,
                                isOweCard: true,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3C3C63),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                offset: const Offset(0, 8),
                                blurRadius: 16,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Summary of Balances',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 16),

                              if (_balanceSummaries.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF171A3F),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Text(
                                    'No balances found.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                )
                              else
                                ..._balanceSummaries.map(
                                  (s) => _buildSummaryTile(s, currencyFormat),
                                ),

                              const SizedBox(height: 16),

                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: () {
                                    final parentState = context
                                        .findAncestorStateOfType<
                                          HomePageState
                                        >();
                                    if (parentState != null) {
                                      parentState.switchTab(
                                        3,
                                      ); // Navigate to the Balance tab
                                    } else {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const BalancePage(),
                                        ),
                                      );
                                    }
                                  },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFEEEEEE),
                                    foregroundColor: const Color(0xFF171A3F),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text(
                                        'Settle Now',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(Icons.arrow_forward, size: 20, color: const Color(0xFF171A3F)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3C3C63),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                offset: const Offset(0, 8),
                                blurRadius: 16,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Recent Expenses',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 16),

                              if (expenseProvider.expenses.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF171A3F),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Text(
                                    'No recent expenses.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                )
                              else
                                ...expenseProvider.expenses
                                    .take(3)
                                    .map(
                                      (e) =>
                                          _buildExpenseTile(e, currencyFormat),
                                    ),

                              const SizedBox(height: 16),

                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: () {
                                    final parentState = context
                                        .findAncestorStateOfType<
                                          HomePageState
                                        >();
                                    if (parentState != null) {
                                      parentState.switchTab(
                                        1,
                                      ); // Navigate to All Expenses tab
                                    }
                                  },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFEEEEEE),
                                    foregroundColor: const Color(0xFF171A3F),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text(
                                        'View All Expenses',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(Icons.arrow_forward, size: 20, color: const Color(0xFF171A3F)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3C3C63),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                offset: const Offset(0, 8),
                                blurRadius: 16,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Your top expenses since last 7 days',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 16),

                              if (_topExpensesThisWeek.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF171A3F),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Text(
                                    'No expenses this week.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                )
                              else
                                ..._topExpensesThisWeek
                                    .take(3)
                                    .toList()
                                    .asMap()
                                    .entries
                                    .map(
                                      (e) => _buildTopExpenseTile(
                                        e.value,
                                        e.key + 1,
                                        currencyFormat,
                                      ),
                                    ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3C3C63),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                offset: const Offset(0, 8),
                                blurRadius: 16,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Members for ${groupProvider.selectedGroupName ?? "Group"}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 16),

                              if (groupMembers.isEmpty)
                                const Text(
                                  'No members found.',
                                  style: TextStyle(color: Colors.white70),
                                )
                              else
                                ...groupMembers.map(
                                  (m) => _buildMemberTile(
                                    m,
                                    m['id'] == createdById,
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardTile(
    String title,
    IconData icon,
    String value,
    double? pctValue, {
    Color iconBgColor = Colors.white,
    Color iconColor = const Color(0xFF3C3C63),
    bool isLoading = false,
    final double? amountValue,
    bool? isOweCard,
  }) {
    final bool isZero = amountValue == null || amountValue.abs() < 0.01;

    String? statusText;
    Color statusColor = Colors.white70;

    if (isOweCard != null) {
      if (isZero) {
        statusText = 'All settled. Good job!';
        statusColor = Colors.white54;
      } else if (isOweCard) {
        statusText = 'You need to settle';
        statusColor = Colors.redAccent;
      } else {
        statusText = 'Nudge them to settle';
        statusColor = Colors.greenAccent;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isZero
            ? const Color(0xFF3C3C63)
            : (title.contains('Total you owe')
                  ? Colors.red.withValues(alpha: 0.25)
                  : Colors.green.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            offset: const Offset(0, 8),
            blurRadius: 16,
            spreadRadius: 0,
          ),
        ],
      ),
      child: isLoading
          ? Shimmer.fromColors(
              baseColor: Colors.grey.shade700,
              highlightColor: Colors.grey.shade500,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(width: 100, height: 12, color: Colors.white),
                  const SizedBox(height: 8),
                  Container(width: 80, height: 20, color: Colors.white),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: iconBgColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: iconColor, size: 24),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // use this to make the text scale down if it's too long
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),

                    if (statusText != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (pctValue != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            pctValue == 0
                                ? Icons.trending_flat
                                : (pctValue > 0
                                      ? Icons.trending_up
                                      : Icons.trending_down),
                            color: pctValue == 0
                                ? Colors.white70
                                : (pctValue > 0
                                      ? Colors.greenAccent
                                      : Colors.redAccent),
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              pctValue == 0
                                  ? 'Same as last week'
                                  : '${pctValue.abs().toStringAsFixed(0)}% ${pctValue > 0 ? 'more' : 'less'} than last week',
                              style: TextStyle(
                                color: pctValue == 0
                                    ? Colors.white70
                                    : (pctValue > 0
                                          ? Colors.greenAccent
                                          : Colors.redAccent),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryTile(Map<String, dynamic> summary, NumberFormat format) {
    final net = summary['net'] as double;
    final name = summary['name'] as String;
    final avatarUrl = summary['avatar_url'] as String?;

    final bool isSettled = net.abs() < 0.01;
    final bool theyOweMe = net > 0;

    final Color amountColor = isSettled
        ? Colors.white70
        : (theyOweMe ? Colors.greenAccent : Colors.redAccent);

    final String subtitle = isSettled
        ? 'settled'
        : (theyOweMe ? 'owes you' : 'you owe');

    final String amountStr = isSettled ? '0.00' : format.format(net.abs());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF171A3F),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: avatarUrl != null && avatarUrl.isNotEmpty
                ? Image.network(
                    avatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.person, color: Color(0xFF3C3C63)),
                  )
                : const Icon(Icons.person, color: Color(0xFF3C3C63)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'P $amountStr',
                style: TextStyle(
                  color: amountColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(color: amountColor, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseTile(Map<String, dynamic> expense, NumberFormat format) {
    final title = expense['title'] as String? ?? 'Untitled';
    final total = (expense['total'] as num?)?.toDouble() ?? 0.0;
    final profiles = expense['profiles'] as Map<String, dynamic>?;
    final firstname = profiles?['firstname'] as String? ?? 'Unknown';
    final lastname = profiles?['lastname'] as String? ?? '';
    final avatarUrl = profiles?['avatar_url'] as String?;
    final name = '$firstname $lastname'.trim();

    final formattedTotal = format
        .format(total)
        .replaceAll(
          RegExp(r'\.00$'),
          '',
        ); // strip trailing .00 to match mockup cleanly

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF171A3F),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize:
                        18, // slightly larger, matching mockup title weight
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: avatarUrl != null && avatarUrl.isNotEmpty
                          ? Image.network(
                              avatarUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.person,
                                size: 10,
                                color: Color(0xFF3C3C63),
                              ),
                            )
                          : const Icon(
                              Icons.person,
                              size: 10,
                              color: Color(0xFF3C3C63),
                            ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'P $formattedTotal',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26, // striking size
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopExpenseTile(
    Map<String, dynamic> item,
    int index,
    NumberFormat format,
  ) {
    final expense = item['expense'] as Map<String, dynamic>;
    final ownAmt = item['ownAmt'] as double;

    final title = expense['title'] as String? ?? 'Untitled';
    final total = (expense['total'] as num?)?.toDouble() ?? 0.0;
    final profiles = expense['profiles'] as Map<String, dynamic>?;
    final firstname = profiles?['firstname'] as String? ?? 'Unknown';
    final lastname = profiles?['lastname'] as String? ?? '';
    final avatarUrl = profiles?['avatar_url'] as String?;
    final name = '$firstname $lastname'.trim();

    final formattedOwnAmt = format
        .format(ownAmt)
        .replaceAll(RegExp(r'\.00$'), ''); // strip trailing .00
    final formattedTotal = format.format(total); // keep decimals for total

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF171A3F),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$index',
                style: const TextStyle(
                  color: Color(0xFF171A3F),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: avatarUrl != null && avatarUrl.isNotEmpty
                          ? Image.network(
                              avatarUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.person,
                                size: 10,
                                color: Color(0xFF3C3C63),
                              ),
                            )
                          : const Icon(
                              Icons.person,
                              size: 10,
                              color: Color(0xFF3C3C63),
                            ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'P $formattedOwnAmt',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'total: P $formattedTotal',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> member, bool isCreator) {
    final firstname = member['firstname'] as String? ?? 'Unknown';
    final lastname = member['lastname'] as String? ?? '';
    final name = '$firstname $lastname'.trim();
    final avatarUrl = member['avatar_url'] as String?;

    final colorStr = member['color'] as String? ?? '#CCCCCC';
    Color memberColor = Colors.grey;
    if (colorStr.startsWith('#') && colorStr.length == 7) {
      try {
        memberColor = Color(
          int.parse(colorStr.substring(1), radix: 16) + 0xFF000000,
        );
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF171A3F),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: avatarUrl != null && avatarUrl.isNotEmpty
                ? Image.network(
                    avatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.person, color: Color(0xFF3C3C63)),
                  )
                : const Icon(Icons.person, color: Color(0xFF3C3C63)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isCreator) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Group Creator',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 24, // distinct large circle for color
            height: 24,
            decoration: BoxDecoration(
              color: memberColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3C3C63),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade700,
        highlightColor: Colors.grey.shade500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 16),
            Container(width: 100, height: 12, color: Colors.white),
            const SizedBox(height: 8),
            Container(width: 80, height: 20, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerTile() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF171A3F),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade700,
        highlightColor: Colors.grey.shade500,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: Container(height: 12, color: Colors.white)),
            const SizedBox(width: 16),
            Container(width: 40, height: 12, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _dashboardStatusBubble(String? status) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.edit_note_outlined,
            size: 16,
            color: Colors.white.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status?.isNotEmpty == true
                  ? status!
                  : 'Wanna share something? Add a note!',
              style: TextStyle(
                fontSize: 13,
                color: status?.isNotEmpty == true
                    ? Colors.white.withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.35),
                fontStyle: status?.isNotEmpty == true
                    ? FontStyle.normal
                    : FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final avatarUrl = CurrentUser.instance.avatarUrl;
    final bgColor = Color(
      int.parse(
        'FF${(CurrentUser.instance.color ?? '#6366F1').replaceAll('#', '')}',
        radix: 16,
      ),
    );

    final initials =
        '${CurrentUser.instance.firstname?[0].toUpperCase() ?? ''}'
        '${CurrentUser.instance.lastname?[0].toUpperCase() ?? ''}';

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
      clipBehavior: Clip.antiAlias,
      child: avatarUrl != null && avatarUrl.isNotEmpty
          ? Image.network(
              avatarUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
    );
  }
}

class _BreathingLogo extends StatefulWidget {
  const _BreathingLogo();

  @override
  State<_BreathingLogo> createState() => _BreathingLogoState();
}

class _BreathingLogoState extends State<_BreathingLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _scale = Tween<double>(
      begin: 0.92,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
      child: Image.asset(
        'assets/divido_logo_only.png', // your static PNG
        height: 100,
      ),
    );
  }
}
