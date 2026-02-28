import 'package:divido_app/screens/create_expense_modal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:divido_app/services/current_user.dart';

import '../providers/expense_provider.dart';
import 'all_page.dart';
import 'mine_page.dart';
import 'balance_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [AllPage(), MinePage(), BalancePage()];

  @override
  void initState() {
    super.initState();

    Future.microtask(() async {
      // Check actual Supabase session, not just in-memory
      final session = Supabase.instance.client.auth.currentSession;

      if (session == null || CurrentUser.instance.id == null) {
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      Provider.of<ExpenseProvider>(context, listen: false).fetchExpenses();
    });
  }

  // ==============================
  // CREATE EXPENSE
  // ==============================
  Future<void> _createExpense(
    String title,
    double total,
    Set<String> payerIds,
    Map<String, double> customAmounts,
    bool isEqualSplit,
  ) async {
    final supabase = Supabase.instance.client;
    final currentUserId = CurrentUser.instance.id;

    final expenseResponse = await supabase
        .from('expenses')
        .insert({'title': title, 'total': total, 'owner_id': currentUserId})
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

    await Provider.of<ExpenseProvider>(context, listen: false).refresh();
  }

  // ==============================
  // CREATE MODAL
  // ==============================
  void _showCreateExpenseModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => CreateExpenseModal(onSubmit: _createExpense),
    );
  }

  // ==============================
  // BUILD
  // ==============================
  @override
  Widget build(BuildContext context) {
    // Parse the user's color
    final rawColor = CurrentUser.instance.color ?? '#6366F1';
    final userColor = Color(
      int.parse('FF${rawColor.replaceAll('#', '')}', radix: 16),
    );

    return Scaffold(
      appBar: AppBar(
        // Dynamic title based on selected tab
        title: Text(
          _currentIndex == 0
              ? 'All Expenses'
              : _currentIndex == 1
              ? 'My Expenses'
              : 'Balances',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              // Profile Header
              UserAccountsDrawerHeader(
                decoration: const BoxDecoration(
                  color: Color(0xFF171A3F), // match app background
                ),
                accountName: Text(
                  '${CurrentUser.instance.firstname} ${CurrentUser.instance.lastname ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                accountEmail: Text(CurrentUser.instance.email ?? ''),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: userColor, // use the parsed user color
                  child: Text(
                    '${CurrentUser.instance.firstname?[0].toUpperCase()}${CurrentUser.instance.lastname?[0].toUpperCase() ?? ''}',
                    style: const TextStyle(fontSize: 24, color: Colors.white),
                  ),
                ),
              ),

              // Nav items
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Profile'),
                onTap: () {
                  Navigator.pop(context); // close drawer
                  Navigator.pushNamed(context, '/profile');
                },
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(index: _currentIndex, children: _pages),

      floatingActionButton: _currentIndex == 1
          ? FloatingActionButton(
              onPressed: _showCreateExpenseModal,
              child: const Icon(Icons.add),
            )
          : null,

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'All'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Mine'),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Balance',
          ),
        ],
      ),
    );
  }
}
