import 'package:flutter/material.dart';
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
        .from('users')
        .select('id, firstname, lastname')
        .inFilter('id', userIds);

    final userMap = {for (var u in users) u['id'] as String: u};

    return netByUser.entries.map((e) {
      final user = userMap[e.key];
      return {
        'user_id': e.key,
        'name': user != null
            ? '${user['firstname']} ${user['lastname']}'
            : 'Unknown',
        'net': e.value,
      };
    }).toList()
      ..sort((a, b) => (b['net'] as double).compareTo(a['net'] as double));
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                'note': noteController.text.isEmpty ? null : noteController.text,
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
                      onPressed: () {
                        CurrentUser.instance.clear();
                        Navigator.pushReplacementNamed(context, '/login');
                      },
                      icon: const Icon(Icons.logout, color: Colors.white, size: 20),
                      label: const Text(
                        'Log out',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.hovered)) {
                            return Colors.red[600];
                          }
                          return Colors.red[300];
                        }),
                        padding: WidgetStateProperty.all(
                          const EdgeInsets.symmetric(vertical: 14),
                        ),
                        side: WidgetStateProperty.all(
                          const BorderSide(color: Color.fromARGB(255, 246, 227, 226)),
                        ),
                        shape: WidgetStateProperty.all(
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                );
              }

              final entry = balances[index];
              final double net = entry['net'] as double;
              final bool isZero = net == 0;
              final bool isPositive = net > 0;

              final Color balanceColor = isZero
                  ? Colors.grey
                  : isPositive
                      ? Colors.green
                      : Colors.red;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(25),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₱${net.abs().toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 33,
                              color: balanceColor,
                            ),
                          ),
                          if (!isZero) ...[
                            const SizedBox(height: 6),
                            FilledButton(
                              onPressed: () => _showPaymentDialog(
                                targetUserId: entry['user_id'] as String,
                                targetName: entry['name'] as String,
                                isSettle: isPositive,
                                suggestedAmount: net.abs(),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: balanceColor,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(isPositive ? 'Settle' : 'Pay'),
                            ),
                          ],
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