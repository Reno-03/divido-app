import 'dart:async';
import 'package:divido_app/providers/expense_provider.dart';
import 'package:divido_app/providers/group_provider.dart';
import 'package:divido_app/providers/status_provider.dart';
import 'package:divido_app/screens/status_chip.dart';
import 'package:divido_app/widgets/avatar_image.dart';
import 'package:divido_app/widgets/dashboard_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/current_user.dart';

final _currentUser = CurrentUser.instance;

/// DOCUMENTATION & EXPECTED RESULTS FOR _computeNetByUser:
/// 1) ownerBreakdowns [B 100] -> B = +100
/// 2) payerBreakdowns [{50, owner C}] -> C = -50
/// 3) then paymentsMade [C 20] -> C = -30
/// 4) then paymentsReceived [B 40] after (1) -> B = +60
/// 5) ownerBreakdowns [B 100] plus payerBreakdowns [{100, owner B}] -> B = 0
/// 6) a row for a non-member D -> D absent
/// 7) ownerBreakdowns [B 0.1, B 0.2] then paymentsReceived [B 0.3] -> abs < 0.01 (settled)
/// 8) empty inputs -> empty map
/// 9) ownerBreakdowns [B 100], paymentsReceived [B 130] -> B = -30
Map<String, double> _computeNetByUser({
  required List<Map<String, dynamic>> ownerBreakdowns,
  required List<Map<String, dynamic>> payerBreakdowns,
  required List<Map<String, dynamic>> paymentsMade,
  required List<Map<String, dynamic>> paymentsReceived,
  required Set<String> memberIds,
}) {
  final Map<String, double> net = {};
  for (final row in ownerBreakdowns) {
    final payerId = row['payer_id'] as String;
    final amount = (row['amount'] as num).toDouble();
    net[payerId] = (net[payerId] ?? 0.0) + amount;
  }
  for (final row in payerBreakdowns) {
    final ownerId = (row['expenses'] as Map<String, dynamic>)['owner_id'] as String;
    final amount = (row['amount'] as num).toDouble();
    net[ownerId] = (net[ownerId] ?? 0.0) - amount;
  }
  for (final row in paymentsMade) {
    final payeeId = row['payee_id'] as String;
    final amount = (row['amount'] as num).toDouble();
    net[payeeId] = (net[payeeId] ?? 0.0) + amount;
  }
  for (final row in paymentsReceived) {
    final payerId = row['payer_id'] as String;
    final amount = (row['amount'] as num).toDouble();
    net[payerId] = (net[payerId] ?? 0.0) - amount;
  }
  net.removeWhere((uid, _) => !memberIds.contains(uid));
  return net;
}

class BalancePage extends StatefulWidget {
  const BalancePage({super.key});

  @override
  State<BalancePage> createState() => _BalancePageState();
}

class _BalancePageState extends State<BalancePage>
    with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _balances = [];
  bool _isFirstLoad = true;
  String? _error;
  int _requestId = 0;

  ExpenseProvider? _expenseProvider;
  GroupProvider? _groupProvider;
  List<Map<String, dynamic>>? _lastExpenses;
  String? _selectedGroupId;
  List<Map<String, dynamic>>? _lastMembers;
  Timer? _debounceTimer;
  RealtimeChannel? _paymentsChannel;

  late AnimationController _nudgeController;
  late Animation<double> _nudgeAnimation;

  @override
  void initState() {
    super.initState();
    _nudgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _nudgeAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _nudgeController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _expenseProvider = Provider.of<ExpenseProvider>(context, listen: false);
      _groupProvider = Provider.of<GroupProvider>(context, listen: false);

      _expenseProvider?.addListener(_onProvidersChanged);
      _groupProvider?.addListener(_onProvidersChanged);

      _selectedGroupId = _groupProvider?.selectedGroupId;
      _lastMembers = _groupProvider?.members;
      _lastExpenses = _expenseProvider?.expenses;
      _setupPaymentsChannel(_selectedGroupId);
      _reload(forceSkeleton: true);
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _nudgeController.dispose();
    _expenseProvider?.removeListener(_onProvidersChanged);
    _groupProvider?.removeListener(_onProvidersChanged);
    if (_paymentsChannel != null) {
      supabase.removeChannel(_paymentsChannel!);
    }
    super.dispose();
  }

  void _setupPaymentsChannel(String? groupId) {
    if (_paymentsChannel != null) {
      supabase.removeChannel(_paymentsChannel!);
      _paymentsChannel = null;
    }
    if (groupId == null) return;
    _paymentsChannel = supabase
        .channel('balance-payments-$groupId')
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
            if (mounted) _reload();
          },
        )
        .subscribe();
  }

  void _onProvidersChanged() {
    if (!mounted) return;
    final newGroupId = _groupProvider?.selectedGroupId;
    final newMembers = _groupProvider?.members;
    final newExpenses = _expenseProvider?.expenses;

    bool groupChanged = newGroupId != _selectedGroupId;
    bool membersChanged = !identical(newMembers, _lastMembers);
    bool expensesChanged = !identical(newExpenses, _lastExpenses);
    _lastExpenses = newExpenses;

    if (groupChanged || membersChanged || expensesChanged) {
      _selectedGroupId = newGroupId;
      _lastMembers = newMembers;
      _setupPaymentsChannel(newGroupId);
      if (groupChanged) {
        setState(() {
          _balances = [];
          _error = null;
        });
      }
      _reload(forceSkeleton: groupChanged);
    } else {
      _reload();
    }
  }

  void _reload({bool forceSkeleton = false}) {
    _debounceTimer?.cancel();
    if (forceSkeleton && mounted) {
      setState(() {
        _isFirstLoad = true;
        _error = null;
      });
    }
    _debounceTimer = Timer(const Duration(milliseconds: 180), () {
      _executeReload(forceSkeleton: forceSkeleton);
    });
  }

  Future<void> _executeReload({bool forceSkeleton = false}) async {
    final currentRequestId = ++_requestId;

    try {
      final myId = _currentUser.id;
      if (myId == null) {
        if (!mounted || currentRequestId != _requestId) return;
        setState(() {
          _balances = [];
          _isFirstLoad = false;
        });
        return;
      }

      final groupProvider = _groupProvider ?? Provider.of<GroupProvider>(context, listen: false);
      final groupId = groupProvider.selectedGroupId;
      if (groupId == null) {
        if (!mounted || currentRequestId != _requestId) return;
        setState(() {
          _balances = [];
          _isFirstLoad = false;
        });
        return;
      }

      final members = groupProvider.members;
      if (members.isEmpty) {
        // B3: If members empty, don't conclude no balances. Keep loading.
        return;
      }
      final memberIdsList = members.map((m) => m['id'] as String).toList();
      final memberIdsSet = memberIdsList.toSet();

      final results = await Future.wait([
        supabase
            .from('expense_breakdowns')
            .select('amount, expense_id, payer_id, expenses!inner(owner_id)')
            .eq('expenses.owner_id', myId)
            .eq('expenses.group_id', groupId)
            .neq('payer_id', myId),
        supabase
            .from('expense_breakdowns')
            .select('amount, payer_id, expense_id, expenses!inner(owner_id)')
            .eq('payer_id', myId)
            .eq('expenses.group_id', groupId)
            .neq('expenses.owner_id', myId),
        supabase
            .from('payments')
            .select('amount, payee_id')
            .eq('payer_id', myId)
            .eq('group_id', groupId),
        supabase
            .from('payments')
            .select('amount, payer_id')
            .eq('payee_id', myId)
            .eq('group_id', groupId),
        supabase
            .from('nudges')
            .select('to_user_id, nudge_count, last_nudged_at')
            .eq('from_user_id', myId),
        supabase
            .from('nudges')
            .select('from_user_id, nudge_count')
            .eq('to_user_id', myId),
        supabase
            .from('profiles')
            .select('id, firstname, lastname, color, contact_number, is_gcash_ready, status, avatar_url')
            .inFilter('id', memberIdsList),
      ]);

      if (!mounted || currentRequestId != _requestId) return;

      final ownerExpenses = results[0] as List<Map<String, dynamic>>;
      final payerExpenses = results[1] as List<Map<String, dynamic>>;
      final paymentsMade = results[2] as List<Map<String, dynamic>>;
      final paymentsReceived = results[3] as List<Map<String, dynamic>>;
      final nudgesSent = results[4] as List<Map<String, dynamic>>;
      final nudgesReceived = results[5] as List<Map<String, dynamic>>;
      final users = results[6] as List<Map<String, dynamic>>;

      // A8c: Debug check for 1000 rows limit
      if (kDebugMode) {
        if (ownerExpenses.length >= 1000) debugPrint('WARNING: ownerExpenses returned 1000 rows');
        if (payerExpenses.length >= 1000) debugPrint('WARNING: payerExpenses returned 1000 rows');
        if (paymentsMade.length >= 1000) debugPrint('WARNING: paymentsMade returned 1000 rows');
        if (paymentsReceived.length >= 1000) debugPrint('WARNING: paymentsReceived returned 1000 rows');
      }

      final netByUser = _computeNetByUser(
        ownerBreakdowns: ownerExpenses,
        payerBreakdowns: payerExpenses,
        paymentsMade: paymentsMade,
        paymentsReceived: paymentsReceived,
        memberIds: memberIdsSet,
      );

      // B6: Stale nudge cleanup (run in parallel / unblocked, wrapped in try/catch)
      final staleUserIds = <String>[];
      for (final entry in netByUser.entries) {
        if (entry.value >= 0) {
          staleUserIds.add(entry.key);
        }
      }
      if (staleUserIds.isNotEmpty) {
        Unawaited(
          Future.sync(() async {
            try {
              await supabase
                  .from('nudges')
                  .delete()
                  .inFilter('from_user_id', staleUserIds)
                  .eq('to_user_id', myId);
            } catch (_) {}
          }),
        );
      }

      final userMap = {for (var u in users) u['id'] as String: u};
      final nudgesSentMap = {for (var n in nudgesSent) n['to_user_id'] as String: n};
      
      // Build nudgesReceivedMap excluding stale ones
      final nudgesReceivedMap = <String, Map<String, dynamic>>{};
      for (final n in nudgesReceived) {
        final fromId = n['from_user_id'] as String;
        if (!staleUserIds.contains(fromId)) {
          nudgesReceivedMap[fromId] = n;
        }
      }

      final computedBalances = netByUser.entries.map((e) {
        final user = userMap[e.key];
        final nudgeSent = nudgesSentMap[e.key];
        final nudgeReceived = nudgesReceivedMap[e.key];

        final fName = (user?['firstname'] ?? '').toString();
        final lName = (user?['lastname'] ?? '').toString();

        return {
          'user_id': e.key,
          'name': fName.isNotEmpty ? fName : 'Unknown',
          'lastname': lName,
          'net': e.value,
          'color': user?['color'] as String? ?? '#6366F1',
          'contact_number': user?['contact_number'] as String? ?? '',
          'is_gcash_ready': user?['is_gcash_ready'] as bool? ?? false,
          'status': user?['status'] as String? ?? '',
          'nudge_count': nudgeSent?['nudge_count'] as int? ?? 0,
          'last_nudged_at': nudgeSent?['last_nudged_at'] as String? ?? '',
          'is_nudged': nudgeReceived != null,
          'nudged_count_received': nudgeReceived?['nudge_count'] as int? ?? 0,
          'avatar_url': user?['avatar_url'] as String? ?? '',
        };
      }).toList()
        ..sort((a, b) {
          final aNudged = a['nudged_count_received'] as int;
          final bNudged = b['nudged_count_received'] as int;
          final aNet = a['net'] as double;
          final bNet = b['net'] as double;

          int category(double net, int nudged) {
            if (nudged > 0) return 0;
            if (net < -0.01) return 1;
            if (net > 0.01) return 2;
            return 3;
          }

          final aCat = category(aNet, aNudged);
          final bCat = category(bNet, bNudged);

          if (aCat != bCat) return aCat.compareTo(bCat);

          if (aCat == 0) return bNudged.compareTo(aNudged);
          if (aCat == 1) return aNet.compareTo(bNet);
          if (aCat == 2) return bNet.compareTo(aNet);
          return 0;
        });

      if (!mounted || currentRequestId != _requestId) return;
      groupProvider.setGroupUnsettledBalance(
        groupId,
        computedBalances.any(
          (balance) => (balance['net'] as double).abs() >= 0.01,
        ),
      );
      setState(() {
        _balances = computedBalances;
        _isFirstLoad = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || currentRequestId != _requestId) return;
      setState(() {
        _error = e.toString();
        _isFirstLoad = false;
      });
    }
  }

  void Unawaited(Future<void> future) {}

  Future<void> _nudge({
    required String targetUserId,
    required String targetName,
    required int currentCount,
    required String lastNudgedAt,
  }) async {
    final myId = _currentUser.id!;

    if (currentCount >= 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Max nudges reached for $targetName'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 0, left: 16, right: 16),
          ),
        );
      }
      return;
    }

    if (lastNudgedAt.isNotEmpty) {
      final last = DateTime.parse(lastNudgedAt).toLocal();
      final diff = DateTime.now().difference(last);
      if (diff.inHours < 12) {
        final remaining = 12 - diff.inHours;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('You can nudge $targetName again in ${remaining}h'),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 0, left: 16, right: 16),
            ),
          );
        }
        return;
      }
    }

    try {
      await supabase.from('nudges').upsert({
        'from_user_id': myId,
        'to_user_id': targetUserId,
        'nudge_count': currentCount + 1,
        'last_nudged_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'from_user_id, to_user_id');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$targetName has been nudged! 🔔'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 0, left: 16, right: 16),
          ),
        );
        _reload();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send nudge. Please try again.'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 0, left: 16, right: 16),
          ),
        );
      }
    }
  }

  String _safeInitials(String? firstname, String? lastname) {
    final f = (firstname ?? '').trim();
    final l = (lastname ?? '').trim();
    final fInit = f.isNotEmpty ? f[0] : '';
    final lInit = l.isNotEmpty ? l[0] : '';
    final res = '$fInit$lInit'.toUpperCase();
    return res.isEmpty ? '?' : res;
  }

  void _showPaymentDialog({
    required String targetUserId,
    required String targetName,
    required bool isSettle,
    required double suggestedAmount,
  }) {
    final activeGroupId = (_groupProvider ?? Provider.of<GroupProvider>(context, listen: false)).selectedGroupId;
    final amountController = TextEditingController(
      text: suggestedAmount.abs().toStringAsFixed(2),
    );
    final noteController = TextEditingController();
    bool isSubmitting = false;
    String paymentMethod = 'cash';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final parsedAmount = double.tryParse(amountController.text.replaceAll(',', '.')) ?? 0.0;
          final isGreaterThanSuggested = parsedAmount > suggestedAmount.abs() + 0.001;

          return Dialog(
            backgroundColor: const Color(0xFF171A3F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                          isSettle ? Icons.handshake_outlined : Icons.payments_outlined,
                          size: 20,
                          color: isSettle ? Colors.green.shade400 : Colors.red.shade400,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isSettle ? 'Settle with $targetName' : 'Pay $targetName',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              isSettle ? 'Record a received payment' : 'Record a payment you made',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          amountController.dispose();
                          noteController.dispose();
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey.withValues(alpha: 0.2),
                          ),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                    ],
                    onChanged: (_) => setDialogState(() {}),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
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
                  if (isGreaterThanSuggested) ...[
                    const SizedBox(height: 6),
                    Text(
                      'This is more than the current balance of ₱${dashMoney(suggestedAmount.abs())}.',
                      style: const TextStyle(fontSize: 12, color: Colors.amber),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Add a note... (optional)',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
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
                      backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.white.withValues(alpha: 0.3);
                        }
                        return Colors.transparent;
                      }),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              final amount = double.tryParse(
                                amountController.text.replaceAll(',', '.'),
                              );
                              if (amount == null || amount <= 0) return;
                              setDialogState(() => isSubmitting = true);

                              try {
                                final myId = _currentUser.id!;
                                final payerId = isSettle ? targetUserId : myId;
                                final payeeId = isSettle ? myId : targetUserId;

                                await supabase.from('payments').insert({
                                  'payer_id': payerId,
                                  'payee_id': payeeId,
                                  'amount': amount,
                                  'note': noteController.text.isEmpty ? null : noteController.text,
                                  'method': paymentMethod,
                                  'group_id': activeGroupId,
                                });

                                amountController.dispose();
                                noteController.dispose();
                                if (ctx.mounted) Navigator.pop(ctx);
                                _reload();
                              } catch (_) {
                                setDialogState(() => isSubmitting = false);
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text('Failed to record payment. Please try again.'),
                                      behavior: SnackBarBehavior.floating,
                                      margin: EdgeInsets.only(bottom: 0, left: 16, right: 16),
                                    ),
                                  );
                                }
                              }
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
    required Color targetColor,
    required String? targetAvatarUrl,
    required double paymentAmount,
    required String paymentDateStr,
  }) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      backgroundColor: const Color(0xFF171A3F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
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
                  'Remove Payment',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(sheetCtx),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey.withValues(alpha: 0.2),
                    ),
                    child: const Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Remove the ₱${dashMoney(paymentAmount)} payment from $paymentDateStr? This action cannot be undone.',
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetCtx),
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
                      Navigator.pop(sheetCtx);
                      Navigator.pop(ctx);

                      try {
                        await supabase.from('payments').delete().eq('id', paymentId);
                        _reload();

                        // Re-fetch balances first to get updated net, then reopen sheet
                        final myId = _currentUser.id;
                        final groupProvider = _groupProvider ?? Provider.of<GroupProvider>(context, listen: false);
                        final groupId = groupProvider.selectedGroupId;
                        if (myId != null && groupId != null) {
                          final members = groupProvider.members.map((m) => m['id'] as String).toSet();
                          // Run quick queries to compute updated net for target user
                          final ownerExp = await supabase.from('expense_breakdowns').select('amount, expense_id, payer_id, expenses!inner(owner_id)').eq('expenses.owner_id', myId).eq('expenses.group_id', groupId).neq('payer_id', myId);
                          final payerExp = await supabase.from('expense_breakdowns').select('amount, payer_id, expense_id, expenses!inner(owner_id)').eq('payer_id', myId).eq('expenses.group_id', groupId).neq('expenses.owner_id', myId);
                          final pMade = await supabase.from('payments').select('amount, payee_id').eq('payer_id', myId).eq('group_id', groupId);
                          final pRec = await supabase.from('payments').select('amount, payer_id').eq('payee_id', myId).eq('group_id', groupId);

                          final netMap = _computeNetByUser(
                            ownerBreakdowns: ownerExp,
                            payerBreakdowns: payerExp,
                            paymentsMade: pMade,
                            paymentsReceived: pRec,
                            memberIds: members,
                          );
                          final updatedNet = netMap[targetUserId] ?? 0.0;

                          if (mounted) {
                            _showPaymentHistory(
                              targetUserId: targetUserId,
                              targetName: targetName,
                              targetLastname: targetLastname,
                              net: updatedNet,
                              targetColor: targetColor,
                              targetAvatarUrl: targetAvatarUrl,
                            );
                          }
                        }
                      } catch (_) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Failed to remove payment. Please try again.'),
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
                      'Remove',
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

  void _showPaymentHistory({
    required String targetUserId,
    required String targetName,
    required String targetLastname,
    required double net,
    required Color targetColor,
    String? targetAvatarUrl,
  }) async {
    final myId = _currentUser.id!;
    final groupProvider = _groupProvider ?? Provider.of<GroupProvider>(context, listen: false);
    final groupId = groupProvider.selectedGroupId;
    if (groupId == null) return;

    final payments = await supabase
        .from('payments')
        .select('id, amount, note, created_at, payer_id, payee_id, method')
        .or('and(payer_id.eq.$myId,payee_id.eq.$targetUserId),and(payer_id.eq.$targetUserId,payee_id.eq.$myId)')
        .eq('group_id', groupId)
        .order('created_at', ascending: false);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      backgroundColor: const Color(0xFF171A3F),
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.3,
        maxChildSize: 1.0,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _BalanceAvatar(
                    url: targetAvatarUrl,
                    color: targetColor,
                    size: 42,
                    initials: _safeInitials(targetName, targetLastname),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          targetName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          net.abs() < 0.01
                              ? 'All settled up'
                              : net > 0
                              ? 'Owes you ₱${dashMoney(net.abs())}'
                              : 'You owe ₱${dashMoney(net.abs())}',
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
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey.withValues(alpha: 0.2),
                      ),
                      child: const Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: payments.isEmpty
                    ? const Center(
                        child: Text(
                          'No payments yet.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : Builder(
                        builder: (context) {
                          final Map<String, List<Map<String, dynamic>>> grouped = {};
                          for (var p in payments) {
                            final date = DateTime.parse(p['created_at']).toLocal();
                            final dateKey = DateFormat('yyyy-MM-dd').format(date);
                            grouped.putIfAbsent(dateKey, () => []);
                            grouped[dateKey]!.add(p);
                          }

                          final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
                          final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                          final yesterdayStr = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));
                          final fullDateFormatter = DateFormat('MMMM d, yyyy');

                          return ListView.builder(
                            controller: scrollController,
                            itemCount: sortedDates.length,
                            itemBuilder: (ctx, i) {
                              final dateKey = sortedDates[i];
                              final entries = grouped[dateKey]!;

                              String dateLabel;
                              if (dateKey == todayStr) {
                                dateLabel = 'Today';
                              } else if (dateKey == yesterdayStr) {
                                dateLabel = 'Yesterday';
                              } else {
                                try {
                                  dateLabel = fullDateFormatter.format(DateTime.parse(dateKey));
                                } catch (_) {
                                  dateLabel = dateKey;
                                }
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: Text(
                                      dateLabel,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white.withValues(alpha: 0.65),
                                      ),
                                    ),
                                  ),
                                  ...entries.map((p) {
                                    final isPayer = p['payer_id'] == myId;
                                    final amount = (p['amount'] as num).toDouble();
                                    final note = p['note'] as String?;
                                    final paymentId = p['id'] as String;

                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isPayer
                                                  ? Colors.red.withValues(alpha: 0.15)
                                                  : Colors.green.withValues(alpha: 0.15),
                                            ),
                                            child: Icon(
                                              isPayer ? Icons.arrow_upward : Icons.arrow_downward,
                                              size: 18,
                                              color: isPayer ? Colors.red.shade400 : Colors.green.shade400,
                                            ),
                                          ),
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
                                        isPayer ? 'You paid $targetName' : '$targetName paid you',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                      subtitle: note != null && note.isNotEmpty
                                          ? Text(
                                              note,
                                              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                                            )
                                          : null,
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '₱${dashMoney(amount)}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: isPayer ? Colors.red.shade400 : Colors.green.shade400,
                                            ),
                                          ),
                                          if (isPayer) ...[
                                            const SizedBox(width: 8),
                                            GestureDetector(
                                              onTap: () => _confirmDeletePayment(
                                                paymentId: paymentId,
                                                ctx: ctx,
                                                targetUserId: targetUserId,
                                                targetName: targetName,
                                                targetLastname: targetLastname,
                                                targetColor: targetColor,
                                                targetAvatarUrl: targetAvatarUrl,
                                                paymentAmount: amount,
                                                paymentDateStr: dateLabel,
                                              ),
                                              child: Container(
                                                padding: const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: Colors.red.withValues(alpha: 0.12),
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
                color: Colors.white38,
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

            controller.dispose();
            if (ctx.mounted) Navigator.pop(ctx);
            setState(() {});
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

            controller.dispose();
            if (ctx.mounted) Navigator.pop(ctx);
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
                          onTap: () {
                            controller.dispose();
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey.withValues(alpha: 0.2),
                            ),
                            child: const Icon(Icons.close, size: 16, color: Colors.white),
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
                        StatusChip(text: "💸 Pay me via GCash", controller: controller),
                        StatusChip(text: "💵 Pay me via Cash only", controller: controller),
                        StatusChip(text: "🍻 I’ll treat next round", controller: controller),
                        StatusChip(text: "💤 Offline", controller: controller),
                        StatusChip(text: "🚫 Not enough money!", controller: controller),
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

  @override
  Widget build(BuildContext context) {
    if (_isFirstLoad) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Shimmer.fromColors(
              baseColor: Colors.white.withValues(alpha: 0.06),
              highlightColor: Colors.white.withValues(alpha: 0.15),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const DashSkeleton(height: 28, radius: 6),
                          const SizedBox(height: 6),
                          const DashSkeleton(height: 16, radius: 4),
                          const SizedBox(height: 16),
                          Row(
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
                              Expanded(
                                child: Container(
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                              ),
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
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, __) => Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Container(
                            height: 180,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                        childCount: 3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
                const SizedBox(height: 16),
                const Text(
                  'Could not load balances',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => _reload(forceSkeleton: true),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final selectedGroup = Provider.of<GroupProvider>(context, listen: false).selectedGroup;
    final inviteCode = selectedGroup?['invite_code'] as String?;

    double totalOwedToYou = 0;
    double totalYouOwe = 0;
    int owedCount = 0;
    int oweCount = 0;

    for (final entry in _balances) {
      final net = entry['net'] as double;
      if (net > 0.01) {
        totalOwedToYou += net;
        owedCount++;
      } else if (net < -0.01) {
        totalYouOwe += net.abs();
        oweCount++;
      }
    }

    String subtitleText = "You're all settled up";
    if (totalYouOwe >= 0.01) {
      subtitleText = 'You owe ₱${dashMoney(totalYouOwe, trimZeros: true)}';
    } else if (totalOwedToYou >= 0.01) {
      subtitleText = 'People owe you ₱${dashMoney(totalOwedToYou, trimZeros: true)}';
    }

    // Build categories for C5 & C6
    final List<_BalanceRowItem> feedRows = [];
    String? currentCategoryLabel;

    String getCategoryLabel(double net, int nudged) {
      if (nudged > 0) return 'Nudged you';
      if (net < -0.01) return 'You owe';
      if (net > 0.01) return 'Owed to you';
      return 'Settled';
    }

    for (final entry in _balances) {
      final net = entry['net'] as double;
      final nudgedCount = entry['nudged_count_received'] as int;
      final catLabel = getCategoryLabel(net, nudgedCount);

      if (currentCategoryLabel != catLabel) {
        currentCategoryLabel = catLabel;
        feedRows.add(_BalanceRowItem.header(catLabel));
      }
      feedRows.add(_BalanceRowItem.card(entry));
    }

    final myAvatarUrl = CurrentUser.instance.avatarUrl;
    final myBgColor = Color(
      int.parse(
        'FF${(CurrentUser.instance.color ?? '#6366F1').replaceAll('#', '')}',
        radix: 16,
      ),
    );
    final myInitials = _safeInitials(
      CurrentUser.instance.firstname,
      CurrentUser.instance.lastname,
    );

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: RefreshIndicator(
            onRefresh: () async {
              _reload(forceSkeleton: false);
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
                        const Text(
                          'Balances',
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
                          subtitleText,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white60,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: myBgColor,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: AvatarImage(
                                url: myAvatarUrl,
                                size: 36,
                                memCacheWidth: 96,
                                fallback: Center(
                                  child: Text(
                                    myInitials,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onTap: _showStatusEditor,
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Consumer<StatusProvider>(
                                          builder: (context, statusProvider, _) {
                                            final st = statusProvider.status;
                                            return Text(
                                              st != null && st.isNotEmpty
                                                  ? st
                                                  : 'Wanna share something? Add a note!',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: st != null && st.isNotEmpty
                                                    ? Colors.white.withValues(alpha: 0.85)
                                                    : Colors.white.withValues(alpha: 0.35),
                                                fontStyle: st == null || st.isEmpty
                                                    ? FontStyle.italic
                                                    : FontStyle.normal,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryTile(
                                icon: Icons.arrow_downward_rounded,
                                label: 'Owed to you',
                                amount: totalOwedToYou,
                                caption: '$owedCount people',
                                amountColor: totalOwedToYou > 0 ? kDashPositive : Colors.white,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _SummaryTile(
                                icon: Icons.arrow_upward_rounded,
                                label: 'You owe',
                                amount: totalYouOwe,
                                caption: '$oweCount people',
                                amountColor: totalYouOwe > 0 ? kDashNegative : Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                if (_balances.isEmpty)
                  SliverToBoxAdapter(
                    child: _buildNoBalancesState(inviteCode),
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
                          return RepaintBoundary(
                            key: ValueKey(row.entry!['user_id']),
                            child: _BalanceCard(
                              entry: row.entry!,
                              onNudge: _nudge,
                              onPayment: _showPaymentDialog,
                              onHistory: _showPaymentHistory,
                              nudgeAnimation: _nudgeAnimation,
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

  Widget _buildNoBalancesState(String? inviteCode) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 64,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                const SizedBox(height: 16),
                Text(
                  'No balances yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add expenses to start tracking balances',
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
        ),
      ),
    );
  }
}

class _BalanceRowItem {
  final bool isHeader;
  final String? headerLabel;
  final Map<String, dynamic>? entry;

  const _BalanceRowItem._({required this.isHeader, this.headerLabel, this.entry});

  factory _BalanceRowItem.header(String label) => _BalanceRowItem._(isHeader: true, headerLabel: label);
  factory _BalanceRowItem.card(Map<String, dynamic> entry) => _BalanceRowItem._(isHeader: false, entry: entry);
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.amount,
    required this.caption,
    required this.amountColor,
  });

  final IconData icon;
  final String label;
  final double amount;
  final String caption;
  final Color amountColor;

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
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
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
              trimZeros: false,
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

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.entry,
    required this.onNudge,
    required this.onPayment,
    required this.onHistory,
    required this.nudgeAnimation,
  });

  final Map<String, dynamic> entry;
  final Future<void> Function({
    required String targetUserId,
    required String targetName,
    required int currentCount,
    required String lastNudgedAt,
  }) onNudge;
  final void Function({
    required String targetUserId,
    required String targetName,
    required bool isSettle,
    required double suggestedAmount,
  }) onPayment;
  final void Function({
    required String targetUserId,
    required String targetName,
    required String targetLastname,
    required double net,
    required Color targetColor,
    String? targetAvatarUrl,
  }) onHistory;
  final Animation<double> nudgeAnimation;

  @override
  Widget build(BuildContext context) {
    final double net = entry['net'] as double;
    final rawColor = entry['color'] as String? ?? '#6366F1';
    final userColor = dashParseColor(rawColor);
    final bool isZero = net.abs() < 0.01;
    final bool isPositive = net > 0;

    final bool isNudged = entry['is_nudged'] as bool;
    final int nudgedCountReceived = entry['nudged_count_received'] as int;
    final int nudgeCount = entry['nudge_count'] as int;
    final String lastNudgedAt = entry['last_nudged_at'] as String;
    final String status = entry['status'] as String;
    final String userId = entry['user_id'] as String;
    final String name = entry['name'] as String;
    final String lastname = entry['lastname'] as String;
    final String avatarUrl = entry['avatar_url'] as String;
    final String contactNumber = entry['contact_number'] as String;
    final bool isGcashReady = entry['is_gcash_ready'] as bool;

    int nudgeCooldownHoursLeft = 0;
    bool isNudgeOnCooldown = false;
    if (lastNudgedAt.isNotEmpty) {
      final last = DateTime.parse(lastNudgedAt).toLocal();
      final diff = DateTime.now().difference(last);
      isNudgeOnCooldown = diff.inHours < 12;
      nudgeCooldownHoursLeft = (12 - diff.inHours).clamp(1, 12);
    }

    final bool isNudgeDisabled = isNudgeOnCooldown || nudgeCount >= 3;
    final Color balanceColor = isZero ? Colors.grey : (isPositive ? Colors.green : Colors.red);

    Widget cardWidget = Card(
      color: const Color(0xFF0F1128),
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          if (status.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                const SizedBox(width: 30),
                ClipPath(
                  clipper: _TriangleClipper(),
                  child: Container(
                    width: 12,
                    height: 8,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _BalanceAvatar(
                        url: avatarUrl,
                        color: userColor,
                        size: 40,
                        initials: _safeInitials(name, lastname),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _gcashIndicator(isReady: isGcashReady, contactNumber: contactNumber),
                                if (contactNumber.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      contactNumber,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.white.withValues(alpha: 0.7),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  _CopyContactButton(contactNumber: contactNumber),
                                ] else ...[
                                  const SizedBox(width: 8),
                                  const Text(
                                    'No contact number',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.white38,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    DashAmount(
                      net.abs(),
                      size: 24,
                      weight: FontWeight.w800,
                      color: balanceColor,
                      trimZeros: false,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isZero ? 'settled' : (isPositive ? 'owes you' : 'you owe'),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: balanceColor.withValues(alpha: 0.75),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!isZero && !isPositive)
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => onPayment(
                      targetUserId: userId,
                      targetName: name,
                      isSettle: false,
                      suggestedAmount: net.abs(),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                        ),
                        border: Border(
                          top: BorderSide(
                            color: Colors.red.withValues(alpha: 0.25),
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
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
                    onTap: () => onHistory(
                      targetUserId: userId,
                      targetName: name,
                      targetLastname: lastname,
                      net: net,
                      targetColor: userColor,
                      targetAvatarUrl: avatarUrl,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.10),
                        borderRadius: const BorderRadius.only(
                          bottomRight: Radius.circular(16),
                        ),
                        border: Border(
                          top: BorderSide(
                            color: Colors.blue.withValues(alpha: 0.25),
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
          if (!isZero && isPositive)
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: isNudgeDisabled
                        ? null
                        : () => onNudge(
                              targetUserId: userId,
                              targetName: name,
                              currentCount: nudgeCount,
                              lastNudgedAt: lastNudgedAt,
                            ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: isNudgeDisabled
                            ? Colors.white.withValues(alpha: 0.04)
                            : _getNudgeColor(nudgeCount).withValues(alpha: 0.15),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                        ),
                        border: Border(
                          top: BorderSide(
                            color: isNudgeDisabled
                                ? Colors.white.withValues(alpha: 0.08)
                                : _getNudgeColor(nudgeCount).withValues(alpha: 0.25),
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isNudgeOnCooldown
                                ? Icons.hourglass_empty
                                : nudgeCount >= 3
                                ? Icons.notifications_off_outlined
                                : Icons.notifications_outlined,
                            size: 22,
                            color: isNudgeDisabled
                                ? Colors.white.withValues(alpha: 0.25)
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
                                  ? Colors.white.withValues(alpha: 0.25)
                                  : _getNudgeColor(nudgeCount),
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
                    onTap: () => onHistory(
                      targetUserId: userId,
                      targetName: name,
                      targetLastname: lastname,
                      net: net,
                      targetColor: userColor,
                      targetAvatarUrl: avatarUrl,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.10),
                        borderRadius: const BorderRadius.only(
                          bottomRight: Radius.circular(16),
                        ),
                        border: Border(
                          top: BorderSide(
                            color: Colors.blue.withValues(alpha: 0.25),
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
          if (isZero)
            GestureDetector(
              onTap: () => onHistory(
                targetUserId: userId,
                targetName: name,
                targetLastname: lastname,
                net: net,
                targetColor: userColor,
                targetAvatarUrl: avatarUrl,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.10),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: Colors.blue.withValues(alpha: 0.25),
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
    );

    if (isNudged) {
      cardWidget = AnimatedBuilder(
        animation: nudgeAnimation,
        builder: (context, child) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: _getNudgeGlowColor(nudgedCountReceived).withValues(
                alpha: nudgeAnimation.value,
              ),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: _getNudgeGlowColor(nudgedCountReceived).withValues(
                  alpha: nudgeAnimation.value * 0.3,
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

      cardWidget = Stack(
        clipBehavior: Clip.none,
        children: [
          cardWidget,
          Positioned(
            top: -9,
            right: -8,
            child: AnimatedBuilder(
              animation: nudgeAnimation,
              builder: (context, child) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getNudgeGlowColor(nudgedCountReceived),
                  borderRadius: BorderRadius.circular(50),
                  boxShadow: [
                    BoxShadow(
                      color: _getNudgeGlowColor(nudgedCountReceived).withValues(
                        alpha: nudgeAnimation.value * 0.6,
                      ),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Text(
                  _getNudgePhrase(nudgedCountReceived),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
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
  }

  Widget _gcashIndicator({required bool isReady, required String contactNumber}) {
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
                color: Colors.white38,
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

  String _getNudgePhrase(int count) {
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

  Color _getNudgeColor(int count) {
    if (count == 0) return Colors.orange;
    if (count == 1) return Colors.orange;
    if (count == 2) return Colors.deepOrange;
    return Colors.red;
  }

  Color _getNudgeGlowColor(int count) {
    if (count == 1) return Colors.orange;
    if (count == 2) return Colors.deepOrange;
    return Colors.red;
  }
}

class _BalanceAvatar extends StatelessWidget {
  const _BalanceAvatar({
    required this.url,
    required this.color,
    required this.size,
    required this.initials,
  });

  final String? url;
  final Color color;
  final double size;
  final String initials;

  @override
  Widget build(BuildContext context) {
    Widget initialsWidget() {
      return Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: size * 0.35,
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
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, color.withValues(alpha: 0.7)],
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: url != null && url!.isNotEmpty
            ? ClipOval(
                child: AvatarImage(
                  url: url,
                  size: size,
                  memCacheWidth: 96,
                  fallback: initialsWidget(),
                ),
              )
            : initialsWidget(),
      ),
    );
  }
}

String _safeInitials(String? f, String? l) {
  final fn = (f ?? '').trim();
  final ln = (l ?? '').trim();
  final fInit = fn.isNotEmpty ? fn[0] : '';
  final lInit = ln.isNotEmpty ? ln[0] : '';
  final res = '$fInit$lInit'.toUpperCase();
  return res.isEmpty ? '?' : res;
}

class _CopyContactButton extends StatefulWidget {
  const _CopyContactButton({required this.contactNumber});
  final String contactNumber;

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
        if (!mounted) return;
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
            color: _copied ? Colors.green.shade400 : Colors.white.withValues(alpha: 0.4),
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
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width / 2, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_TriangleClipper oldClipper) => false;
}