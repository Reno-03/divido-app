import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:divido_app/services/current_user.dart';
import 'package:divido_app/providers/expense_provider.dart';
import 'package:divido_app/providers/group_provider.dart';
import 'package:divido_app/screens/balance_page.dart';
import 'package:divido_app/screens/home.dart';

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

  double _thisWeekOwedToYou = 0;
  double _lastWeekOwedToYou = 0;
  double _thisWeekYouOwe = 0;
  double _lastWeekYouOwe = 0;

  List<Map<String, dynamic>> _balanceSummaries = [];

  @override
  void initState() {
    super.initState();
    // Re-fetch automatically if expenses change
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchMetrics();
      Provider.of<ExpenseProvider>(context, listen: false).addListener(_onExpensesChanged);
    });
  }

  @override
  void dispose() {
    Provider.of<ExpenseProvider>(context, listen: false).removeListener(_onExpensesChanged);
    super.dispose();
  }

  void _onExpensesChanged() {
    _fetchMetrics();
  }

  Future<void> _fetchMetrics() async {
    if (!mounted) return;
    
    final currentUserId = CurrentUser.instance.id;
    final groupProvider = Provider.of<GroupProvider>(context, listen: false);
    final groupId = groupProvider.selectedGroupId;

    if (currentUserId == null || groupId == null) {
      if (mounted) setState(() => _isLoadingMetrics = false);
      return;
    }

    final now = DateTime.now();
    final startOfThisWeek = now.subtract(const Duration(days: 7));
    final startOfLastWeek = now.subtract(const Duration(days: 14));

    final ownerBreakdowns = await _supabase
        .from('expense_breakdowns')
        .select('amount, payer_id, expenses!inner(owner_id, created_at)')
        .eq('expenses.owner_id', currentUserId)
        .eq('expenses.group_id', groupId)
        .neq('payer_id', currentUserId);

    final payerBreakdowns = await _supabase
        .from('expense_breakdowns')
        .select('amount, payer_id, expenses!inner(owner_id, created_at)')
        .eq('payer_id', currentUserId)
        .eq('expenses.group_id', groupId)
        .neq('expenses.owner_id', currentUserId);

    final paymentsMade = await _supabase
        .from('payments')
        .select('amount, created_at, payee_id')
        .eq('payer_id', currentUserId)
        .eq('group_id', groupId);

    final paymentsReceived = await _supabase
        .from('payments')
        .select('amount, created_at, payer_id')
        .eq('payee_id', currentUserId)
        .eq('group_id', groupId);

    final Map<String, double> netByUser = {};
    final Map<String, double> netByUserLastWeek = {};
    final Map<String, double> netByUserTwoWeeksAgo = {};

    void process(List<dynamic> list, String userKeyField, bool isTheyOweMe, bool isExpenseBreakdown) {
      for (var row in list) {
        final uid = isExpenseBreakdown 
            ? (userKeyField == 'payer_id' ? row['payer_id'] as String : row['expenses']['owner_id'] as String)
            : row[userKeyField] as String;
            
        final amount = (row['amount'] as num).toDouble();
        final dateStr = isExpenseBreakdown ? row['expenses']['created_at'] : row['created_at'];
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

    double calcOwedToYou(Map<String, double> dict) => dict.values.where((v) => v > 0).fold(0.0, (a, b) => a + b);
    double calcYouOwe(Map<String, double> dict) => dict.values.where((v) => v < 0).fold(0.0, (a, b) => a + b.abs());

    double currOwedToYou = calcOwedToYou(netByUser);
    double currYouOwe = calcYouOwe(netByUser);

    double lastWkOwedToYou = calcOwedToYou(netByUserLastWeek);
    double lastWkYouOwe = calcYouOwe(netByUserLastWeek);

    double twoWksOwedToYou = calcOwedToYou(netByUserTwoWeeksAgo);
    double twoWksYouOwe = calcYouOwe(netByUserTwoWeeksAgo);

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
            'name': u['firstname'] != null ? '${u['firstname']} ${u['lastname'] ?? ''}'.trim() : 'Unknown',
            'avatar_url': u['avatar_url'],
            'color': u['color'],
            'net': entry.value
          });
        }
      }
      
      summaries.sort((a, b) => (b['net'] as double).abs().compareTo((a['net'] as double).abs()));
    }

    if (mounted) {
      setState(() {
        _totalOwedToYou = currOwedToYou;
        _totalYouOwe = currYouOwe;

        _thisWeekOwedToYou = currOwedToYou - lastWkOwedToYou;
        _lastWeekOwedToYou = lastWkOwedToYou - twoWksOwedToYou;

        _thisWeekYouOwe = currYouOwe - lastWkYouOwe;
        _lastWeekYouOwe = lastWkYouOwe - twoWksYouOwe;

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

  @override
  Widget build(BuildContext context) {
    final firstName = CurrentUser.instance.username ?? 'there';
    final currentUserId = CurrentUser.instance.id;
    final funGreeting = _getFunGreeting(firstName);

    final expenseProvider = Provider.of<ExpenseProvider>(context);

    double totalGroupExpense = 0;
    double totalOwnExpense = 0;

    double thisWeekGroup = 0;
    double lastWeekGroup = 0;
    double thisWeekOwn = 0;
    double lastWeekOwn = 0;

    final now = DateTime.now();
    final startOfThisWeek = now.subtract(const Duration(days: 7));
    final startOfLastWeek = now.subtract(const Duration(days: 14));

    for (final expense in expenseProvider.expenses) {
      final total = (expense['total'] as num?)?.toDouble() ?? 0.0;
      totalGroupExpense += total;

      double ownAmt = 0;
      final breakdowns = expense['expense_breakdowns'] as List<dynamic>? ?? [];
      for (final b in breakdowns) {
        if (b['payer_id'] == currentUserId) {
          ownAmt += (b['amount'] as num?)?.toDouble() ?? 0.0;
        }
      }
      totalOwnExpense += ownAmt;

      final date = expense['created_at_local'] as DateTime?;
      if (date != null) {
        if (date.isAfter(startOfThisWeek)) {
          thisWeekGroup += total;
          thisWeekOwn += ownAmt;
        } else if (date.isAfter(startOfLastWeek) && date.isBefore(startOfThisWeek)) {
          lastWeekGroup += total;
          lastWeekOwn += ownAmt;
        }
      }
    }

    double groupPct = lastWeekGroup > 0 ? ((thisWeekGroup - lastWeekGroup) / lastWeekGroup) * 100 : (thisWeekGroup > 0 ? 100 : 0);
    double ownPct = lastWeekOwn > 0 ? ((thisWeekOwn - lastWeekOwn) / lastWeekOwn) * 100 : (thisWeekOwn > 0 ? 100 : 0);

    final currencyFormat = NumberFormat('#,##0.00', 'en_US');

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await _fetchMetrics();
          if (mounted) {
            await Provider.of<ExpenseProvider>(context, listen: false).refresh(null);
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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

                  Center(
                    child: Image.asset(
                      'assets/divido-logo-animating.gif',
                      width: 200,
                    ),
                  ),

                  const SizedBox(height: 30),

                  Row(
                    children: [
                      Expanded(
                        child: _buildCardTile(
                          'Total group expense',
                          Icons.group,
                          '₱ ${currencyFormat.format(totalGroupExpense)}',
                          groupPct,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildCardTile(
                          'Total own expense',
                          Icons.person,
                          '₱ ${currencyFormat.format(totalOwnExpense)}',
                          ownPct,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  if (_isLoadingMetrics)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: CircularProgressIndicator(color: Color(0xFF3C3C63)),
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: _buildCardTile(
                            'Total owed to you',
                            Icons.arrow_downward,
                            '₱ ${currencyFormat.format(_totalOwedToYou)}',
                            null,
                            iconBgColor: Colors.green.shade400,
                            iconColor: Colors.white,
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
                              child: const Text('No balances found.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                            )
                          else
                            ..._balanceSummaries.map((s) => _buildSummaryTile(s, currencyFormat)),

                          const SizedBox(height: 16),

                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () {
                                final parentState = context.findAncestorStateOfType<HomePageState>();
                                if (parentState != null) {
                                  parentState.switchTab(3); // Navigate to the Balance tab
                                } else {
                                  Navigator.push(context, MaterialPageRoute(builder: (context) => const BalancePage()));
                                }
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFEEEEEE),
                                foregroundColor: const Color(0xFF171A3F),
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Settle Now',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
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
    );
  }

  Widget _buildCardTile(
    String title,
    IconData icon,
    String value,
    double? pctValue, {
    Color iconBgColor = Colors.white,
    Color iconColor = const Color(0xFF3C3C63),
  }) {
    return Container(
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
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
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
          if (pctValue != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  pctValue == 0
                      ? Icons.trending_flat
                      : (pctValue > 0 ? Icons.trending_up : Icons.trending_down),
                  color: pctValue == 0
                      ? Colors.white70
                      : (pctValue > 0 ? Colors.greenAccent : Colors.redAccent),
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
                          : (pctValue > 0 ? Colors.greenAccent : Colors.redAccent),
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
                ? Image.network(avatarUrl, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.person, color: Color(0xFF3C3C63)))
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
                style: TextStyle(
                  color: amountColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
