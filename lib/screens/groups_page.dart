import 'package:divido_app/screens/group_info_page.dart';
import 'package:divido_app/widgets/avatar_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:divido_app/services/current_user.dart';
import '../providers/group_provider.dart';

class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key});

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  final _supabase = Supabase.instance.client;
  int _balancesRequestId = 0;
  bool _balancesReady = false;
  List<String> _order = [];
  static DateTime? _lastFetchAt;
  static List<String> _lastGroupIds = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final groupProvider = context.read<GroupProvider>();
      if (groupProvider.groups.isEmpty) {
        await groupProvider.fetchGroups();
      }
      if (groupProvider.groupBalances.isNotEmpty) {
        _balancesReady = true;
        _updateOrder(groupProvider.groups, groupProvider.groupBalances);
      }
      _fetchAllGroupBalances();
    });
  }

  void _updateOrder(
    List<Map<String, dynamic>> groups,
    Map<String, double> balances,
  ) {
    final groupMap = {for (var g in groups) g['id'] as String: g};
    final currentIds = groupMap.keys.toSet();

    final newOrder = _order.where((id) => currentIds.contains(id)).toList();
    for (final id in currentIds) {
      if (!newOrder.contains(id)) {
        newOrder.add(id);
      }
    }

    int category(double net) {
      if (net < -0.01) return 0; // You owe
      if (net > 0.01) return 1; // Owes you
      return 2; // Settled
    }

    newOrder.sort((aId, bId) {
      final aGroup = groupMap[aId]!;
      final bGroup = groupMap[bId]!;
      final aNet = balances[aId] ?? 0.0;
      final bNet = balances[bId] ?? 0.0;

      final aCat = category(aNet);
      final bCat = category(bNet);

      if (aCat != bCat) return aCat.compareTo(bCat);

      final netCompare = bNet.abs().compareTo(aNet.abs());
      if (netCompare != 0) return netCompare;

      final aName = (aGroup['name'] as String).toLowerCase();
      final bName = (bGroup['name'] as String).toLowerCase();
      final nameCompare = aName.compareTo(bName);
      if (nameCompare != 0) return nameCompare;

      return aId.compareTo(bId);
    });

    _order = newOrder;
  }

  void _accumulateBalances(
    List rows,
    Map<String, double> balances,
    double sign,
    String Function(Map<String, dynamic>) extractor,
  ) {
    for (final row in rows) {
      final map = row as Map<String, dynamic>;
      final gid = extractor(map);
      final amount = (map['amount'] as num).toDouble();
      balances[gid] = (balances[gid] ?? 0.0) + sign * amount;
    }
  }

  Future<void> _fetchAllGroupBalances({bool force = false}) async {
    if (!mounted) return;
    final groupProvider = context.read<GroupProvider>();
    final groups = groupProvider.groups;
    if (groups.isEmpty) {
      if (mounted) {
        setState(() {
          _balancesReady = true;
        });
      }
      return;
    }

    final currentUserId = CurrentUser.instance.id;
    if (currentUserId == null) {
      if (mounted) {
        setState(() {
          _balancesReady = true;
        });
      }
      return;
    }

    final groupIds = groups.map((g) => g['id'] as String).toList();

    if (!force &&
        _lastFetchAt != null &&
        _lastGroupIds.length == groupIds.length &&
        _lastGroupIds.every(groupIds.contains)) {
      if (DateTime.now().difference(_lastFetchAt!) < const Duration(seconds: 30)) {
        if (mounted) {
          setState(() {
            _balancesReady = true;
          });
        }
        return;
      }
    }

    final requestId = ++_balancesRequestId;

    try {
      final results = await Future.wait([
        _supabase
            .from('expense_breakdowns')
            .select('amount, expenses!inner(owner_id, group_id)')
            .eq('expenses.owner_id', currentUserId)
            .neq('payer_id', currentUserId)
            .filter('expenses.group_id', 'in', groupIds),
        _supabase
            .from('expense_breakdowns')
            .select('amount, expenses!inner(owner_id, group_id)')
            .eq('payer_id', currentUserId)
            .neq('expenses.owner_id', currentUserId)
            .filter('expenses.group_id', 'in', groupIds),
        _supabase
            .from('payments')
            .select('amount, group_id')
            .eq('payer_id', currentUserId)
            .filter('group_id', 'in', groupIds),
        _supabase
            .from('payments')
            .select('amount, group_id')
            .eq('payee_id', currentUserId)
            .filter('group_id', 'in', groupIds),
      ]);

      if (!mounted || requestId != _balancesRequestId) return;

      final Map<String, double> balances = {for (var id in groupIds) id: 0.0};

      _accumulateBalances(
        results[0] as List,
        balances,
        1.0,
        (r) => (r['expenses'] as Map)['group_id'] as String,
      );
      _accumulateBalances(
        results[1] as List,
        balances,
        -1.0,
        (r) => (r['expenses'] as Map)['group_id'] as String,
      );
      _accumulateBalances(
        results[2] as List,
        balances,
        1.0,
        (r) => r['group_id'] as String,
      );
      _accumulateBalances(
        results[3] as List,
        balances,
        -1.0,
        (r) => r['group_id'] as String,
      );

      groupProvider.setGroupBalances(balances);
      _lastFetchAt = DateTime.now();
      _lastGroupIds = groupIds;
      _updateOrder(groupProvider.groups, groupProvider.groupBalances);
    } catch (e) {
      debugPrint('balances fetch error: $e');
    } finally {
      if (mounted && requestId == _balancesRequestId) {
        _balancesReady = true;
        setState(() {});
      }
    }
  }

  void _showCreateGroupSheet() {
    _showAppSheet(
      context,
      (_) => CreateGroupSheet(
        onCreated: () {
          _updateOrder(
            context.read<GroupProvider>().groups,
            context.read<GroupProvider>().groupBalances,
          );
          _fetchAllGroupBalances(force: true);
        },
      ),
    );
  }

  void _showJoinGroupSheet() {
    _showAppSheet(
      context,
      (_) => JoinGroupSheet(
        onJoined: () {
          _updateOrder(
            context.read<GroupProvider>().groups,
            context.read<GroupProvider>().groupBalances,
          );
          _fetchAllGroupBalances(force: true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GroupProvider>(
      builder: (context, groupProvider, _) {
        final rawGroups = groupProvider.groups;
        final groupMap = {for (var g in rawGroups) g['id'] as String: g};

        if (_order.isEmpty && rawGroups.isNotEmpty) {
          _updateOrder(rawGroups, groupProvider.groupBalances);
        } else {
          final currentIds = groupMap.keys.toSet();
          final orderIds = _order.toSet();
          if (currentIds.difference(orderIds).isNotEmpty ||
              orderIds.difference(currentIds).isNotEmpty) {
            _updateOrder(rawGroups, groupProvider.groupBalances);
          }
        }

        final showSkeleton =
            (groupProvider.isLoading && rawGroups.isEmpty) ||
            (rawGroups.isNotEmpty &&
                !_balancesReady &&
                groupProvider.groupBalances.isEmpty);

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Groups',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          body: showSkeleton
              ? _buildShimmerList()
              : rawGroups.isEmpty
              ? _EmptyGroupsState(
                  onCreate: _showCreateGroupSheet,
                  onJoin: _showJoinGroupSheet,
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    await context.read<GroupProvider>().fetchGroups();
                    _updateOrder(
                      context.read<GroupProvider>().groups,
                      context.read<GroupProvider>().groupBalances,
                    );
                    await _fetchAllGroupBalances(force: true);
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: _order.length + 2,
                    addAutomaticKeepAlives: false,
                    findChildIndexCallback: (Key key) {
                      if (key is ValueKey<String>) {
                        final index = _order.indexOf(key.value);
                        return index == -1 ? null : index + 2;
                      }
                      return null;
                    },
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return const _GroupsOverview();
                      }
                      if (index == 1) {
                        return _GroupListHeading(count: _order.length);
                      }

                      final groupId = _order[index - 2];
                      final group = groupMap[groupId];
                      if (group == null) return const SizedBox.shrink();

                      final isSelected =
                          groupProvider.selectedGroupId == groupId;
                      final net = groupProvider.groupBalances[groupId];

                      return _GroupTile(
                        key: ValueKey(groupId),
                        group: group,
                        isSelected: isSelected,
                        net: net,
                        avatarVersion: groupProvider.groupAvatarVersion,
                        onTap: () {
                          if (!isSelected) {
                            groupProvider.selectGroup(groupId);
                          }
                          Navigator.pop(context);
                        },
                        onInfoTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupInfoPage(group: group),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
          bottomNavigationBar: rawGroups.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _showCreateGroupSheet,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text(
                            'Create Group',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF171A3F),
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _showJoinGroupSheet,
                          icon: const Icon(
                            Icons.key_outlined,
                            size: 18,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Join Group',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildShimmerList() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade800,
      highlightColor: Colors.grey.shade700,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 7,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 180,
                      height: 11,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 80,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupsOverview extends StatelessWidget {
  const _GroupsOverview();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF292E68), Color(0xFF1D214C)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Shared plans,',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Text(
                  'simpler spending.',
                  style: TextStyle(
                    color: Color(0xFFB8B9FF),
                    fontSize: 21,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Keep the people and expenses you share, all in one place.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.groups_rounded,
              color: Color(0xFFB8B9FF),
              size: 31,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupListHeading extends StatelessWidget {
  const _GroupListHeading({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
      child: Row(
        children: [
          const Text(
            'YOUR GROUPS',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyGroupsState extends StatelessWidget {
  const _EmptyGroupsState({required this.onCreate, required this.onJoin});

  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: const Color(0xFFB8B9FF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: const Color(0xFFB8B9FF).withValues(alpha: 0.18),
                  ),
                ),
                child: const Icon(
                  Icons.groups_rounded,
                  size: 42,
                  color: Color(0xFFB8B9FF),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Shared expenses start here',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Create a group for your household, trip, or friends—or join one with an invite code.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add, size: 19),
                  label: const Text(
                    'Create a group',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF171A3F),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onJoin,
                  icon: const Icon(Icons.key_outlined, size: 18),
                  label: const Text('Join with an invite code'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showAppSheet(BuildContext context, WidgetBuilder builder) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.85),
    backgroundColor: const Color(0xFF171A3F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: builder,
  );
}

class _SheetHeader extends StatelessWidget {
  final String title;

  const _SheetHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
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
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            GestureDetector(
              onTap: () => Navigator.pop(context),
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
      ],
    );
  }
}

InputDecoration _fieldDecoration(String label, IconData icon, {String? hint}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: Icon(icon, size: 20),
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
    labelStyle: TextStyle(
      color: Colors.white.withValues(alpha: 0.5),
    ),
  );
}

class _BalancePill extends StatelessWidget {
  final double? net;

  const _BalancePill({required this.net});

  @override
  Widget build(BuildContext context) {
    if (net == null) {
      return Container(
        width: 80,
        height: 18,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
      );
    }

    final val = net!;
    if (val.abs() < 0.01) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.white54,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            const Text(
              'Settled',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final bool youOwe = val < 0;
    final color = youOwe ? Colors.redAccent : Colors.greenAccent;
    final bgColor = youOwe
        ? Colors.red.withValues(alpha: 0.15)
        : Colors.green.withValues(alpha: 0.15);
    final label = youOwe
        ? 'You owe ₱${val.abs().toStringAsFixed(2)}'
        : '₱${val.toStringAsFixed(2)} owed to you';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final Map<String, dynamic> group;
  final bool isSelected;
  final double? net;
  final int avatarVersion;
  final VoidCallback onTap;
  final VoidCallback onInfoTap;

  const _GroupTile({
    super.key,
    required this.group,
    required this.isSelected,
    required this.net,
    required this.avatarVersion,
    required this.onTap,
    required this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = group['name'] as String? ?? '';
    final description = group['description'] as String? ?? '';
    final hasDescription = description.isNotEmpty;
    final avatarUrl = group['avatar_url'] as String?;
    final fullAvatarUrl = avatarUrl != null && avatarUrl.isNotEmpty
        ? '$avatarUrl?v=$avatarVersion'
        : null;

    final fallbackIcon = Icon(
      Icons.group,
      size: 22,
      color: isSelected
          ? Colors.blue.shade300
          : Colors.white.withValues(alpha: 0.4),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isSelected
            ? const Color(0xFF252A5A)
            : Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF8587FF).withValues(alpha: 0.65)
                    : Colors.white.withValues(alpha: 0.09),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: isSelected
                            ? const Color(0xFFB8B9FF).withValues(alpha: 0.14)
                            : Colors.white.withValues(alpha: 0.07),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: fullAvatarUrl != null
                            ? AvatarImage(
                                url: fullAvatarUrl,
                                size: 52,
                                memCacheWidth: 144,
                                memCacheHeight: 144,
                                fallback: fallbackIcon,
                              )
                            : fallbackIcon,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasDescription ? description : 'No description',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(
                                alpha: hasDescription ? 0.55 : 0.3,
                              ),
                              fontStyle: hasDescription
                                  ? FontStyle.normal
                                  : FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFFB8B9FF),
                          size: 20,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Group details',
                      onPressed: onInfoTap,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.more_horiz,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 15,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'Your balance',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.58),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    _BalancePill(net: net),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CreateGroupSheet extends StatefulWidget {
  final VoidCallback onCreated;

  const CreateGroupSheet({super.key, required this.onCreated});

  @override
  State<CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<CreateGroupSheet> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetHeader(title: 'Create Group'),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: _fieldDecoration('Group Name', Icons.group_outlined),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _descController,
            decoration: _fieldDecoration(
              'Description (optional)',
              Icons.edit_note_outlined,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSaving
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final groupProvider = context.read<GroupProvider>();
                      final name = _nameController.text.trim();
                      if (name.isEmpty) return;

                      setState(() => _isSaving = true);
                      try {
                        await groupProvider.createGroup(
                          name,
                          description: _descController.text.trim().isEmpty
                              ? null
                              : _descController.text.trim(),
                        );
                        if (mounted) Navigator.pop(context);
                        widget.onCreated();
                      } catch (e) {
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      } finally {
                        if (mounted) setState(() => _isSaving = false);
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF171A3F),
                padding: const EdgeInsets.symmetric(vertical: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF171A3F),
                      ),
                    )
                  : const Text(
                      'Create Group',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class JoinGroupSheet extends StatefulWidget {
  final VoidCallback onJoined;

  const JoinGroupSheet({super.key, required this.onJoined});

  @override
  State<JoinGroupSheet> createState() => _JoinGroupSheetState();
}

class _JoinGroupSheetState extends State<JoinGroupSheet> {
  final _codeController = TextEditingController();
  bool _isJoining = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetHeader(title: 'Join Group'),
          const SizedBox(height: 20),
          TextField(
            controller: _codeController,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: _fieldDecoration(
              'Invite Code',
              Icons.key_outlined,
              hint: 'e.g. A1B2C3D4',
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isJoining
                  ? null
                  : () async {
                      final code = _codeController.text.trim();
                      if (code.isEmpty) return;
                      setState(() {
                        _isJoining = true;
                        _errorMessage = null;
                      });
                      try {
                        final error =
                            await context.read<GroupProvider>().joinGroup(code);

                        if (error != null) {
                          if (mounted) {
                            setState(() {
                              _errorMessage = error;
                              _isJoining = false;
                            });
                          }
                        } else {
                          if (mounted) Navigator.pop(context);
                          widget.onJoined();
                        }
                      } catch (e) {
                        if (mounted) {
                          setState(() {
                            _errorMessage = 'Failed to join group: $e';
                            _isJoining = false;
                          });
                        }
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF171A3F),
                padding: const EdgeInsets.symmetric(vertical: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isJoining
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF171A3F),
                      ),
                    )
                  : const Text(
                      'Join Group',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
