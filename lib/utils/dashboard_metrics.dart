/// In-place dashboard aggregations for the PWA (single JS isolate).
/// Walks expense maps already in memory — no copies, no `compute()`.
Future<Map<String, dynamic>> aggregateDashboardMetrics({
  required String currentUserId,
  required int nowMs,
  required List<Map<String, dynamic>> expenses,
  required List<Map<String, dynamic>> paymentsMade,
  required List<Map<String, dynamic>> paymentsReceived,
}) async {
  const weekMs = 7 * 24 * 60 * 60 * 1000;
  final startOfThisWeek = nowMs - weekMs;
  final startOfLastWeek = nowMs - (2 * weekMs);
  const yieldEvery = 40;

  double totalGroup = 0;
  double totalOwn = 0;
  double thisWeekGroup = 0;
  double lastWeekGroup = 0;
  double thisWeekOwn = 0;
  double lastWeekOwn = 0;
  final topExpenses = <Map<String, dynamic>>[];
  final netByUser = <String, double>{};

  void addNet(String uid, double val) {
    if (uid == currentUserId) return;
    netByUser[uid] = (netByUser[uid] ?? 0) + val;
  }

  for (var i = 0; i < expenses.length; i++) {
    if (i > 0 && i % yieldEvery == 0) {
      await Future<void>.delayed(Duration.zero);
    }

    final expense = expenses[i];
    final total = (expense['total'] as num?)?.toDouble() ?? 0.0;
    totalGroup += total;

    final ownerId = expense['owner_id'] as String?;
    final createdAtMs = expenseCreatedAtMs(expense);
    final breakdowns =
        expense['expense_breakdowns'] as List<dynamic>? ?? const [];

    double ownAmt = 0;
    for (final rawB in breakdowns) {
      final b = rawB as Map;
      final payerId = b['payer_id'] as String?;
      final amount = (b['amount'] as num?)?.toDouble() ?? 0.0;
      if (payerId == currentUserId) {
        ownAmt += amount;
      }

      if (ownerId == currentUserId &&
          payerId != null &&
          payerId != currentUserId) {
        addNet(payerId, amount);
      } else if (payerId == currentUserId &&
          ownerId != null &&
          ownerId != currentUserId) {
        addNet(ownerId, -amount);
      }
    }
    totalOwn += ownAmt;

    if (createdAtMs > startOfThisWeek) {
      thisWeekGroup += total;
      thisWeekOwn += ownAmt;
      if (ownAmt > 0) {
        _insertTopExpense(topExpenses, {
          'title': expense['title'],
          'ownAmt': ownAmt,
          'total': total,
          'owner_name': _ownerName(expense),
          'avatar_url':
              (expense['profiles'] as Map<String, dynamic>?)?['avatar_url'],
        });
      }
    } else if (createdAtMs > startOfLastWeek && createdAtMs <= startOfThisWeek) {
      lastWeekGroup += total;
      lastWeekOwn += ownAmt;
    }
  }

  for (final row in paymentsMade) {
    final uid = row['uid'] as String?;
    final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
    if (uid != null) addNet(uid, amount);
  }
  for (final row in paymentsReceived) {
    final uid = row['uid'] as String?;
    final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
    if (uid != null) addNet(uid, -amount);
  }

  double owedToYou = 0;
  double youOwe = 0;
  final nets = <Map<String, dynamic>>[];
  for (final entry in netByUser.entries) {
    final net = entry.value;
    if (net > 0) {
      owedToYou += net;
    } else if (net < 0) {
      youOwe += -net;
    }
    nets.add({'uid': entry.key, 'net': net});
  }
  nets.sort(
    (a, b) => (b['net'] as double).abs().compareTo((a['net'] as double).abs()),
  );

  return {
    'totalGroupExpense': totalGroup,
    'totalOwnExpense': totalOwn,
    'thisWeekGroup': thisWeekGroup,
    'lastWeekGroup': lastWeekGroup,
    'thisWeekOwn': thisWeekOwn,
    'lastWeekOwn': lastWeekOwn,
    'totalOwedToYou': owedToYou,
    'totalYouOwe': youOwe,
    'topExpensesThisWeek': topExpenses,
    'nets': nets,
  };
}

void _insertTopExpense(
  List<Map<String, dynamic>> top,
  Map<String, dynamic> item,
) {
  const keep = 3;
  final ownAmt = item['ownAmt'] as double;
  if (top.length < keep) {
    top.add(item);
    if (top.length == keep) {
      top.sort(
        (a, b) => (b['ownAmt'] as double).compareTo(a['ownAmt'] as double),
      );
    }
    return;
  }
  if (ownAmt <= (top.last['ownAmt'] as double)) return;
  top[keep - 1] = item;
  top.sort((a, b) => (b['ownAmt'] as double).compareTo(a['ownAmt'] as double));
}

int expenseCreatedAtMs(Map<String, dynamic> expense) {
  final local = expense['created_at_local'];
  if (local is DateTime) return local.millisecondsSinceEpoch;

  final createdAt = expense['created_at'] as String?;
  if (createdAt == null || createdAt.isEmpty) return 0;
  final normalized = createdAt.endsWith('Z') ? createdAt : '${createdAt}Z';
  return DateTime.parse(normalized).toLocal().millisecondsSinceEpoch;
}

String _ownerName(Map<String, dynamic> expense) {
  final profiles = expense['profiles'] as Map<String, dynamic>?;
  final firstname = profiles?['firstname'] as String? ?? 'Unknown';
  final lastname = profiles?['lastname'] as String? ?? '';
  return '$firstname $lastname'.trim();
}
