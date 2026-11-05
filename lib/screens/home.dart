import 'dart:async';

import 'package:divido_app/providers/status_provider.dart';
import 'package:divido_app/screens/create_expense_modal.dart';
import 'package:divido_app/screens/dashboard_page.dart';
import 'package:divido_app/services/changelog_service.dart';
import 'package:divido_app/services/offline_cache.dart';
import 'package:divido_app/widgets/changelog_dialog.dart';
import 'package:divido_app/widgets/avatar_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final Set<int> _visitedPages = {0};
  late GroupProvider _groupProvider;
  late ExpenseProvider _expenseProvider;
  VoidCallback? _groupListener;
  bool _groupListenerAdded = false;
  String? _lastFetchedGroupId;

  final List<Widget> _pages = const [
    DashboardPage(),
    AllPage(),
    MinePage(),
    BalancePage(),
  ];

  void switchTab(int index) {
    if (!mounted || _currentIndex == index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = index;
      _visitedPages.add(index);
    });
  }

  @override
  void initState() {
    super.initState();

    final statusProvider = context.read<StatusProvider>();
    statusProvider.setStatus(CurrentUser.instance.status);
    _groupProvider = context.read<GroupProvider>();
    _expenseProvider = context.read<ExpenseProvider>();
    _groupListener = () {
      final groupId = _groupProvider.selectedGroupId;
      if (groupId == _lastFetchedGroupId) return;
      _lastFetchedGroupId = groupId;
      if (groupId != null) {
        _expenseProvider.fetchExpenses(groupId);
      }
    };
    _groupProvider.addListener(_groupListener!);
    _groupListenerAdded = true;

    Future.microtask(() async {
      try {
        if (!mounted) return;
        final session = Supabase.instance.client.auth.currentSession;

        if (session == null || CurrentUser.instance.id == null) {
          if (!mounted || !context.mounted) return;
          Navigator.pushReplacementNamed(context, '/login');
          return;
        }

        unawaited(_refreshProfile(session.user.id));
        await _groupProvider.fetchGroups();
      } catch (error) {
        debugPrint('HomePage initialization error: $error');
      }
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

  Future<void> _refreshProfile(String userId) async {
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      if (profile['id'] != userId) {
        throw StateError('The fetched profile does not match the active user.');
      }
      CurrentUser.instance.setFromMap(profile);
      await OfflineCache.write(OfflineCache.profileKey(userId), profile);
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('Profile refresh failed; using saved profile when available: $error');
    }
  }

  @override
  void dispose() {
    if (_groupListenerAdded && _groupListener != null) {
      _groupProvider.removeListener(_groupListener!);
    }
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
    final messenger = ScaffoldMessenger.of(context);
    final expenseProvider = context.read<ExpenseProvider>();
    final groupProvider = context.read<GroupProvider>();
    final currentUserId = CurrentUser.instance.id;
    final groupId = groupProvider.selectedGroupId;

    if (groupId == null) return;

    Map<String, dynamic> expenseResponse;
    try {
      expenseResponse = await supabase
          .from('expenses')
          .insert({
            'title': title,
            'total': total,
            'owner_id': currentUserId,
            'group_id': groupId,
            'description': description,
          })
          .select()
          .single();
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(_expenseFailureSnackBar);
      }
      return;
    }

    final expenseId = expenseResponse['id'];
    final rows = <Map<String, dynamic>>[];
    for (final payerId in payerIds) {
      // TODO: Equal split shares can differ from the total by a few centavos (100 split 3 ways gives 33.33 x 3 = 99.99).
      final amount = isEqualSplit
          ? ((total / payerIds.length) * 100).round() / 100
          : customAmounts[payerId] ?? 0;
      rows.add({
        'expense_id': expenseId,
        'payer_id': payerId,
        'amount': amount,
      });
    }

    try {
      await supabase.from('expense_breakdowns').insert(rows);
    } catch (_) {
      try {
        await supabase.from('expenses').delete().eq('id', expenseId);
      } catch (_) {}
      if (mounted) {
        messenger.showSnackBar(_expenseFailureSnackBar);
      }
      return;
    }

    await expenseProvider.refresh(groupId);
  }

  void _showCreateExpenseModal() {
    final groupProvider = context.read<GroupProvider>();

    if (groupProvider.members.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invite someone to the group to create an expense.'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 0, left: 16, right: 16),
        ),
      );
      return;
    }

    switchTab(2);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      backgroundColor: const Color(0xFF171A3F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => CreateExpenseModal(onSubmit: _createExpense),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawColor = CurrentUser.instance.color ?? '#6366F1';
    final userColor = Color(
      int.parse('FF${rawColor.replaceAll('#', '')}', radix: 16),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (_currentIndex != 0) switchTab(0);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Consumer<GroupProvider>(
            builder: (context, groupProvider, _) {
              final selectedGroup = groupProvider.selectedGroup;
              final hasGroups = groupProvider.groups.isNotEmpty;
              return GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/groups'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selectedGroup != null) ...[
                      _GroupAvatar(
                        avatarUrl: selectedGroup['avatar_url'] as String?,
                        avatarVersion: groupProvider.groupAvatarVersion,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        selectedGroup != null
                            ? selectedGroup['name'] as String
                            : _titleForIndex(_currentIndex),
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
              );
            },
          ),
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.group_outlined),
              onPressed: () {
                Navigator.pushNamed(context, '/groups').then((_) {
                  final groupId = _groupProvider.selectedGroupId;
                  if (groupId != null) {
                    _expenseProvider.fetchExpenses(groupId);
                  }
                });
              },
            ),
          ],
        ),
        drawer: _HomeDrawer(
          userColor: userColor,
          currentIndex: _currentIndex,
          onNavigate: switchTab,
          onProfileReturned: () {
            if (mounted) setState(() {});
          },
        ),
        body: Consumer<GroupProvider>(
          builder: (context, groupProvider, _) {
            if (groupProvider.isLoading && groupProvider.groups.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (groupProvider.groups.isEmpty) {
              return const _NoGroupSelected();
            }
            return IndexedStack(
              index: _currentIndex,
              children: [
                for (var index = 0; index < _pages.length; index++)
                  _visitedPages.contains(index)
                      ? _pages[index]
                      : const SizedBox.shrink(),
              ],
            );
          },
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        floatingActionButton: Consumer<GroupProvider>(
          builder: (context, groupProvider, _) {
            if (groupProvider.groups.isEmpty) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(top: 30),
              child: FloatingActionButton(
                heroTag: 'home_create_expense_fab',
                tooltip: 'Add expense',
                onPressed: _showCreateExpenseModal,
                backgroundColor: const Color(0xFFFFFFFF),
                shape: const CircleBorder(),
                child: const Icon(
                  Icons.add,
                  color: Color(0xFF0F1128),
                  size: 32,
                ),
              ),
            );
          },
        ),
        bottomNavigationBar: Consumer<GroupProvider>(
          builder: (context, groupProvider, _) {
            if (groupProvider.groups.isEmpty) return const SizedBox.shrink();
            return _HomeBottomBar(
              currentIndex: _currentIndex,
              onSelect: switchTab,
              hasUnsettledBalance:
                  groupProvider.groupUnsettledBalances[
                    groupProvider.selectedGroupId
                  ] ??
                  false,
            );
          },
        ),
      ),
    );
  }
}

const _expenseFailureSnackBar = SnackBar(
  content: Text('Failed to create expense. Please try again.'),
  behavior: SnackBarBehavior.floating,
  margin: EdgeInsets.only(bottom: 0, left: 16, right: 16),
);

String _titleForIndex(int index) {
  switch (index) {
    case 1:
      return 'All Expenses';
    case 2:
      return 'My Expenses';
    case 3:
      return 'Balances';
    default:
      return 'Dashboard';
  }
}

String _safeInitials(String? firstName, String? lastName) {
  final firstInitial = firstName != null && firstName.isNotEmpty
      ? firstName[0].toUpperCase()
      : '';
  final lastInitial = lastName != null && lastName.isNotEmpty
      ? lastName[0].toUpperCase()
      : '';
  return '$firstInitial$lastInitial';
}

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.avatarUrl, required this.avatarVersion});

  final String? avatarUrl;
  final int avatarVersion;

  @override
  Widget build(BuildContext context) {
    final fallback = const Icon(Icons.group, size: 16, color: Colors.white54);
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.1),
      ),
      child: ClipOval(
        child: avatarUrl != null && avatarUrl!.isNotEmpty
            ? AvatarImage(
                url: '$avatarUrl?v=$avatarVersion',
                size: 32,
                memCacheWidth: 96,
                fallback: fallback,
              )
            : fallback,
      ),
    );
  }
}

class _HomeDrawer extends StatelessWidget {
  const _HomeDrawer({
    required this.userColor,
    required this.currentIndex,
    required this.onNavigate,
    required this.onProfileReturned,
  });

  final Color userColor;
  final int currentIndex;
  final ValueChanged<int> onNavigate;
  final VoidCallback onProfileReturned;

  @override
  Widget build(BuildContext context) {
    final firstName = CurrentUser.instance.firstname ?? '';
    final lastName = CurrentUser.instance.lastname ?? '';
    final initials = _safeInitials(firstName, lastName);
    final avatarUrl = CurrentUser.instance.avatarUrl;
    final fullName = '$firstName $lastName'.trim();
    final displayName = fullName.isNotEmpty
        ? fullName
        : CurrentUser.instance.username ?? 'Your account';

    return Drawer(
      backgroundColor: const Color(0xFF0F1128),
      child: SafeArea(
        child: Consumer<GroupProvider>(
          builder: (context, groupProvider, _) => Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF252A61), Color(0xFF171A3F)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            'assets/divido_logo_only.png',
                            width: 42,
                            height: 32,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'DIVIDO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: userColor,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                              width: 2,
                            ),
                          ),
                          child: ClipOval(
                            child: avatarUrl != null && avatarUrl.isNotEmpty
                                ? AvatarImage(
                                    url: avatarUrl,
                                    size: 54,
                                    memCacheWidth: 96,
                                    fallback: _InitialsAvatar(
                                      initials: initials,
                                    ),
                                  )
                                : _InitialsAvatar(initials: initials),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (CurrentUser.instance.email case final email?
                                  when email.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                  children: [
                    _CurrentGroupCard(
                      groupName:
                          groupProvider.selectedGroup?['name'] as String?,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/groups');
                      },
                    ),
                    const SizedBox(height: 20),
                    const _DrawerSectionLabel(label: 'YOUR SPACE'),
                    const SizedBox(height: 6),
                    _HomeDrawerItem(
                      icon: Icons.space_dashboard_outlined,
                      label: 'Dashboard',
                      selected: currentIndex == 0,
                      onTap: () => _selectPage(context, 0),
                    ),
                    _HomeDrawerItem(
                      icon: Icons.receipt_long_outlined,
                      label: 'All expenses',
                      selected: currentIndex == 1,
                      onTap: () => _selectPage(context, 1),
                    ),
                    _HomeDrawerItem(
                      icon: Icons.person_outline,
                      label: 'My expenses',
                      selected: currentIndex == 2,
                      onTap: () => _selectPage(context, 2),
                    ),
                    _HomeDrawerItem(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Balances',
                      selected: currentIndex == 3,
                      onTap: () => _selectPage(context, 3),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(color: Color(0xFF292C4A), height: 1),
                    ),
                    const _DrawerSectionLabel(label: 'MORE'),
                    const SizedBox(height: 6),
                    _HomeDrawerItem(
                      icon: Icons.manage_accounts_outlined,
                      label: 'Profile',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/profile').then((_) {
                          onProfileReturned();
                        });
                      },
                    ),
                    _HomeDrawerItem(
                      icon: Icons.install_mobile_outlined,
                      label: 'Install App',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/install-guide');
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Column(
                  children: [
                    const Divider(color: Color(0xFF292C4A), height: 1),
                    ListTile(
                      onTap: () => _logOut(context, groupProvider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      minLeadingWidth: 24,
                      horizontalTitleGap: 14,
                      leading: const Icon(
                        Icons.logout_rounded,
                        size: 21,
                        color: Color(0xFFFF8585),
                      ),
                      title: const Text(
                        'Log out',
                        style: TextStyle(
                          color: Color(0xFFFF8585),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.people_alt_outlined,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Shared spending, made simple',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
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

  void _selectPage(BuildContext context, int index) {
    Navigator.pop(context);
    onNavigate(index);
  }

  Future<void> _logOut(
    BuildContext context,
    GroupProvider groupProvider,
  ) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    final userId = CurrentUser.instance.id;

    try {
      await Supabase.instance.client.auth.signOut();
      if (userId != null) await OfflineCache.clearUser(userId);
      CurrentUser.instance.clear();
      groupProvider.clear();

      if (!navigator.mounted) return;
      navigator.pushNamedAndRemoveUntil('/login', (_) => false);
    } catch (error) {
      debugPrint('Logout failed: $error');
      if (!messenger.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Unable to log out. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _CurrentGroupCard extends StatelessWidget {
  const _CurrentGroupCard({required this.groupName, required this.onTap});

  final String? groupName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasGroup = groupName != null && groupName!.isNotEmpty;
    final accent = const Color(0xFFB8B9FF);

    return Material(
      color: const Color(0xFF191C3B),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.groups_outlined, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasGroup ? 'CURRENT GROUP' : 'GET STARTED',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasGroup ? groupName! : 'Create or join a group',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _HomeDrawerItem extends StatelessWidget {
  const _HomeDrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFB8B9FF);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        onTap: onTap,
        selected: selected,
        selectedTileColor: accent.withValues(alpha: 0.12),
        selectedColor: accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        minLeadingWidth: 24,
        horizontalTitleGap: 14,
        leading: Icon(icon, size: 21),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials,
        style: const TextStyle(fontSize: 24, color: Colors.white),
      ),
    );
  }
}

class _NoGroupSelected extends StatelessWidget {
  const _NoGroupSelected();

  @override
  Widget build(BuildContext context) {
    return Center(
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
            onPressed: () => Navigator.pushNamed(context, '/groups'),
            icon: const Icon(Icons.group_outlined, size: 18),
            label: const Text(
              'Go to Groups',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF171A3F),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeBottomBar extends StatelessWidget {
  const _HomeBottomBar({
    required this.currentIndex,
    required this.onSelect,
    required this.hasUnsettledBalance,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final bool hasUnsettledBalance;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      color: const Color(0xFF0F1128),
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 60,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = (constraints.maxWidth - 48) / 4;
            final indicatorWidth = itemWidth < 96 ? itemWidth - 12 : 84.0;
            final indicatorLeft =
                currentIndex * itemWidth + (currentIndex >= 2 ? 48 : 0);
            final duration = MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 260);

            return Stack(
              fit: StackFit.expand,
              children: [
                AnimatedPositioned(
                  left: indicatorLeft + (itemWidth - indicatorWidth) / 2,
                  top: 6,
                  bottom: 6,
                  width: indicatorWidth,
                  duration: duration,
                  curve: Curves.easeInOutCubic,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _HomeBottomBarItem(
                        icon: Icons.dashboard_rounded,
                        label: 'Dashboard',
                        index: 0,
                        currentIndex: currentIndex,
                        onSelect: onSelect,
                      ),
                    ),
                    Expanded(
                      child: _HomeBottomBarItem(
                        icon: Icons.list,
                        label: 'All',
                        index: 1,
                        currentIndex: currentIndex,
                        onSelect: onSelect,
                      ),
                    ),
                    const SizedBox(width: 48),
                    Expanded(
                      child: _HomeBottomBarItem(
                        icon: Icons.person,
                        label: 'Mine',
                        index: 2,
                        currentIndex: currentIndex,
                        onSelect: onSelect,
                      ),
                    ),
                    Expanded(
                      child: _HomeBottomBarItem(
                        icon: Icons.account_balance_wallet,
                        label: 'Balance',
                        index: 3,
                        currentIndex: currentIndex,
                        onSelect: onSelect,
                        showUnsettledDot: hasUnsettledBalance,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HomeBottomBarItem extends StatelessWidget {
  const _HomeBottomBarItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onSelect,
    this.showUnsettledDot = false,
  });

  final IconData icon;
  final String label;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final bool showUnsettledDot;

  @override
  Widget build(BuildContext context) {
    final isSelected = currentIndex == index;
    final color = isSelected
      ? const Color(0xFF0F1128)
        : Colors.white.withValues(alpha: 0.4);

    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label tab${showUnsettledDot ? ', unsettled' : ''}',
      child: SizedBox(
        height: 48,
        child: InkResponse(
          onTap: isSelected ? null : () => onSelect(index),
          radius: 16,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, color: color),
                    if (showUnsettledDot)
                      Positioned(
                        top: -2,
                        right: -4,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53935),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF0F1128),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
