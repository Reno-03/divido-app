// lib/screens/dashboard_page.dart

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:divido_app/providers/expense_provider.dart';
import 'package:divido_app/providers/group_provider.dart';
import 'package:divido_app/providers/status_provider.dart';
import 'package:divido_app/screens/balance_page.dart';
import 'package:divido_app/screens/home.dart';
import 'package:divido_app/screens/status_chip.dart';
import 'package:divido_app/services/current_user.dart';
import 'package:divido_app/utils/dashboard_metrics.dart';
import 'package:divido_app/widgets/breathing_logo.dart';
import 'package:divido_app/widgets/dashboard_ui.dart';
import 'package:divido_app/widgets/gcash_nudge_card.dart';
import 'package:divido_app/widgets/install_nudge_card.dart';
import 'package:divido_app/widgets/share_nudge_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _supabase = Supabase.instance.client;

  ExpenseProvider? _expenses;
  GroupProvider? _groups;

  bool _isLoadingMetrics = true;

  double _totalOwedToYou = 0;
  double _totalYouOwe = 0;

  double _thisWeekOwn = 0;
  double _lastWeekOwn = 0;

  List<Map<String, dynamic>> _balanceSummaries = [];

  double? _totalGroupExpense;
  double? _totalOwnExpense;
  double _thisWeekGroup = 0;
  double _lastWeekGroup = 0;
  List<Map<String, dynamic>> _topExpensesThisWeek = [];
  List<Map<String, dynamic>> _recentExpenses = [];
  List<Map<String, dynamic>> _sortedMembers = [];
  String? _groupName;
  Object? _createdById;

  int _metricsRequestId = 0;
  Timer? _metricsDebounce;
  String? _metricsGroupId;
  String? _cachedPaymentsGroupId;
  List<Map<String, dynamic>> _paymentsMade = const [];
  List<Map<String, dynamic>> _paymentsReceived = const [];

  RealtimeChannel? _paymentsChannel;
  String? _subscribedGroupId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _expenses = context.read<ExpenseProvider>();
      _groups = context.read<GroupProvider>();
      _expenses!.addListener(_onExpensesChanged);
      _groups!.addListener(_onGroupChanged);
      _metricsGroupId = _groups!.selectedGroupId;
      _cacheGroupView(_groups!);
      _subscribePayments(_groups!.selectedGroupId);
      _scheduleMetrics();
    });
  }

  @override
  void dispose() {
    _metricsDebounce?.cancel();
    _expenses?.removeListener(_onExpensesChanged);
    _groups?.removeListener(_onGroupChanged);
    if (_paymentsChannel != null) {
      _supabase.removeChannel(_paymentsChannel!);
    }
    super.dispose();
  }

  List<Map<String, dynamic>>? _membersSource;

  void _subscribePayments(String? groupId) {
    if (groupId == _subscribedGroupId) return;
    _subscribedGroupId = groupId;
    if (_paymentsChannel != null) {
      _supabase.removeChannel(_paymentsChannel!);
      _paymentsChannel = null;
    }
    if (groupId == null) return;
    _paymentsChannel = _supabase
        .channel('dashboard-payments-$groupId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (_) {
            if (mounted) _scheduleMetrics(forcePaymentsRefresh: true);
          },
        )
        .subscribe();
  }

  void _onGroupChanged() {
    if (!mounted) return;
    final groupProvider = _groups ?? context.read<GroupProvider>();
    final groupId = groupProvider.selectedGroupId;
    if (groupId != _metricsGroupId) {
      _cachedPaymentsGroupId = null;
      _metricsGroupId = groupId;
      _paymentsMade = const [];
      _paymentsReceived = const [];
      _subscribePayments(groupId);
      setState(() {
        _cacheGroupView(groupProvider);
        _isLoadingMetrics = true;
        _totalGroupExpense = null;
        _totalOwnExpense = null;
        _recentExpenses = [];
        _topExpensesThisWeek = [];
        _balanceSummaries = [];
      });
      _scheduleMetrics();
      return;
    }
    if (identical(_membersSource, groupProvider.members) &&
        _groupName == groupProvider.selectedGroupName) {
      return;
    }
    setState(() => _cacheGroupView(groupProvider));
  }

  void _cacheGroupView(GroupProvider groupProvider) {
    _membersSource = groupProvider.members;
    final members = List<Map<String, dynamic>>.from(groupProvider.members);
    final createdById = groupProvider.selectedGroup?['created_by'];
    members.sort((a, b) {
      if (a['id'] == createdById) return -1;
      if (b['id'] == createdById) return 1;
      return 0;
    });
    _sortedMembers = members;
    _createdById = createdById;
    _groupName = groupProvider.selectedGroupName;
  }

  void _onExpensesChanged() {
    if (!mounted) return;
    final expenseProvider = _expenses ?? context.read<ExpenseProvider>();

    if (expenseProvider.isLoading) return;

    _scheduleMetrics();
  }

  void _scheduleMetrics({bool forcePaymentsRefresh = false}) {
    _metricsDebounce?.cancel();
    _metricsDebounce = Timer(const Duration(milliseconds: 180), () {
      _recomputeMetrics(forcePaymentsRefresh: forcePaymentsRefresh);
    });
  }

  Future<void> _ensurePayments({
    required String groupId,
    required String currentUserId,
    required bool force,
  }) async {
    if (!force && _cachedPaymentsGroupId == groupId) return;

    final results = await Future.wait([
      _supabase
          .from('payments')
          .select('amount, payee_id')
          .eq('payer_id', currentUserId)
          .eq('group_id', groupId),
      _supabase
          .from('payments')
          .select('amount, payer_id')
          .eq('payee_id', currentUserId)
          .eq('group_id', groupId),
    ]);

    _paymentsMade = [
      for (final row in results[0] as List)
        {
          'uid': row['payee_id'],
          'amount': (row['amount'] as num?)?.toDouble() ?? 0.0,
        },
    ];
    _paymentsReceived = [
      for (final row in results[1] as List)
        {
          'uid': row['payer_id'],
          'amount': (row['amount'] as num?)?.toDouble() ?? 0.0,
        },
    ];
    _cachedPaymentsGroupId = groupId;
  }

  Future<void> _recomputeMetrics({bool forcePaymentsRefresh = false}) async {
    if (!mounted) return;

    final currentUserId = CurrentUser.instance.id;
    final groupProvider = _groups ?? context.read<GroupProvider>();
    final expenseProvider = _expenses ?? context.read<ExpenseProvider>();
    final groupId = groupProvider.selectedGroupId;
    if (expenseProvider.isLoading) return;

    if (currentUserId == null || groupId == null) {
      if (mounted) {
        setState(() {
          _isLoadingMetrics = false;
          _totalOwedToYou = 0;
          _totalYouOwe = 0;
          _balanceSummaries = [];
          _recentExpenses = [];
          _topExpensesThisWeek = [];
          _totalGroupExpense = 0;
          _totalOwnExpense = 0;
        });
      }
      return;
    }

    if (_totalGroupExpense == null && !_isLoadingMetrics) {
      setState(() => _isLoadingMetrics = true);
    }

    final requestId = ++_metricsRequestId;

    try {
      await _ensurePayments(
        groupId: groupId,
        currentUserId: currentUserId,
        force: forcePaymentsRefresh,
      );
    } catch (_) {
      if (!mounted || requestId != _metricsRequestId) return;
    }

    if (!mounted ||
        requestId != _metricsRequestId ||
        (_groups?.selectedGroupId ?? groupProvider.selectedGroupId) != groupId) {
      return;
    }

    final expenses = expenseProvider.expenses;
    final result = await aggregateDashboardMetrics(
      currentUserId: currentUserId,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      expenses: expenses,
      paymentsMade: _paymentsMade,
      paymentsReceived: _paymentsReceived,
    );

    if (!mounted ||
        requestId != _metricsRequestId ||
        (_groups?.selectedGroupId ?? groupProvider.selectedGroupId) != groupId) {
      return;
    }

    final memberById = {
      for (final m in groupProvider.members) m['id'] as String: m,
    };
    final nets = result['nets'] as List<dynamic>? ?? const [];
    final summaries = <Map<String, dynamic>>[];
    for (final raw in nets) {
      final row = raw as Map;
      final uid = row['uid'] as String;
      final u = memberById[uid];
      final net = (row['net'] as num).toDouble();

      if (u == null && net.abs() < 0.01) continue;

      summaries.add({
        'uid': uid,
        'name': u != null
            ? '${u['firstname'] ?? 'Unknown'} ${u['lastname'] ?? ''}'.trim()
            : 'Former member',
        'avatar_url': u?['avatar_url'],
        'color': u?['color'],
        'net': net,
      });
    }

    setState(() {
      _metricsGroupId = groupId;
      _cacheGroupView(groupProvider);
      _totalGroupExpense = (result['totalGroupExpense'] as num).toDouble();
      _totalOwnExpense = (result['totalOwnExpense'] as num).toDouble();
      _thisWeekGroup = (result['thisWeekGroup'] as num).toDouble();
      _lastWeekGroup = (result['lastWeekGroup'] as num).toDouble();
      _thisWeekOwn = (result['thisWeekOwn'] as num).toDouble();
      _lastWeekOwn = (result['lastWeekOwn'] as num).toDouble();
      _totalOwedToYou = (result['totalOwedToYou'] as num).toDouble();
      _totalYouOwe = (result['totalYouOwe'] as num).toDouble();
      _topExpensesThisWeek = List<Map<String, dynamic>>.from(
        result['topExpensesThisWeek'] as List,
      );
      _recentExpenses = expenses.length <= 3
          ? List<Map<String, dynamic>>.from(expenses)
          : expenses.sublist(0, 3);
      _balanceSummaries = summaries;
      _isLoadingMetrics = false;
    });
  }

  String _greeting(String name) {
    final h = DateTime.now().hour;
    final part = h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
    return '$part, $name';
  }

  String _firstWord(String s) => s.trim().split(' ').first;

  Map<String, dynamic>? get _topDebtor {
    Map<String, dynamic>? best;
    for (final s in _balanceSummaries) {
      final n = s['net'] as double;
      if (n < -0.01 && (best == null || n < (best['net'] as double))) best = s;
    }
    return best;
  }

  Map<String, dynamic>? get _topCreditor {
    Map<String, dynamic>? best;
    for (final s in _balanceSummaries) {
      final n = s['net'] as double;
      if (n > 0.01 && (best == null || n > (best['net'] as double))) best = s;
    }
    return best;
  }

  String? get _heroActionLabel {
    final d = _topDebtor;
    if (_totalYouOwe >= 0.01 && d != null) {
      return 'Pay ${_firstWord(d['name'] as String)} ₱${dashMoney((d['net'] as double).abs(), trimZeros: true)}';
    }
    final c = _topCreditor;
    if (_totalOwedToYou >= 0.01 && c != null) {
      return 'Nudge ${_firstWord(c['name'] as String)}';
    }
    return null;
  }

  String get _greetingSubtitle {
    final c = _topCreditor;
    if (_totalYouOwe >= 0.01) return 'You owe ₱${dashMoney(_totalYouOwe, trimZeros: true)}';
    if (_totalOwedToYou >= 0.01 && c != null) {
      final creditorCount = _balanceSummaries.where((s) => (s['net'] as double) > 0.01).length;
      if (creditorCount > 1) {
        return 'People owe you ₱${dashMoney(_totalOwedToYou, trimZeros: true)}';
      }
      return '${_firstWord(c['name'] as String)} owes you ₱${dashMoney(_totalOwedToYou, trimZeros: true)}';
    }
    return "You're all settled up";
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
                          text: "📉 Not enough money!",
                          controller: controller,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
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

  void _openBalances() {
    final parentState = context.findAncestorStateOfType<HomePageState>();
    if (parentState != null) {
      parentState.switchTab(3);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BalancePage()),
      );
    }
  }

  void _openExpenses() {
    context.findAncestorStateOfType<HomePageState>()?.switchTab(1);
  }

  String _fullName(Map<String, dynamic>? p) =>
      '${p?['firstname'] ?? 'Unknown'} ${p?['lastname'] ?? ''}'.trim();

  Widget _expenseRow(Map<String, dynamic> e) {
    final p = e['profiles'] as Map<String, dynamic>?;
    return DashExpenseRow(
      title: e['title'] as String? ?? 'Untitled',
      ownerName: _fullName(p),
      avatarUrl: p?['avatar_url'] as String?,
      total: (e['total'] as num?)?.toDouble() ?? 0.0,
    );
  }

  List<Widget> _buildSkeleton() => const [
        DashSkeleton(height: 330, radius: 28),
        SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: DashSkeleton(height: 150)),
            SizedBox(width: 14),
            Expanded(child: DashSkeleton(height: 150)),
          ],
        ),
        SizedBox(height: 28),
        DashSkeleton(height: 220),
        SizedBox(height: 28),
        DashSkeleton(height: 220),
      ];

  List<Widget> _buildContent({
    required double? groupPct,
    required double? ownPct,
  }) {
    return [
      DashHeroBalance(
        owedToYou: _totalOwedToYou,
        youOwe: _totalYouOwe,
        actionLabel: _heroActionLabel,
        onSettle: _openBalances,
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: DashStatTile(
              icon: Icons.groups_rounded,
              label: 'Group expenses',
              value: _totalGroupExpense ?? 0,
              changePct: groupPct,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: DashStatTile(
              icon: Icons.person_rounded,
              label: 'Your expenses',
              value: _totalOwnExpense ?? 0,
              changePct: ownPct,
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      const InstallNudgeCard(),
      const ShareNudgeCard(),
      const GcashNudgeCard(),
      const SizedBox(height: 14),
      DashSection(
        title: 'Summary of balances',
        actionLabel: 'See all',
        onAction: _openBalances,
        child: _balanceSummaries.isEmpty
            ? const DashEmpty('No balances found.')
            : DashRows(
                children: [
                  for (final s in _balanceSummaries)
                    DashBalanceRow(
                      name: s['name'] as String,
                      avatarUrl: s['avatar_url'] as String?,
                      net: s['net'] as double,
                    ),
                ],
              ),
      ),
      const SizedBox(height: 28),
      DashSection(
        title: 'Recent expenses',
        actionLabel: 'View all',
        onAction: _openExpenses,
        child: _recentExpenses.isEmpty
            ? const DashEmpty('No recent expenses.')
            : DashRows(children: [for (final e in _recentExpenses) _expenseRow(e)]),
      ),
      const SizedBox(height: 28),
      DashSection(
        title: 'Your top expenses, last 7 days',
        child: _topExpensesThisWeek.isEmpty
            ? const DashEmpty('No expenses this week.')
            : DashRows(
                children: [
                  for (final (i, t) in _topExpensesThisWeek.indexed)
                    DashTopExpenseRow(
                      rank: i + 1,
                      title: t['title'] as String? ?? 'Untitled',
                      ownerName: t['owner_name'] as String? ?? 'Unknown',
                      avatarUrl: t['avatar_url'] as String?,
                      ownAmt: (t['ownAmt'] as num).toDouble(),
                      total: (t['total'] as num?)?.toDouble() ?? 0.0,
                    ),
                ],
              ),
      ),
      const SizedBox(height: 28),
      DashSection(
        title: 'Members for ${_groupName ?? "Group"}',
        child: _sortedMembers.isEmpty
            ? const DashEmpty('No members found.')
            : DashRows(
                children: [
                  for (final m in _sortedMembers)
                    DashMemberRow(
                      name: _fullName(m),
                      avatarUrl: m['avatar_url'] as String?,
                      colorHex: m['color'] as String?,
                      isCreator: m['id'] == _createdById,
                    ),
                ],
              ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final firstName = (CurrentUser.instance.firstname?.isNotEmpty == true)
        ? CurrentUser.instance.firstname!
        : 'there';
    final loading = _isLoadingMetrics || _totalGroupExpense == null;

    final double? groupPct = _lastWeekGroup > 0
        ? ((_thisWeekGroup - _lastWeekGroup) / _lastWeekGroup) * 100
        : (_thisWeekGroup > 0 ? null : 0);
    final double? ownPct = _lastWeekOwn > 0
        ? ((_thisWeekOwn - _lastWeekOwn) / _lastWeekOwn) * 100
        : (_thisWeekOwn > 0 ? null : 0);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          _cachedPaymentsGroupId = null;
          if (mounted) {
            await (_expenses ?? context.read<ExpenseProvider>()).refresh(null);
            _scheduleMetrics(forcePaymentsRefresh: true);
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  MediaQuery.of(context).padding.bottom + 110,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _greeting(firstName),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                loading
                                    ? const SizedBox.shrink()
                                    : Text(
                                        _greetingSubtitle,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.white60,
                                        ),
                                      ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          const SizedBox(
                            width: 44,
                            height: 44,
                            child: RepaintBoundary(
                              child: FittedBox(
                                child: BreathingLogo(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: _showStatusEditor,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              _buildAvatar(),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Consumer<StatusProvider>(
                                  builder: (context, statusProvider, _) =>
                                      _dashboardStatusBubble(
                                        statusProvider.status,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (loading)
                        ..._buildSkeleton()
                      else
                        ..._buildContent(groupPct: groupPct, ownPct: ownPct),
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

  Widget _networkAvatar(
    String? url, {
    required double size,
    required Widget fallback,
  }) {
    if (url == null || url.isEmpty) return fallback;
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2;
    final px = (size * dpr).round();
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: size,
      height: size,
      memCacheWidth: px,
      memCacheHeight: px,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      errorWidget: (_, _, _) => fallback,
      placeholder: (_, _) => fallback,
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
          ? _networkAvatar(
              avatarUrl,
              size: 36,
              fallback: Center(
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