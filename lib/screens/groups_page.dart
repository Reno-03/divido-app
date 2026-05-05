import 'package:divido_app/screens/group_info_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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

  // groupId -> net balance (positive = owed to you, negative = you owe)
  Map<String, double> _groupBalances = {};
  bool _isLoadingBalances = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Provider.of<GroupProvider>(context, listen: false).fetchGroups();
      _fetchAllGroupBalances();
    });
  }

  Future<void> _fetchAllGroupBalances() async {
    if (!mounted) return;
    final groups = Provider.of<GroupProvider>(context, listen: false).groups;
    if (groups.isEmpty) return;

    final currentUserId = CurrentUser.instance.id;
    if (currentUserId == null) return;

    setState(() => _isLoadingBalances = true);

    final groupIds = groups.map((g) => g['id'] as String).toList();

    // Run all 4 queries in parallel across all groups at once
    final results = await Future.wait([
      // Breakdowns on expenses YOU own — others owe you
      _supabase
          .from('expense_breakdowns')
          .select('amount, expenses!inner(owner_id, group_id)')
          .eq('expenses.owner_id', currentUserId)
          .neq('payer_id', currentUserId)
          .filter('expenses.group_id', 'in', groupIds),

      // Breakdowns where YOU are the payer — you owe the expense owner
      _supabase
          .from('expense_breakdowns')
          .select('amount, expenses!inner(owner_id, group_id)')
          .eq('payer_id', currentUserId)
          .neq('expenses.owner_id', currentUserId)
          .filter('expenses.group_id', 'in', groupIds),

      // Payments YOU made to others (reduces what you owe)
      _supabase
          .from('payments')
          .select('amount, group_id')
          .eq('payer_id', currentUserId)
          .filter('group_id', 'in', groupIds),

      // Payments others made TO YOU (reduces what they owe)
      _supabase
          .from('payments')
          .select('amount, group_id')
          .eq('payee_id', currentUserId)
          .filter('group_id', 'in', groupIds),
    ]);

    final Map<String, double> balances = {for (var id in groupIds) id: 0.0};

    // Others owe you → positive
    for (final row in results[0] as List) {
      final gid = row['expenses']['group_id'] as String;
      balances[gid] = (balances[gid] ?? 0) + (row['amount'] as num).toDouble();
    }

    // You owe others → negative
    for (final row in results[1] as List) {
      final gid = row['expenses']['group_id'] as String;
      balances[gid] = (balances[gid] ?? 0) - (row['amount'] as num).toDouble();
    }

    // Payments you made → you owed less, so positive adjustment
    for (final row in results[2] as List) {
      final gid = row['group_id'] as String;
      balances[gid] = (balances[gid] ?? 0) + (row['amount'] as num).toDouble();
    }

    // Payments received → they owed less, so negative adjustment
    for (final row in results[3] as List) {
      final gid = row['group_id'] as String;
      balances[gid] = (balances[gid] ?? 0) - (row['amount'] as num).toDouble();
    }

    if (mounted) {
      setState(() {
        _groupBalances = balances;
        _isLoadingBalances = false;
      });
    }
  }

  void _showCreateGroupSheet() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      backgroundColor: const Color(0xFF171A3F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
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
                    'Create Group',
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
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Group Name',
                  prefixIcon: const Icon(Icons.group_outlined, size: 20),
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
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: descController,
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                  prefixIcon: const Icon(Icons.edit_note_outlined, size: 20),
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
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final groupProvider = context.read<GroupProvider>();
                          final name = nameController.text.trim();
                          if (name.isEmpty) return;
                          setModalState(() => isSaving = true);
                          try {
                            await groupProvider.createGroup(
                              name,
                              description: descController.text.trim().isEmpty
                                  ? null
                                  : descController.text.trim(),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            _fetchAllGroupBalances();
                          } catch (e) {
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          } finally {
                            setModalState(() => isSaving = false);
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
                  child: isSaving
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
        ),
      ),
    );
  }

  void _showJoinGroupSheet() {
    final codeController = TextEditingController();
    bool isJoining = false;
    String? errorMessage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      backgroundColor: const Color(0xFF171A3F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
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
                    'Join Group',
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
                controller: codeController,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Invite Code',
                  hintText: 'e.g. A1B2C3D4',
                  prefixIcon: const Icon(Icons.key_outlined, size: 20),
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
                ),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isJoining
                      ? null
                      : () async {
                          final code = codeController.text.trim();
                          if (code.isEmpty) return;
                          setModalState(() {
                            isJoining = true;
                            errorMessage = null;
                          });
                          final error = await Provider.of<GroupProvider>(
                            context,
                            listen: false,
                          ).joinGroup(code);
                          if (error != null) {
                            setModalState(() {
                              errorMessage = error;
                              isJoining = false;
                            });
                          } else {
                            if (ctx.mounted) Navigator.pop(ctx);
                            _fetchAllGroupBalances();
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
                  child: isJoining
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
        ),
      ),
    );
  }

  /// The balance pill shown under the group name
  Widget _buildBalancePill(String groupId) {
    if (_isLoadingBalances) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        width: 80,
        height: 18,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
      );
    }

    final net = _groupBalances[groupId] ?? 0.0;

    // if balance is close enough to zero, show "Settled" pill instead of "You owe / owed to you"
    if (net.abs() < 0.01) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
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

    final bool youOwe = net < 0;
    final color = youOwe ? Colors.redAccent : Colors.greenAccent;
    final bgColor = youOwe
        ? Colors.red.withValues(alpha: 0.15)
        : Colors.green.withValues(alpha: 0.15);
    final label = youOwe
        ? 'You owe ₱${net.abs().toStringAsFixed(2)}'
        : '₱${net.toStringAsFixed(2)} owed to you';

    return Container(
      margin: const EdgeInsets.only(top: 6),
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

  @override
  Widget build(BuildContext context) {
    return Consumer<GroupProvider>(
      builder: (context, groupProvider, _) {
        final groups = groupProvider.groups;
        final isLoading = groupProvider.isLoading;

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Groups',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          body: isLoading
              ? const Center(child: CircularProgressIndicator())
              : groups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.group_outlined,
                        size: 64,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No groups yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create or join a group to get started',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: _showCreateGroupSheet,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Create'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF171A3F),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 20,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: _showJoinGroupSheet,
                            icon: const Icon(Icons.key_outlined, size: 18),
                            label: const Text('Join'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 20,
                              ),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    await Provider.of<GroupProvider>(
                      context,
                      listen: false,
                    ).fetchGroups();
                    await _fetchAllGroupBalances();
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      final groupId = group['id'] as String;
                      final isSelected =
                          groupProvider.selectedGroupId == groupId;
                      final avatarUrl = group['avatar_url'] as String?;

                      return GestureDetector(
                        onTap: () {
                          groupProvider.selectGroup(groupId);
                          Navigator.pop(context);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.blue.withValues(alpha: 0.1)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.blue.withValues(alpha: 0.4)
                                  : Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Row(
                            children: [
                              // group avatar
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? Colors.blue.withValues(alpha: 0.2)
                                      : Colors.white.withValues(alpha: 0.08),
                                ),
                                child: ClipOval(
                                  child:
                                      avatarUrl != null && avatarUrl.isNotEmpty
                                      ? Image.network(
                                          '$avatarUrl?v=${DateTime.now().millisecondsSinceEpoch}',
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => Icon(
                                            Icons.group,
                                            size: 22,
                                            color: isSelected
                                                ? Colors.blue.shade300
                                                : Colors.white.withValues(
                                                    alpha: 0.4,
                                                  ),
                                          ),
                                        )
                                      : Icon(
                                          Icons.group,
                                          size: 22,
                                          color: isSelected
                                              ? Colors.blue.shade300
                                              : Colors.white.withValues(
                                                  alpha: 0.4,
                                                ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 14),

                              // name + description + balance pill
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      group['name'] as String,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      (group['description'] != null &&
                                              (group['description'] as String)
                                                  .isNotEmpty)
                                          ? group['description'] as String
                                          : 'No description',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.white.withValues(
                                          alpha:
                                              (group['description'] != null &&
                                                  (group['description']
                                                          as String)
                                                      .isNotEmpty)
                                              ? 0.4
                                              : 0.2,
                                        ),
                                        fontStyle:
                                            (group['description'] != null &&
                                                (group['description'] as String)
                                                    .isNotEmpty)
                                            ? FontStyle.normal
                                            : FontStyle.italic,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    // ← balance pill lives here
                                    _buildBalancePill(groupId),
                                  ],
                                ),
                              ),

                              // action buttons
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              GroupInfoPage(group: group),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: const BoxDecoration(),
                                      child: Icon(
                                        Icons.arrow_forward_ios,
                                        size: 16,
                                        color: Colors.white.withValues(
                                          alpha: 0.4,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
          bottomNavigationBar: groups.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
                          icon: const Icon(Icons.key_outlined, size: 18, color: Colors.white),
                          label: const Text(
                            'Join Group',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
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
}
