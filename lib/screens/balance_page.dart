import 'package:divido_app/providers/expense_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/current_user.dart';

final _currentUser = CurrentUser.instance;

class BalancePage extends StatefulWidget {
  const BalancePage({super.key});

  @override
  State<BalancePage> createState() => _BalancePageState();
}

class _BalancePageState extends State<BalancePage>
    with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _balanceFuture;

  late AnimationController _nudgeController;
  late Animation<double> _nudgeAnimation;

  @override
  void initState() {
    super.initState();
    _balanceFuture = _fetchNetBalances();

    _nudgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _nudgeAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _nudgeController, curve: Curves.easeInOut),
    );

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
    _nudgeController.dispose();

    Provider.of<ExpenseProvider>(
      context,
      listen: false,
    ).removeListener(_onExpensesChanged);

    super.dispose();
  }

  Future<void> _nudge({
    required String targetUserId,
    required String targetName,
    required int currentCount,
    required String lastNudgedAt,
  }) async {
    final myId = _currentUser.id!;

    // Check max
    if (currentCount >= 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Max nudges reached for $targetName')),
        );
      }
      return;
    }

    // Check cooldown
    if (lastNudgedAt.isNotEmpty) {
      final last = DateTime.parse(lastNudgedAt).toLocal();
      final diff = DateTime.now().difference(last);
      if (diff.inHours < 12) {
        final remaining = 12 - diff.inHours;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('You can nudge $targetName again in ${remaining}h'),
            ),
          );
        }
        return;
      }
    }

    // Upsert nudge
    await supabase.from('nudges').upsert({
      'from_user_id': myId,
      'to_user_id': targetUserId,
      'nudge_count': currentCount + 1,
      'last_nudged_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'from_user_id, to_user_id');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$targetName has been nudged! 🔔')),
      );
      setState(() {
        _balanceFuture = _fetchNetBalances();
      });
    }
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
          'id, firstname, lastname, color, contact_number, is_gcash_ready, status, avatar_url',
        )
        .inFilter('id', userIds);

    final userMap = {for (var u in users) u['id'] as String: u};

    // Fetch nudges sent by me (to show cooldown/max on nudge button)
    final nudgesSent = await supabase
        .from('nudges')
        .select('to_user_id, nudge_count, last_nudged_at')
        .eq('from_user_id', myId);

    // Fetch nudges received by me (to show glow on my cards)
    final nudgesReceived = await supabase
        .from('nudges')
        .select('from_user_id, nudge_count')
        .eq('to_user_id', myId);

    final nudgesSentMap = {
      for (var n in nudgesSent) n['to_user_id'] as String: n,
    };
    final nudgesReceivedMap = {
      for (var n in nudgesReceived) n['from_user_id'] as String: n,
    };

    return netByUser.entries
        .map((e) {
          final user = userMap[e.key];
          final nudgeSent = nudgesSentMap[e.key];
          final nudgeReceived = nudgesReceivedMap[e.key];

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
                user?['is_gcash_ready'] as bool? ??
                false, // gcash ready indicator
            'status': user?['status'] as String? ?? '',
            // nudge sent to this person
            'nudge_count': nudgeSent?['nudge_count'] as int? ?? 0,
            'last_nudged_at': nudgeSent?['last_nudged_at'] as String? ?? '',
            // nudge received from this person
            'is_nudged': nudgeReceived != null,
            'nudged_count_received': nudgeReceived?['nudge_count'] as int? ?? 0,
            'avatar_url': user?['avatar_url'] as String? ?? '',
          };
        })
        .toList() // updated — nudged cards first, then by net amount
      ..sort((a, b) {
        final aNudged = a['nudged_count_received'] as int;
        final bNudged = b['nudged_count_received'] as int;

        // primary: most nudged first
        if (bNudged != aNudged) return bNudged.compareTo(aNudged);

        // secondary: largest amount you owe (negative net) first
        final aOwed = (a['net'] as double)
            .clamp(double.negativeInfinity, 0)
            .abs();
        final bOwed = (b['net'] as double)
            .clamp(double.negativeInfinity, 0)
            .abs();
        return bOwed.compareTo(aOwed);
      });
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
    bool isSubmitting = false;
    String paymentMethod = 'cash';

    showDialog(
      context: context,
      // why statefulbuilder? because we need to update the dialog's internal state (e.g. text to show loading)
      // without building the entire BalancePage again
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            backgroundColor: Color(0xFF171A3F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSettle
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.red.withValues(alpha: 0.15),
                        ),
                        child: Icon(
                          isSettle
                              ? Icons.handshake_outlined
                              : Icons.payments_outlined,
                          size: 20,
                          color: isSettle
                              ? Colors.green.shade400
                              : Colors.red.shade400,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isSettle
                                  ? 'Settle with $targetName'
                                  : 'Pay $targetName',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              isSettle
                                  ? 'Record a received payment'
                                  : 'Record a payment you made',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
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

                  const SizedBox(height: 24),

                  // Amount field
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      prefixText: '₱  ',
                      prefixStyle: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      hintText: '0.00',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isSettle ? Colors.green : Colors.red,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Note field
                  TextField(
                    controller: noteController,
                    decoration: InputDecoration(
                      hintText: 'Add a note... (optional)',
                      prefixIcon: Icon(
                        Icons.edit_note_outlined,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15),
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

                  const SizedBox(height: 16),

                  // Payment method
                  SegmentedButton<String>(
                    expandedInsets: EdgeInsets.zero,
                    segments: [
                      const ButtonSegment(
                        value: 'cash',
                        label: Text('Cash'),
                        icon: Icon(Icons.money, size: 16),
                      ),
                      ButtonSegment(
                        value: 'gcash',
                        label: const Text('GCash'),
                        icon: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(3),
                          child: Image.asset(
                            'assets/gcash_logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ],
                    selected: {paymentMethod},
                    onSelectionChanged: (val) =>
                        setDialogState(() => paymentMethod = val.first),
                    style: ButtonStyle(
                      visualDensity: VisualDensity.standard,
                      backgroundColor: WidgetStateProperty.resolveWith<Color>((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.white.withValues(alpha: 0.3);
                        }
                        return Colors.transparent;
                      }),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Confirm button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              final amount = double.tryParse(
                                amountController.text,
                              );
                              if (amount == null || amount <= 0) return;
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
                                'method': paymentMethod,
                              });

                              if (ctx.mounted) Navigator.pop(ctx);
                              setState(() {
                                _balanceFuture = _fetchNetBalances();
                              });
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: isSettle ? Colors.green : Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
                              isSettle ? 'Confirm Settle' : 'Confirm Payment',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmDeletePayment({
    required String paymentId,
    required BuildContext ctx,
    required String targetUserId,
    required String targetName,
    required String targetLastname,
    required double net,
    required Color targetColor,
  }) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Remove Payment'),
        content: const Text(
          'Are you sure you want to remove this payment? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogCtx); // close confirm dialog
              Navigator.pop(ctx); // close payment history sheet

              await supabase.from('payments').delete().eq('id', paymentId);

              setState(() {
                _balanceFuture = _fetchNetBalances();
              });

              // Reopen payment history with updated data
              _showPaymentHistory(
                targetUserId: targetUserId,
                targetName: targetName,
                targetLastname: targetLastname,
                net: net,
                targetColor: targetColor,
              );
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
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
        .select('id, amount, note, created_at, payer_id, payee_id, method')
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
                                    final paymentId =
                                        p['id']
                                            as String; // 👈 need to add 'id' to the select

                                    return ListTile(
                                      leading: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
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
                                          // method badge — bottom right of avatar
                                          Positioned(
                                            bottom: -4,
                                            right: -4,
                                            child: Container(
                                              width: 16,
                                              height: 16,
                                              decoration: const BoxDecoration(
                                                color: Colors.white,
                                                shape: BoxShape.circle,
                                              ),
                                              padding: const EdgeInsets.all(2),
                                              child: p['method'] == 'gcash'
                                                  ? Image.asset(
                                                      'assets/gcash_logo.png',
                                                      fit: BoxFit.contain,
                                                    )
                                                  : const Icon(
                                                      Icons.money,
                                                      size: 10,
                                                      color: Colors.green,
                                                    ),
                                            ),
                                          ),
                                        ],
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
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '₱${amount.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: isPayer
                                                  ? Colors.red.shade400
                                                  : Colors.green.shade400,
                                            ),
                                          ),
                                          // 👇 Only show delete if current user is the payer
                                          if (isPayer) ...[
                                            const SizedBox(width: 8),
                                            GestureDetector(
                                              onTap: () =>
                                                  _confirmDeletePayment(
                                                    paymentId: paymentId,
                                                    ctx: ctx,
                                                    targetUserId: targetUserId,
                                                    targetName: targetName,
                                                    targetLastname:
                                                        targetLastname,
                                                    net: net,
                                                    targetColor: targetColor,
                                                  ),
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: Colors.red.withValues(
                                                    alpha: 0.12,
                                                  ),
                                                ),
                                                child: Icon(
                                                  Icons.delete_outline,
                                                  size: 16,
                                                  color: Colors.red.shade400,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
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

  void _showStatusDialog() {
    final controller = TextEditingController(
      text: CurrentUser.instance.status ?? '',
    );
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Set Status',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                autofocus: true,
                maxLength: 50,
                decoration: InputDecoration(
                  hintText: 'e.g. Pay me via GCash 😄',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              setModalState(() => isSaving = true);
                              await Supabase.instance.client
                                  .from('profiles')
                                  .update({'status': null})
                                  .eq('id', CurrentUser.instance.id!);
                              CurrentUser.instance.status = null;
                              if (ctx.mounted) Navigator.pop(ctx);
                              setState(() {});
                            },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              setModalState(() => isSaving = true);
                              final newStatus = controller.text.trim();
                              await Supabase.instance.client
                                  .from('profiles')
                                  .update({
                                    'status': newStatus.isEmpty
                                        ? null
                                        : newStatus,
                                  })
                                  .eq('id', CurrentUser.instance.id!);
                              CurrentUser.instance.status = newStatus.isEmpty
                                  ? null
                                  : newStatus;
                              if (ctx.mounted) Navigator.pop(ctx);
                              setState(() {});
                            },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Save',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBubble(String? status) {
    return GestureDetector(
      onTap: _showStatusDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.edit_note_outlined,
              size: 16,
              color: Colors.white.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                status != null && status.isNotEmpty
                    ? status
                    : 'Tap to set a status...',
                style: TextStyle(
                  fontSize: 13,
                  color: status != null && status.isNotEmpty
                      ? Colors.white.withValues(alpha: 0.85)
                      : Colors.white.withValues(alpha: 0.35),
                  fontStyle: status == null || status.isEmpty
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
          return Shimmer.fromColors(
            baseColor: Colors.white.withValues(alpha: 0.06),
            highlightColor: Colors.white.withValues(alpha: 0.15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── skeleton: avatar + status row ─────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 180,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ],
                  ),
                ),
                // ── skeleton: balance cards ────────────────────────────
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: 5,
                    itemBuilder: (_, _) => Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final balances = snapshot.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 👇 Your own avatar + status at the top
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  () {
                    final avatarUrl = CurrentUser.instance.avatarUrl;
                    final bgColor = Color(
                      int.parse(
                        'FF${(CurrentUser.instance.color ?? '#6366F1').replaceAll('#', '')}',
                        radix: 16,
                      ),
                    );
                    final initials =
                        '${CurrentUser.instance.firstname?[0].toUpperCase() ?? ''}${CurrentUser.instance.lastname?[0].toUpperCase() ?? ''}';

                    return Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: bgColor,
                      ),
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
                  }(),
                  const SizedBox(width: 8),
                  Flexible(child: _statusBubble(CurrentUser.instance.status)),
                ],
              ),
            ),
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
                  itemCount: balances.length,
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

                    final bool isNudged = entry['is_nudged'] as bool;
                    final int nudgedCountReceived =
                        entry['nudged_count_received'] as int;

                    final int nudgeCount = entry['nudge_count'] as int;
                    final String lastNudgedAt =
                        entry['last_nudged_at'] as String;

                    int nudgeCooldownHoursLeft = 0;

                    // Check cooldown
                    bool isNudgeOnCooldown = false;
                    if (lastNudgedAt.isNotEmpty) {
                      final last = DateTime.parse(lastNudgedAt).toLocal();
                      final diff = DateTime.now().difference(last);
                      isNudgeOnCooldown = diff.inHours < 12;
                      nudgeCooldownHoursLeft = (12 - diff.inHours).clamp(1, 12);
                    }

                    final bool isNudgeDisabled =
                        isNudgeOnCooldown || nudgeCount >= 3;

                    final Color balanceColor = isZero
                        ? Colors.grey
                        : isPositive
                        ? Colors.green
                        : Colors.red;

                    // 👇 wrap only if nudged
                    Widget cardWidget = Card(
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
                                  color: Colors.white.withValues(alpha: 0.2),
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
                                        alpha: 0.8,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        entry['status'] as String,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.white.withValues(
                                            alpha: 0.8,
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
                                  SizedBox(width: 30),
                                  ClipPath(
                                    clipper: _TriangleClipper(),
                                    child: Container(
                                      width: 12,
                                      height: 8,
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                10,
                                20,
                                20,
                              ),
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
                                              () {
                                                final avatarUrl =
                                                    entry['avatar_url']
                                                        as String?;
                                                return Container(
                                                  width: 34,
                                                  height: 34,
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
                                                          errorBuilder: (_, _, _) => Center(
                                                            child: Text(
                                                              _getInitials(
                                                                entry['name']
                                                                    as String,
                                                                entry['lastname']
                                                                    as String,
                                                              ),
                                                              style: const TextStyle(
                                                                fontSize: 12,
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
                                                            _getInitials(
                                                              entry['name']
                                                                  as String,
                                                              entry['lastname']
                                                                  as String,
                                                            ),
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

                            // You owe them — Pay + Activity
                            if (!isZero && !isPositive)
                              Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => _showPaymentDialog(
                                        targetUserId:
                                            entry['user_id'] as String,
                                        targetName: entry['name'] as String,
                                        isSettle: false,
                                        suggestedAmount: net.abs(),
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: const BorderRadius.only(
                                            bottomLeft: Radius.circular(12),
                                          ),
                                          border: Border(
                                            top: BorderSide(
                                              color: Colors.red.withValues(
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
                                              Icons.payments_outlined,
                                              size: 22,
                                              color: Colors.red.shade400,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Pay',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.red.shade400,
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
                                    color: Colors.red.withValues(alpha: 0.25),
                                  ),
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

                            // They owe you — Nudge + Activity
                            if (!isZero && isPositive)
                              Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: isNudgeDisabled
                                          ? null // 👈 disabled — no action
                                          : () => _nudge(
                                              targetUserId:
                                                  entry['user_id'] as String,
                                              targetName:
                                                  entry['name'] as String,
                                              currentCount: nudgeCount,
                                              lastNudgedAt: lastNudgedAt,
                                            ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isNudgeDisabled
                                              ? Colors.white.withValues(
                                                  alpha: 0.04,
                                                ) // 👈 grayed
                                              : _getNudgeColor(
                                                  nudgeCount,
                                                ).withValues(alpha: 0.15),
                                          borderRadius: const BorderRadius.only(
                                            bottomLeft: Radius.circular(12),
                                          ),
                                          border: Border(
                                            top: BorderSide(
                                              color: isNudgeDisabled
                                                  ? Colors.white.withValues(
                                                      alpha: 0.08,
                                                    )
                                                  : _getNudgeColor(
                                                      nudgeCount,
                                                    ).withValues(alpha: 0.25),
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              isNudgeOnCooldown
                                                  ? Icons
                                                        .hourglass_empty // 👈 cooldown icon
                                                  : nudgeCount >= 3
                                                  ? Icons
                                                        .notifications_off_outlined // 👈 max icon
                                                  : Icons
                                                        .notifications_outlined,
                                              size: 22,
                                              color: isNudgeDisabled
                                                  ? Colors.white.withValues(
                                                      alpha: 0.25,
                                                    )
                                                  : _getNudgeColor(nudgeCount),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              isNudgeOnCooldown
                                                  ? 'Cooldown (${nudgeCooldownHoursLeft}h)'
                                                  : nudgeCount >= 3
                                                  ? 'Nudge x3'
                                                  : nudgeCount == 0
                                                  ? 'Nudge'
                                                  : 'Nudge x$nudgeCount',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w600,
                                                color: isNudgeDisabled
                                                    ? Colors.white.withValues(
                                                        alpha: 0.25,
                                                      )
                                                    : _getNudgeColor(
                                                        nudgeCount,
                                                      ),
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
                                    color: Colors.blue.withValues(alpha: 0.25),
                                  ),
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

                            // Settled — Activity only
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

                    String getNudgePhrase(int count) {
                      switch (count) {
                        case 1:
                          return 'Alayun la pagbayad!';
                        case 2:
                          return 'Ayaw nala pagbinayad!';
                        case 3:
                          return 'PAGBAYAD NA!';
                        default:
                          return 'Nudged!';
                      }
                    }

                    if (isNudged) {
                      cardWidget = AnimatedBuilder(
                        animation: _nudgeAnimation,
                        builder: (context, child) => Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: _getNudgeGlowColor(
                                nudgedCountReceived,
                              ).withValues(alpha: _nudgeAnimation.value),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _getNudgeGlowColor(nudgedCountReceived)
                                    .withValues(
                                      alpha: _nudgeAnimation.value * 0.3,
                                    ),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: child,
                        ),
                        child: cardWidget,
                      );

                      // Wrap in Stack to add nudge count badge
                      cardWidget = Stack(
                        clipBehavior: Clip.none,
                        children: [
                          cardWidget,
                          Positioned(
                            top: -9,
                            right: -8,
                            child: AnimatedBuilder(
                              animation: _nudgeAnimation,
                              builder: (context, child) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _getNudgeGlowColor(
                                    nudgedCountReceived,
                                  ),
                                  borderRadius: BorderRadius.circular(50),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          _getNudgeGlowColor(
                                            nudgedCountReceived,
                                          ).withValues(
                                            alpha: _nudgeAnimation.value * 0.6,
                                          ),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      getNudgePhrase(nudgedCountReceived),
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: cardWidget,
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

Color _getNudgeColor(int count) {
  if (count == 0) return Colors.orange;
  if (count == 1) return Colors.orange;
  if (count == 2) return Colors.deepOrange;
  return Colors.red; // count == 3
}

Color _getNudgeGlowColor(int count) {
  if (count == 1) return Colors.orange;
  if (count == 2) return Colors.deepOrange;
  return Colors.red; // count == 3
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
    path.moveTo(0, 0); // top-left
    path.lineTo(size.width, 0); // top-right
    path.lineTo(size.width / 2, size.height); // bottom-center (point)
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_TriangleClipper oldClipper) => false;
}
