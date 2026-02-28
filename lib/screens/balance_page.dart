import 'package:divido_app/providers/expense_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/current_user.dart';

final _currentUser = CurrentUser.instance;

class BalancePage extends StatefulWidget {
  const BalancePage({super.key});

  @override
  State<BalancePage> createState() => _BalancePageState();
}

class _BalancePageState extends State<BalancePage> {
  final supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _balanceFuture;

  @override
  void initState() {
    super.initState();
    _balanceFuture = _fetchNetBalances();

    // Re-fetch balances whenever expenses change
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ExpenseProvider>(
        context,
        listen: false,
      ).addListener(_onExpensesChanged);
    });
  }

  void _onExpensesChanged() {
    setState(() {
      _balanceFuture = _fetchNetBalances();
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

  Future<List<Map<String, dynamic>>> _fetchNetBalances() async {
    final myId = _currentUser.id;
    if (myId == null) return [];

    final ownerExpenses = await supabase
        .from('expense_breakdowns')
        .select('amount, expense_id, payer_id, expenses!inner(owner_id)')
        .eq('expenses.owner_id', myId)
        .neq('payer_id', myId);

    final payerExpenses = await supabase
        .from('expense_breakdowns')
        .select('amount, payer_id, expense_id, expenses!inner(owner_id)')
        .eq('payer_id', myId)
        .neq('expenses.owner_id', myId);

    final paymentsMade = await supabase
        .from('payments')
        .select('amount, payee_id')
        .eq('payer_id', myId);

    final paymentsReceived = await supabase
        .from('payments')
        .select('amount, payer_id')
        .eq('payee_id', myId);

    final Map<String, double> netByUser = {};

    for (var b in ownerExpenses) {
      final uid = b['payer_id'] as String;
      netByUser[uid] = (netByUser[uid] ?? 0) + (b['amount'] as num).toDouble();
    }

    for (var b in payerExpenses) {
      final uid = b['expenses']['owner_id'] as String;
      netByUser[uid] = (netByUser[uid] ?? 0) - (b['amount'] as num).toDouble();
    }

    for (var p in paymentsMade) {
      final uid = p['payee_id'] as String;
      netByUser[uid] = (netByUser[uid] ?? 0) + (p['amount'] as num).toDouble();
    }

    for (var p in paymentsReceived) {
      final uid = p['payer_id'] as String;
      netByUser[uid] = (netByUser[uid] ?? 0) - (p['amount'] as num).toDouble();
    }

    netByUser.remove(myId);
    if (netByUser.isEmpty) return [];

    final userIds = netByUser.keys.toList();
    final users = await supabase
        .from('profiles')
        .select('id, firstname, lastname, color')
        .inFilter('id', userIds);

    final userMap = {for (var u in users) u['id'] as String: u};

    return netByUser.entries.map((e) {
        final user = userMap[e.key];
        return {
          'user_id': e.key,
          'name': user != null
              // ? '${user['firstname']} ${user['lastname']}'
              ? '${user['firstname']}'
              : 'Unknown',
          'net': e.value,
          'color': user?['color'] as String? ?? '#6366F1',
        };
      }).toList()
      ..sort((a, b) => (b['net'] as double).compareTo(a['net'] as double));
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  void _showPaymentDialog({
    required String targetUserId,
    required String targetName,
    required bool isSettle,
    required double suggestedAmount,
  }) {
    final amountController = TextEditingController(
      text: suggestedAmount.abs().toStringAsFixed(2),
    );
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSettle ? 'Settle with $targetName' : 'Pay $targetName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount (₱)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text);
              if (amount == null || amount <= 0) return;

              final myId = _currentUser.id!;
              final payerId = isSettle ? targetUserId : myId;
              final payeeId = isSettle ? myId : targetUserId;

              await supabase.from('payments').insert({
                'payer_id': payerId,
                'payee_id': payeeId,
                'amount': amount,
                'note': noteController.text.isEmpty
                    ? null
                    : noteController.text,
              });

              if (ctx.mounted) Navigator.pop(ctx);

              setState(() {
                _balanceFuture = _fetchNetBalances();
              });
            },
            style: FilledButton.styleFrom(
              backgroundColor: isSettle ? Colors.green : Colors.red,
            ),
            child: Text(isSettle ? 'Settle' : 'Pay'),
          ),
        ],
      ),
    );
  }

  void _showPaymentHistory({
    required String targetUserId,
    required String targetName,
    required double net,
    required Color targetColor,
  }) async {
    final myId = _currentUser.id!;

    final payments = await supabase
        .from('payments')
        .select('amount, note, created_at, payer_id, payee_id')
        .or(
          'and(payer_id.eq.$myId,payee_id.eq.$targetUserId),and(payer_id.eq.$targetUserId,payee_id.eq.$myId)',
        )
        .order('created_at', ascending: false);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      // add more dim to the background
      barrierColor: Colors.black.withValues(
        alpha: 0.85,
      ), // 0.0 = transparent, 1.0 = full black
      showDragHandle: true,  // adds a nice little handle at the top of the sheet 
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with title and X button
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Avatar
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [targetColor, targetColor.withValues(alpha: 0.7)],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _getInitials(targetName),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Title + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        targetName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        net > 0
                            ? 'Owes you ₱${net.abs().toStringAsFixed(2)}'
                            : net < 0
                            ? 'You owe ₱${net.abs().toStringAsFixed(2)}'
                            : 'All settled up',
                        style: TextStyle(
                          fontSize: 13,
                          color: net > 0
                              ? Colors.green.shade400
                              : net < 0
                              ? Colors.red.shade400
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                // X button
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
            const SizedBox(height: 12),

            Expanded(
              child: payments.isEmpty
                  ? const Center(child: Text('No payments yet.'))
                  : ListView.builder(
                      itemCount: payments.length,
                      itemBuilder: (ctx, i) {
                        final p = payments[i];
                        final isPayer = p['payer_id'] == myId;
                        final amount = (p['amount'] as num).toDouble();
                        final note = p['note'] as String?;
                        final date = DateTime.parse(p['created_at']).toLocal();

                        return ListTile(
                          leading: Icon(
                            isPayer ? Icons.arrow_upward : Icons.arrow_downward,
                            color: isPayer ? Colors.red : Colors.green,
                          ),
                          title: Text(
                            '${isPayer ? 'You paid' : '$targetName paid'}  ₱${amount.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            note != null && note.isNotEmpty
                                ? '$note • ${date.month}/${date.day}/${date.year}'
                                : '${date.month}/${date.day}/${date.year}',
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _balanceFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final balances = snapshot.data ?? [];

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _balanceFuture = _fetchNetBalances();
            });
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: balances.length + 2, // +2 for divider and logout
            itemBuilder: (context, index) {
              if (index == balances.length) {
                return const Divider(height: 32);
              }

              if (index == balances.length + 1) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      // Fixed — properly clears session
                      onPressed: () async {
                        await supabase.auth.signOut();
                        CurrentUser.instance.clear();
                        if (context.mounted) {
                          Navigator.pushReplacementNamed(context, '/login');
                        }
                      },
                      icon: const Icon(
                        Icons.logout,
                        color: Colors.white,
                        size: 20,
                      ),
                      label: const Text(
                        'Log out',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith((
                          states,
                        ) {
                          if (states.contains(WidgetState.hovered)) {
                            return Colors.red[600];
                          }
                          return Colors.red[300];
                        }),
                        padding: WidgetStateProperty.all(
                          const EdgeInsets.symmetric(vertical: 14),
                        ),
                        side: WidgetStateProperty.all(
                          const BorderSide(
                            color: Color.fromARGB(255, 246, 227, 226),
                          ),
                        ),
                        shape: WidgetStateProperty.all(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }

              final entry = balances[index];
              final double net = entry['net'] as double;
              final rawColor = entry['color'] as String? ?? '#6366F1';
              final userColor = Color(
                int.parse('FF${rawColor.replaceAll('#', '')}', radix: 16),
              );
              // final bool isZero = net == 0;
              final bool isZero = net.abs() < 0.01;
              final bool isPositive = net > 0;

              final Color balanceColor = isZero
                  ? Colors.grey
                  : isPositive
                  ? Colors.green
                  : Colors.red;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Opacity(
                  opacity: isZero ? 0.45 : 1.0,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(25),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                // Avatar badge
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        userColor,
                                        userColor.withValues(alpha: 0.7),
                                      ],
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _getInitials(entry['name'] as String),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Name + label
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry['name'] as String,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                      ),
                                    ),
                                    Text(
                                      isZero
                                          ? 'settled'
                                          : isPositive
                                          ? 'owes you'
                                          : 'you owe',
                                      style: TextStyle(color: balanceColor),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            // Amount
                            Text(
                              '₱${net.abs().toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 33,
                                color: balanceColor,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Full-width CTA — same style as MinePage
                      if (!isZero)
                        Row(
                          children: [
                            // Pay/Settle Button
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _showPaymentDialog(
                                  targetUserId: entry['user_id'] as String,
                                  targetName: entry['name'] as String,
                                  isSettle: isPositive,
                                  suggestedAmount: net.abs(),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isPositive
                                        ? Colors.green.withValues(alpha: 0.15)
                                        : Colors.red.withValues(alpha: 0.15),
                                    borderRadius: const BorderRadius.only(
                                      bottomLeft: Radius.circular(12),
                                    ),
                                    border: Border(
                                      top: BorderSide(
                                        color: isPositive
                                            ? Colors.green.withValues(
                                                alpha: 0.25,
                                              )
                                            : Colors.red.withValues(
                                                alpha: 0.25,
                                              ),
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isPositive
                                            ? Icons.handshake_outlined
                                            : Icons.payments_outlined,
                                        size: 22,
                                        color: isPositive
                                            ? Colors.green.shade400
                                            : Colors.red.shade400,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        isPositive ? 'Settle' : 'Pay',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          color: isPositive
                                              ? Colors.green.shade400
                                              : Colors.red.shade400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Divider between buttons
                            Container(
                              width: 1,
                              height: 50,
                              color: isPositive
                                  ? Colors.green.withValues(alpha: 0.25)
                                  : Colors.red.withValues(alpha: 0.25),
                            ),

                            // Payment History Button
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _showPaymentHistory(
                                  targetUserId: entry['user_id'] as String,
                                  targetName: entry['name'] as String,
                                  net: net, 
                                  targetColor: userColor,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.10),
                                    borderRadius: const BorderRadius.only(
                                      bottomRight: Radius.circular(12),
                                    ),
                                    border: Border(
                                      top: BorderSide(
                                        color: Colors.blue.withValues(
                                          alpha: 0.25,
                                        ),
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.history,
                                        size: 22,
                                        color: Colors.blue.shade400,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Activity',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.blue.shade400,
                                        ),
                                      ),
                                    ],
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
          ),
        );
      },
    );
  }
}
