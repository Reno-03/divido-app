import 'dart:async';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:divido_app/providers/expense_provider.dart';
import 'package:divido_app/providers/group_provider.dart';
import 'package:divido_app/screens/expense_detail_page.dart';
import 'package:divido_app/widgets/dashboard_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  bool _showPaid = true;
  bool _showUnpaid = true;
  bool _onlyMine = false;
  late final ExpenseProvider _expenseProvider;
  int _expenseVersion = 0;
  int _preparationRequestId = 0;
  _AllPagePreparationKey? _preparingKey;
  _AllPagePreparationKey? _preparedKey;
  _PreparedAllPageData? _preparedData;

  @override
  void initState() {
    super.initState();
    _expenseProvider = context.read<ExpenseProvider>();
    _expenseProvider.addListener(_onExpensesChanged);
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
    _expenseProvider.removeListener(_onExpensesChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onExpensesChanged() {
    _expenseVersion++;
  }

  void _openFilterDialog(
    String currentUserId,
    List<Map<String, dynamic>> allExpenses,
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
      builder: (_) {
        bool tempShowPaid = _showPaid;
        bool tempShowUnpaid = _showUnpaid;
        bool tempOnlyMine = _onlyMine;

        return StatefulBuilder(
          builder: (context, setStateSB) {
            // Live compute count inside sheet
            final tempFiltered = allExpenses.where((expense) {
              final isPaid = expense['is_paid'] == true;
              if ((!tempShowPaid && isPaid) || (!tempShowUnpaid && !isPaid)) {
                return false;
              }
              if (tempOnlyMine) {
                final ownerId = expense['owner_id'] as String?;
                if (ownerId == currentUserId) return false;
                final breakdowns =
                    (expense['expense_breakdowns'] as List<dynamic>? ?? []);
                final isPayer = breakdowns.any(
                  (b) => b['payer_id'] == currentUserId,
                );
                if (!isPayer) return false;
              }
              final searchTitle =
                  (expense['search_title'] ?? '').toString().toLowerCase();
              final searchDateStr =
                  (expense['search_date_str'] ?? '').toString().toLowerCase();
              final searchDateKey =
                  (expense['search_date_key'] ?? '').toString().toLowerCase();
              return searchTitle.contains(_searchQuery) ||
                  searchDateStr.contains(_searchQuery) ||
                  searchDateKey.contains(_searchQuery);
            }).toList();

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
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
                        'Filter Expenses',
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
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildFilterOption(
                    title: 'Show Paid',
                    value: tempShowPaid,
                    onChanged: (v) => setStateSB(() => tempShowPaid = v),
                  ),
                  _buildFilterOption(
                    title: 'Show Unpaid',
                    value: tempShowUnpaid,
                    onChanged: (v) => setStateSB(() => tempShowUnpaid = v),
                  ),
                  _buildFilterOption(
                    title: 'Only Show Expenses I\'m Involved In',
                    value: tempOnlyMine,
                    onChanged: (v) => setStateSB(() => tempOnlyMine = v),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setStateSB(() {
                              tempShowPaid = true;
                              tempShowUnpaid = true;
                              tempOnlyMine = false;
                            });
                          },
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
                                'Reset',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _showPaid = tempShowPaid;
                              _showUnpaid = tempShowUnpaid;
                              _onlyMine = tempOnlyMine;
                            });
                            Navigator.pop(context);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Text(
                                'Show ${tempFiltered.length} expenses',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF171A3F),
                                  fontSize: 16,
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
            );
          },
        );
      },
    );
  }

  Widget _buildFilterOption({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value
                ? Colors.white.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: value
                  ? const Icon(
                      Icons.check_circle,
                      key: ValueKey('checked'),
                      color: Colors.white,
                    )
                  : Icon(
                      Icons.circle_outlined,
                      key: const ValueKey('unchecked'),
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _isFiltered => !(_showPaid && _showUnpaid && !_onlyMine);

  bool _matchesFilters(
    Map<String, dynamic> expense,
    _AllPagePreparationKey key,
  ) {
    final isPaid = expense['is_paid'] == true;
    if ((!key.showPaid && isPaid) || (!key.showUnpaid && !isPaid)) {
      return false;
    }

    if (key.onlyMine) {
      final ownerId = expense['owner_id'] as String?;
      if (ownerId == key.currentUserId) return false;

      final breakdowns = expense['expense_breakdowns'] as List<dynamic>? ?? [];
      if (!breakdowns.any((b) => b['payer_id'] == key.currentUserId)) {
        return false;
      }
    }

    final searchTitle = (expense['search_title'] ?? '').toString();
    final searchDateStr = (expense['search_date_str'] ?? '').toString();
    final searchDateKey = (expense['search_date_key'] ?? '').toString();
    return searchTitle.contains(key.searchQuery) ||
        searchDateStr.contains(key.searchQuery) ||
        searchDateKey.contains(key.searchQuery);
  }

  Future<void> _preparePageData(
    _AllPagePreparationKey key,
    int requestId,
  ) async {
    final expenses = <Map<String, dynamic>>[];
    final rows = <_FeedRow>[];
    final now = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);
    final yesterdayKey = DateFormat(
      'yyyy-MM-dd',
    ).format(now.subtract(const Duration(days: 1)));
    final dateFormat = DateFormat('MMMM d, yyyy');
    String? lastDateKey;
    var totalSum = 0.0;
    var myShareSum = 0.0;

    for (var index = 0; index < key.source.length; index++) {
      if (requestId != _preparationRequestId) return;

      final expense = key.source[index];
      if (_matchesFilters(expense, key)) {
        expenses.add(expense);
        totalSum += _toDouble(expense['total']);

        final breakdowns =
            expense['expense_breakdowns'] as List<dynamic>? ?? [];
        for (final breakdown in breakdowns) {
          if (breakdown['payer_id'] == key.currentUserId) {
            myShareSum += _toDouble(breakdown['amount']);
            break;
          }
        }

        final rawDate = expense['created_at_local'];
        final createdAt = rawDate is DateTime
            ? rawDate
            : (DateTime.tryParse('$rawDate') ?? now);
        final dateKey = (expense['search_date_key'] ?? '').toString();
        final resolvedDateKey = dateKey.isNotEmpty
            ? dateKey
            : DateFormat('yyyy-MM-dd').format(createdAt);

        if (resolvedDateKey != lastDateKey) {
          final dateLabel = switch (resolvedDateKey) {
            _ when resolvedDateKey == todayKey => 'Today',
            _ when resolvedDateKey == yesterdayKey => 'Yesterday',
            _ => dateFormat.format(createdAt),
          };
          rows.add(_FeedRow.header(label: dateLabel));
          lastDateKey = resolvedDateKey;
        }
        rows.add(_FeedRow.expense(expenseMap: expense));
      }

      if (index % 64 == 63) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (!mounted || requestId != _preparationRequestId) return;
    _preparedData = _PreparedAllPageData(
      expenses: expenses,
      rows: rows,
      totalSum: totalSum,
      myShareSum: myShareSum,
    );
    _preparedKey = key;
    _preparingKey = null;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final expenseProvider = Provider.of<ExpenseProvider>(context);
    if (expenseProvider.isLoading) {
      _cancelPagePreparation();
      return _buildLoadingShimmer();
    }

    final allExpenses = expenseProvider.expenses;
    final currentUserId = supabase.auth.currentUser?.id ?? '';
    final key = _AllPagePreparationKey(
      source: allExpenses,
      expenseVersion: _expenseVersion,
      currentUserId: currentUserId,
      searchQuery: _searchQuery,
      showPaid: _showPaid,
      showUnpaid: _showUnpaid,
      onlyMine: _onlyMine,
    );
    if (_preparedData == null || !_preparedKey!.matches(key)) {
      if (_preparingKey == null || !_preparingKey!.matches(key)) {
        _cancelPagePreparation();
        final requestId = ++_preparationRequestId;
        _preparingKey = key;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && requestId == _preparationRequestId) {
            unawaited(_preparePageData(key, requestId));
          }
        });
      }
      return _buildLoadingShimmer();
    }

    final preparedData = _preparedData!;
    final expenses = preparedData.expenses;
    final feedRows = preparedData.rows;
    final totalSum = preparedData.totalSum;
    final myShareSum = preparedData.myShareSum;
    final selectedGroup = Provider.of<GroupProvider>(
      context,
      listen: false,
    ).selectedGroup;
    final inviteCode = selectedGroup?['invite_code'] as String?;
    final groupId = Provider.of<GroupProvider>(context, listen: false).selectedGroupId;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: RefreshIndicator(
            onRefresh: () async {
              if (groupId != null) {
                await expenseProvider.refresh(groupId);
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
                              'All expenses',
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
                              '${expenses.length} expenses',
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
                                caption: '${expenses.length} expenses',
                                amountColor: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _SummaryTile(
                                icon: Icons.person_outline,
                                label: 'Your share',
                                amount: myShareSum,
                                caption: 'your portion',
                                amountColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // SEARCH AND FILTER ROW
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
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
                                  suffixIcon: _searchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: Icon(
                                            Icons.clear,
                                            color: Colors.white.withValues(
                                              alpha: 0.5,
                                            ),
                                            size: 18,
                                          ),
                                          onPressed: () {
                                            _searchController.clear();
                                          },
                                        )
                                      : null,
                                  filled: true,
                                  fillColor: Colors.white.withValues(
                                    alpha: 0.06,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 48,
                              height: 48,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  GestureDetector(
                                    onTap: () => _openFilterDialog(
                                      currentUserId,
                                      allExpenses,
                                    ),
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.06,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.1,
                                          ),
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.filter_list,
                                        color: Colors.white.withValues(
                                          alpha: 0.85,
                                        ),
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  if (_isFiltered)
                                    Positioned(
                                      top: -2,
                                      right: -2,
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: kDashNavy,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // QUICK FILTER CHIPS
                        SizedBox(
                          height: 36,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _buildChip(
                                label: 'All',
                                selected:
                                    _showPaid && _showUnpaid && !_onlyMine,
                                onTap: () {
                                  setState(() {
                                    _showPaid = true;
                                    _showUnpaid = true;
                                    _onlyMine = false;
                                  });
                                },
                              ),
                              const SizedBox(width: 8),
                              _buildChip(
                                label: 'Unpaid',
                                selected: !_showPaid && _showUnpaid,
                                onTap: () {
                                  setState(() {
                                    _showPaid = false;
                                    _showUnpaid = true;
                                  });
                                },
                              ),
                              const SizedBox(width: 8),
                              _buildChip(
                                label: 'Paid',
                                selected: _showPaid && !_showUnpaid,
                                onTap: () {
                                  setState(() {
                                    _showPaid = true;
                                    _showUnpaid = false;
                                  });
                                },
                              ),
                              const SizedBox(width: 8),
                              _buildChip(
                                label: 'Involving me',
                                selected: _onlyMine,
                                onTap: () {
                                  setState(() {
                                    _onlyMine = !_onlyMine;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                if (allExpenses.isEmpty)
                  SliverToBoxAdapter(
                    child: _buildNoExpensesState(inviteCode),
                  )
                else if (expenses.isEmpty &&
                    (_searchQuery.isNotEmpty || _isFiltered))
                  SliverToBoxAdapter(child: _buildNoResultsState())
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
                            child: _ExpenseCard(
                              expense: expense,
                              currentUserId: currentUserId,
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

  void _cancelPagePreparation() {
    if (_preparingKey == null) return;
    _preparationRequestId++;
    _preparingKey = null;
  }

  Widget _buildLoadingShimmer() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Shimmer.fromColors(
          baseColor: Colors.white.withValues(alpha: 0.06),
          highlightColor: Colors.white.withValues(alpha: 0.15),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  DashSkeleton(height: 28, radius: 6),
                  SizedBox(height: 6),
                  DashSkeleton(height: 16, radius: 4),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: const [
                  Expanded(child: DashSkeleton(height: 110, radius: 20)),
                  SizedBox(width: 14),
                  Expanded(child: DashSkeleton(height: 110, radius: 20)),
                ],
              ),
              const SizedBox(height: 16),
              const DashSkeleton(height: 48, radius: 12),
              const SizedBox(height: 16),
              const DashSkeleton(height: 130, radius: 16),
              const SizedBox(height: 12),
              const DashSkeleton(height: 130, radius: 16),
              const SizedBox(height: 12),
              const DashSkeleton(height: 130, radius: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? kDashNavy : Colors.white.withValues(alpha: 0.65),
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
              'Create an expense using the add button below to see it here',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.5),
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
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
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

  Widget _buildNoResultsState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No results for "$_searchQuery"'
                  : 'No expenses match the selected filters',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  _searchQuery = '';
                  _showPaid = true;
                  _showUnpaid = true;
                  _onlyMine = false;
                });
              },
              child: const Text(
                'Clear filters',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
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

class _PreparedAllPageData {
  const _PreparedAllPageData({
    required this.expenses,
    required this.rows,
    required this.totalSum,
    required this.myShareSum,
  });

  final List<Map<String, dynamic>> expenses;
  final List<_FeedRow> rows;
  final double totalSum;
  final double myShareSum;
}

class _AllPagePreparationKey {
  const _AllPagePreparationKey({
    required this.source,
    required this.expenseVersion,
    required this.currentUserId,
    required this.searchQuery,
    required this.showPaid,
    required this.showUnpaid,
    required this.onlyMine,
  });

  final List<Map<String, dynamic>> source;
  final int expenseVersion;
  final String currentUserId;
  final String searchQuery;
  final bool showPaid;
  final bool showUnpaid;
  final bool onlyMine;

  bool matches(_AllPagePreparationKey other) =>
      identical(source, other.source) &&
      expenseVersion == other.expenseVersion &&
      currentUserId == other.currentUserId &&
      searchQuery == other.searchQuery &&
      showPaid == other.showPaid &&
      showUnpaid == other.showUnpaid &&
      onlyMine == other.onlyMine;
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

class _ExpenseCard extends StatefulWidget {
  final Map<String, dynamic> expense;
  final String currentUserId;

  const _ExpenseCard({required this.expense, required this.currentUserId});

  @override
  State<_ExpenseCard> createState() => _ExpenseCardState();
}

class _ExpenseCardState extends State<_ExpenseCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final expense = widget.expense;
    final currentUserId = widget.currentUserId;
    final isPaid = expense['is_paid'] == true;
    final owner = expense['profiles'];
    final ownerId = owner?['id'];
    final breakdowns = expense['expense_breakdowns'] as List<dynamic>? ?? [];

    final ownerName = owner != null
        ? '${owner['firstname'] ?? ''} ${owner['lastname'] ?? ''}'.trim()
        : 'Unknown';

    final filteredBreakdowns = breakdowns
        .where((b) => b['payer_id'] != ownerId)
        .toList();

    final ownerRawColor = owner?['color'] as String? ?? '#6366F1';
    final ownerColor = dashParseColor(ownerRawColor);

    double? myShare;
    for (var b in breakdowns) {
      if (b['payer_id'] == currentUserId) {
        myShare = _toDouble(b['amount']);
        break;
      }
    }

    return Hero(
      tag: 'expense_${expense['id']}',
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 300),
              reverseTransitionDuration: const Duration(milliseconds: 250),
              pageBuilder: (_, _, _) => ExpenseDetailPage(
                expense: expense,
                ownerColor: ownerColor,
              ),
              transitionsBuilder: (_, animation, _, child) {
                final curved = animation.drive(
                  CurveTween(curve: Curves.easeOut),
                );
                return FadeTransition(
                  opacity: curved,
                  child: ColoredBox(
                    color: kDashNavy,
                    child: child,
                  ),
                );
              },
            ),
          );
        },
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: isPaid ? 0.45 : 1.0,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: ownerColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border(left: BorderSide(color: ownerColor, width: 5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PayerAvatar(
                        user: owner,
                        size: 38,
                        fontSize: 12,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              expense['title'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: Colors.white,
                                decoration: isPaid
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: Colors.white54,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ownerName,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      DashAmount(
                        _toDouble(expense['total']),
                        size: 22,
                        weight: FontWeight.w800,
                        trimZeros: true,
                        animate: false,
                        color: Colors.white,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(
                    color: Colors.white.withValues(alpha: 0.07),
                    height: 1,
                  ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
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
                            color: isPaid
                                ? kDashPositive
                                : Colors.amber.shade300,
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

                  if (myShare != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Your share: ₱${dashMoney(myShare, trimZeros: true)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],

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
                                final pName = user != null
                                    ? '$fName $lName'
                                    : 'Unknown';
                                final amount = _toDouble(b['amount']);

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
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
                                          color: Colors.white.withValues(
                                            alpha: 0.65,
                                          ),
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
        ),
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
                child: Center(
                  child: Text(
                    '+${count - maxVisible}',
                    style: const TextStyle(
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
