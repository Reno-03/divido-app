import 'package:divido_app/providers/expense_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
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
        .select(
          'id, firstname, lastname, color, contact_number, is_gcash_ready, status',
        )
        .inFilter('id', userIds);

    final userMap = {for (var u in users) u['id'] as String: u};

    return netByUser.entries.map((e) {
      final user = userMap[e.key];
      return {
        'user_id': e.key,
        'name': user != null ? '${user['firstname']}' : 'Unknown',
        'lastname': user?['lastname'] ?? '',
        'net': e.value,
        'color': user?['color'] as String? ?? '#6366F1',
        'contact_number':
            user?['contact_number'] as String? ??
            '', // add contact number indicator
        'is_gcash_ready':
            user?['is_gcash_ready'] as bool? ?? false, // gcash ready indicator
        'status': user?['status'] as String? ?? '',
      };
    }).toList()..sort(
      (a, b) => (b['net'] as double).compareTo(a['net'] as double),
    );
  }

  String _getInitials(String firstname, String lastname) {
    final f = firstname.isNotEmpty ? firstname[0] : '';
    final l = lastname.isNotEmpty ? lastname[0] : '';
    return '$f$l'.toUpperCase();
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
    bool isSubmitting = false; // local flag for pay button state

    showDialog(
      context: context,
      // why statefulbuilder? because we need to update the dialog's internal state (e.g. text to show loading)
      // without building the entire BalancePage again
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(
              isSettle ? 'Settle with $targetName' : 'Pay $targetName',
            ),
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
                // disable button while submitting
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final amount = double.tryParse(amountController.text);
                        if (amount == null || amount <= 0) return;

                        // 👇 set loading true
                        setDialogState(() => isSubmitting = true);

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

                // show loading indicator while submitting
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        isSettle ? 'Settle' : 'Pay',
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPaymentHistory({
    required String targetUserId,
    required String targetName,
    required String targetLastname,
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
      showDragHandle: true, // adds a nice little handle at the top of the sheet
      isScrollControlled:
          true, // allow the sheet to take up more vertical space when needed
      useSafeArea: true, // avoid system UI overlaps
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65, // start at half the screen height
        minChildSize: 0.3, // can be dragged down to 30% of the screen height
        maxChildSize: 1.0, // can be dragged up to full screen height
        expand: false,
        builder: (context, scrollController) => Padding(
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
                        colors: [
                          targetColor,
                          targetColor.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _getInitials(targetName, targetLastname),
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
                          // fix: if net is very close to zero (e.g. 0.001 or -0.001), show "All settled up" instead of "Owes you ₱0.00" or "You owe ₱0.00"
                          net.abs() < 0.01
                              ? 'All settled up'
                              : net > 0
                              ? 'Owes you ₱${net.abs().toStringAsFixed(2)}'
                              : 'You owe ₱${net.abs().toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: net.abs() < 0.01
                                ? Colors.grey
                                : net > 0
                                ? Colors.green.shade400
                                : Colors.red.shade400,
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
                    : Builder(
                        builder: (context) {
                          // Group by date
                          final Map<String, List<Map<String, dynamic>>>
                          grouped = {};
                          for (var p in payments) {
                            final date = DateTime.parse(
                              p['created_at'],
                            ).toLocal();
                            final dateKey = DateFormat(
                              'yyyy-MM-dd',
                            ).format(date);
                            grouped.putIfAbsent(dateKey, () => []);
                            grouped[dateKey]!.add(p);
                          }

                          final sortedDates = grouped.keys.toList()
                            ..sort((a, b) => b.compareTo(a));

                          return ListView.builder(
                            controller:
                                scrollController, // attach the scroll controller to enable dragging
                            itemCount: sortedDates.length,
                            itemBuilder: (ctx, i) {
                              final dateKey = sortedDates[i];
                              final entries = grouped[dateKey]!;
                              final formattedDate = DateFormat(
                                'MMMM d, yyyy',
                              ).format(DateTime.parse(dateKey));

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Date divider
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
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
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ),
                                        const Expanded(child: Divider()),
                                      ],
                                    ),
                                  ),

                                  // Payment entries for that date
                                  ...entries.map((p) {
                                    final isPayer = p['payer_id'] == myId;
                                    final amount = (p['amount'] as num)
                                        .toDouble();
                                    final note = p['note'] as String?;

                                    return ListTile(
                                      leading: Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isPayer
                                              ? Colors.red.withValues(
                                                  alpha: 0.15,
                                                )
                                              : Colors.green.withValues(
                                                  alpha: 0.15,
                                                ),
                                        ),
                                        child: Icon(
                                          isPayer
                                              ? Icons.arrow_upward
                                              : Icons.arrow_downward,
                                          size: 18,
                                          color: isPayer
                                              ? Colors.red.shade400
                                              : Colors.green.shade400,
                                        ),
                                      ),
                                      title: Text(
                                        isPayer
                                            ? 'You paid $targetName'
                                            : '$targetName paid you',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: note != null && note.isNotEmpty
                                          ? Text(note)
                                          : null,
                                      trailing: Text(
                                        '₱${amount.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: isPayer
                                              ? Colors.red.shade400
                                              : Colors.green.shade400,
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gcashIndicator({
    required bool isReady,
    required String contactNumber,
  }) {
    // No contact number at all
    if (contactNumber.isEmpty) {
      return Tooltip(
        message: 'No contact number',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/gcash_logo.png',
                width: 16,
                height: 16,
                fit: BoxFit.contain,
                color: Colors.white38, // 👈 greyed out logo
                colorBlendMode: BlendMode.modulate,
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.remove_circle_outline,
                size: 14,
                color: Colors.white38,
              ),
            ],
          ),
        ),
      );
    }

    // Has contact number — show green or red
    final color = isReady ? Colors.green : Colors.red;

    return Tooltip(
      message: isReady ? 'GCash: $contactNumber' : 'Not GCash ready',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isReady ? const Color(0xFFE8FFF3) : const Color(0xFFFFECEC),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/gcash_logo.png',
              width: 16,
              height: 16,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 4),
            Icon(
              isReady ? Icons.check_circle : Icons.cancel,
              size: 14,
              color: color,
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  setState(() {
                    _balanceFuture = _fetchNetBalances();
                  });
                },
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount:
                      balances.length, //+ 2, // +2 for divider and logout
                  itemBuilder: (context, index) {
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
                            // Status strip
                            if ((entry['status'] as String).isNotEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 15,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(12),
                                    topRight: Radius.circular(12),
                                  ),
                                  
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline,
                                      size: 13,
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        entry['status'] as String,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.white.withValues(
                                            alpha: 0.6,
                                          ),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Triangle pointer pointing down-left toward avatar
                            if ((entry['status'] as String).isNotEmpty)
                              Row(
                                children: [
                                  SizedBox(
                                    width: 30,
                                  ),
                                  ClipPath(
                                    clipper: _TriangleClipper(),
                                    child: Container(
                                      width: 12,
                                      height: 8,
                                      color: Colors.white.withValues(
                                        alpha: 0.08,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      // Name + label
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 34,
                                                height: 34,
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
                                                  _getInitials(
                                                    entry['name'] as String,
                                                    entry['lastname'] as String,
                                                  ),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                entry['name'] as String,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 20,
                                                ),
                                              ),
                                            ],
                                          ),

                                          const SizedBox(height: 12),

                                          // GCash pill + number + copy icon
                                          Row(
                                            children: [
                                              _gcashIndicator(
                                                isReady:
                                                    entry['is_gcash_ready']
                                                        as bool,
                                                contactNumber:
                                                    entry['contact_number']
                                                        as String,
                                              ),

                                              if ((entry['contact_number']
                                                      as String)
                                                  .isNotEmpty) ...[
                                                const SizedBox(width: 8),
                                                Text(
                                                  entry['contact_number']
                                                      as String,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.white
                                                        .withValues(alpha: 0.7),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                _CopyContactButton(
                                                  contactNumber:
                                                      entry['contact_number']
                                                          as String,
                                                ),
                                              ] else ...[
                                                const SizedBox(width: 8),
                                                Text(
                                                  'No contact number',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.white
                                                        .withValues(alpha: 0.3),
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  // Amount
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '₱ ${net.abs().toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 33,
                                          color: balanceColor,
                                        ),
                                      ),

                                      Text(
                                        isZero
                                            ? 'settled'
                                            : isPositive
                                            ? 'owes you'
                                            : 'you owe',
                                        style: TextStyle(
                                          color: balanceColor.withValues(
                                            alpha: 0.75,
                                          ),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
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
                                        targetUserId:
                                            entry['user_id'] as String,
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
                                              ? Colors.green.withValues(
                                                  alpha: 0.15,
                                                )
                                              : Colors.red.withValues(
                                                  alpha: 0.15,
                                                ),
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
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
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
                                        targetUserId:
                                            entry['user_id'] as String,
                                        targetName: entry['name'] as String,
                                        targetLastname:
                                            entry['lastname'] as String,
                                        net: net,
                                        targetColor: userColor,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(
                                            alpha: 0.10,
                                          ),
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
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
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

                            // if it is settled, only show the payment history button centered
                            if (isZero)
                              GestureDetector(
                                onTap: () => _showPaymentHistory(
                                  targetUserId: entry['user_id'] as String,
                                  targetName: entry['name'] as String,
                                  targetLastname: entry['lastname'] as String,
                                  net: net,
                                  targetColor: userColor,
                                ),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.10),
                                    borderRadius: const BorderRadius.only(
                                      bottomLeft: Radius.circular(12),
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
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CopyContactButton extends StatefulWidget {
  final String contactNumber;
  const _CopyContactButton({required this.contactNumber});

  @override
  State<_CopyContactButton> createState() => _CopyContactButtonState();
}

class _CopyContactButtonState extends State<_CopyContactButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        if (_copied) return;
        await Clipboard.setData(ClipboardData(text: widget.contactNumber));
        setState(() => _copied = true);
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) setState(() => _copied = false);
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Icon(
            _copied ? Icons.check : Icons.copy,
            key: ValueKey(_copied),
            size: 16,
            color: _copied
                ? Colors.green.shade400
                : Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

class _TriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 0);                          // top-left
    path.lineTo(size.width, 0);                 // top-right
    path.lineTo(size.width / 2, size.height);   // bottom-center (point)
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_TriangleClipper oldClipper) => false;
}
