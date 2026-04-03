import 'package:divido_app/screens/create_expense_modal.dart';
import 'package:divido_app/screens/dashboard_page.dart';
import 'package:divido_app/services/changelog_service.dart';
import 'package:divido_app/widgets/changelog_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:divido_app/services/current_user.dart';

import '../providers/expense_provider.dart';
import '../providers/group_provider.dart';
import 'all_page.dart';
import 'mine_page.dart';
import 'balance_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  void switchTab(int index) {
    if (mounted) {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  final List<Widget> _pages = const [
    DashboardPage(),
    AllPage(),
    MinePage(),
    BalancePage(),
  ];

  late VoidCallback _groupListener;

  @override
  void initState() {
    super.initState();

    Future.microtask(() async {
      final session = Supabase.instance.client.auth.currentSession;

      if (session == null || CurrentUser.instance.id == null) {
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      final groupProvider = Provider.of<GroupProvider>(context, listen: false);
      final expenseProvider = Provider.of<ExpenseProvider>(
        context,
        listen: false,
      );

      // store listener so we can remove it on dispose
      _groupListener = () {
        final groupId = groupProvider.selectedGroupId;
        if (groupId != null) {
          expenseProvider.fetchExpenses(groupId);
        }
      };

      groupProvider.addListener(_groupListener);

      // initial fetch — this triggers the listener which fetches expenses
      await groupProvider.fetchGroups();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final shouldShow = await ChangelogService.shouldShow();
      if (shouldShow && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const ChangelogDialog(),
        );
      }
    });
  }

  @override
  void dispose() {
    Provider.of<GroupProvider>(
      context,
      listen: false,
    ).removeListener(_groupListener);
    super.dispose();
  }

  Future<void> _createExpense(
    String title,
    double total,
    Set<String> payerIds,
    Map<String, double> customAmounts,
    bool isEqualSplit,
    String description,
  ) async {
    final supabase = Supabase.instance.client;
    final currentUserId = CurrentUser.instance.id;
    final groupId = Provider.of<GroupProvider>(
      context,
      listen: false,
    ).selectedGroupId;

    if (groupId == null) return;

    final expenseResponse = await supabase
        .from('expenses')
        .insert({
          'title': title,
          'total': total,
          'owner_id': currentUserId,
          'group_id': groupId, // attach to group
          'description': description,
        })
        .select()
        .single();

    final expenseId = expenseResponse['id'];

    for (final payerId in payerIds) {
      final amount = isEqualSplit
          ? ((total / payerIds.length) * 100).round() / 100
          : customAmounts[payerId] ?? 0;

      await supabase.from('expense_breakdowns').insert({
        'expense_id': expenseId,
        'payer_id': payerId,
        'amount': amount,
      });
    }

    await Provider.of<ExpenseProvider>(context, listen: false).refresh(groupId);
  }

  void _showCreateExpenseModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => CreateExpenseModal(onSubmit: _createExpense),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawColor = CurrentUser.instance.color ?? '#6366F1';
    final userColor = Color(
      int.parse('FF${rawColor.replaceAll('#', '')}', radix: 16),
    );

    return Consumer<GroupProvider>(
      builder: (context, groupProvider, _) {
        final selectedGroup = groupProvider.selectedGroup;
        final hasGroups = groupProvider.groups.isNotEmpty;

        return Scaffold(
          appBar: AppBar(
            title: GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/groups'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      selectedGroup != null
                          ? selectedGroup['name'] as String
                          : _currentIndex == 0
                          ? 'Dashboard'
                          : _currentIndex == 1
                          ? 'All Expenses'
                          : _currentIndex == 2
                          ? 'My Expenses'
                          : 'Balances',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasGroups) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 20,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ],
                ],
              ),
            ),
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            actions: [
              // groups button
              IconButton(
                icon: const Icon(Icons.group_outlined),
                onPressed: () =>
                    Navigator.pushNamed(context, '/groups').then((_) {
                      // refresh expenses when coming back from groups
                      final gid = groupProvider.selectedGroupId;
                      if (gid != null) {
                        Provider.of<ExpenseProvider>(
                          context,
                          listen: false,
                        ).fetchExpenses(gid);
                      }
                    }),
              ),
            ],
          ),

          drawer: Drawer(
            child: SafeArea(
              child: Column(
                children: [
                  UserAccountsDrawerHeader(
                    decoration: const BoxDecoration(color: Color(0xFF171A3F)),
                    accountName: Text(
                      '${CurrentUser.instance.firstname} ${CurrentUser.instance.lastname ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    accountEmail: Text(CurrentUser.instance.email ?? ''),
                    currentAccountPicture: () {
                      final avatarUrl = CurrentUser.instance.avatarUrl;
                      final initials =
                          '${CurrentUser.instance.firstname?[0].toUpperCase() ?? ''}${CurrentUser.instance.lastname?[0].toUpperCase() ?? ''}';
                      return Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: userColor,
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
                                      fontSize: 24,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              )
                            : Center(
                                child: Text(
                                  initials,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                      );
                    }(),
                  ),

                  // selected group indicator
                  if (selectedGroup != null)
                    Container(
                      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.group_outlined,
                            size: 16,
                            color: Colors.blue.shade300,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              selectedGroup['name'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue.shade300,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                  ListTile(
                    leading: const Icon(Icons.group_outlined),
                    title: const Text('Groups'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/groups');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('Profile'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/profile').then((_) {
                        setState(() {});
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

          // show no group selected state
          body: !hasGroups
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
                        'No group selected',
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
                      FilledButton.icon(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/groups'),
                        icon: const Icon(Icons.group_outlined, size: 18),
                        label: const Text(
                          'Go to Groups',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF171A3F),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 24,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : IndexedStack(index: _currentIndex, children: _pages),

          floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
          floatingActionButton: hasGroups
              ? Container(
                  margin: const EdgeInsets.only(top: 30),
                  child: FloatingActionButton(
                    onPressed: () {
                      setState(() => _currentIndex = 2); // Switch to Mine Page
                      _showCreateExpenseModal();
                    },
                    backgroundColor: const Color(0xFFFFFFFF), // highlight action color
                    shape: const CircleBorder(),
                    child: const Icon(Icons.add, color: Color(0xFF0F1128), size: 32),
                  ),
                )
              : null,

          bottomNavigationBar: hasGroups
              ? BottomAppBar(
                  color: const Color(0xFF0F1128),
                  shape: const CircularNotchedRectangle(),
                  notchMargin: 8.0,
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    height: 60,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildNavItem(Icons.dashboard_rounded, 'Dashboard', 0),
                        _buildNavItem(Icons.list, 'All', 1),
                        const SizedBox(width: 48), // Spacing for the FAB notch
                        _buildNavItem(Icons.person, 'Mine', 2),
                        _buildNavItem(Icons.account_balance_wallet, 'Balance', 3),
                      ],
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? Colors.white : Colors.white.withValues(alpha: 0.4);
    
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
