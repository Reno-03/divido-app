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

  final List<Widget> _pages = const [
    AllPage(),
    MinePage(),
    BalancePage(),
  ];

  @override
  void initState() {
    super.initState();

    // 🔥 Load expenses when app starts
    Future.microtask(() {
      Provider.of<ExpenseProvider>(context, listen: false)
          .fetchExpenses();
    });
  }

  // ==============================
  // CREATE EXPENSE
  // ==============================
  Future<void> _createExpense(
    String title,
    double total,
    Set<String> payerIds,
  ) async {
    final supabase = Supabase.instance.client;
    final currentUserId = CurrentUser.instance.id;

    // 1️⃣ Create expense
    final expenseResponse = await supabase
        .from('expenses')
        .insert({
          'title': title,
          'total': total,
          'owner_id': currentUserId,
        })
        .select()
        .single();

    final expenseId = expenseResponse['id'];

    // 2️⃣ Split equally
    final splitAmount = total / payerIds.length;

    // 3️⃣ Insert breakdowns
    for (final payerId in payerIds) {
      await supabase.from('expense_breakdowns').insert({
        'expense_id': expenseId,
        'payer_id': payerId,
        'amount': splitAmount,
      });
    }

    // 🔥 Refresh Provider (this updates ALL pages automatically)
    await Provider.of<ExpenseProvider>(context, listen: false)
        .refresh();
  }

  // ==============================
  // CREATE MODAL
  // ==============================
  void _showCreateExpenseModal() {
    final titleController = TextEditingController();
    final totalController = TextEditingController();
    final currentUserId = CurrentUser.instance.id;
    final supabase = Supabase.instance.client;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return FutureBuilder(
          future: supabase.from('users').select('id, firstname, lastname'),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              );
            }

            // Remove current user from checkboxes
            final users = List<Map<String, dynamic>>.from(
              snapshot.data as List,
            ).where((user) => user['id'] != currentUserId).toList();

            final selectedUsers = <String>{};

            return StatefulBuilder(
              builder: (context, setModalState) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                    left: 16,
                    right: 16,
                    top: 16,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: titleController,
                          decoration:
                              const InputDecoration(labelText: 'Title'),
                        ),
                        TextField(
                          controller: totalController,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Total'),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Select Payers:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),

                        ...users.map((user) {
                          final name =
                              '${user['firstname']} ${user['lastname']}';

                          return CheckboxListTile(
                            title: Text(name),
                            value: selectedUsers.contains(user['id']),
                            onChanged: (value) {
                              setModalState(() {
                                if (value == true) {
                                  selectedUsers.add(user['id']);
                                } else {
                                  selectedUsers.remove(user['id']);
                                }
                              });
                            },
                          );
                        }),

                        const SizedBox(height: 16),

                        ElevatedButton(
                          onPressed: () async {
                            final title = titleController.text;
                            final total =
                                double.tryParse(totalController.text) ?? 0;

                            if (title.isEmpty || total <= 0) return;

                            // Automatically include current user
                            selectedUsers.add(currentUserId!);

                            await _createExpense(
                              title,
                              total,
                              selectedUsers,
                            );

                            Navigator.pop(context);
                          },
                          child: const Text('Create'),
                        ),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ==============================
  // BUILD
  // ==============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),

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
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'All',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Mine',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Balance',
          ),
        ],
      ),
    );
  }
}