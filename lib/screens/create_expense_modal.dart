import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:divido_app/services/current_user.dart';

class CreateExpenseModal extends StatefulWidget {
  final Future<void> Function(
    String title,
    double total,
    Set<String> payerIds,
    Map<String, double> customAmounts,
    bool isEqualSplit,
  ) onSubmit;

  const CreateExpenseModal({super.key, required this.onSubmit});

  @override
  State<CreateExpenseModal> createState() => _CreateExpenseModalState();
}

class _CreateExpenseModalState extends State<CreateExpenseModal> {
  final _titleController = TextEditingController();
  final _totalController = TextEditingController();
  final _ownerCustomAmount = TextEditingController();

  final _selectedUsers = <String>{};
  final _customAmounts = <String, TextEditingController>{};
  bool _isEqualSplit = true;
  bool _isLoading = false;
  List<Map<String, dynamic>> _users = [];

  final _supabase = Supabase.instance.client;
  final _currentUserId = CurrentUser.instance.id;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final response =
        await _supabase.from('profiles').select('id, firstname, lastname');
    final users = List<Map<String, dynamic>>.from(response)
        .where((u) => u['id'] != _currentUserId)
        .toList();

    setState(() {
      _users = users;
      for (final user in users) {
        _customAmounts[user['id']] = TextEditingController();
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _totalController.dispose();
    _ownerCustomAmount.dispose();
    for (final c in _customAmounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _assignedTotal {
    final payersSum = _selectedUsers.fold<double>(
      0,
      (sum, uid) =>
          sum + (double.tryParse(_customAmounts[uid]?.text ?? '') ?? 0),
    );
    return payersSum + (double.tryParse(_ownerCustomAmount.text) ?? 0);
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final total = double.tryParse(_totalController.text) ?? 0;

    if (title.isEmpty || total <= 0) return;
    if (_selectedUsers.isEmpty) return;

    if (!_isEqualSplit) {
      if ((_assignedTotal - total).abs() > 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Custom amounts must add up to the total.'),
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    final customAmountValues = {
      for (final uid in _selectedUsers)
        uid: double.tryParse(_customAmounts[uid]?.text ?? '') ?? 0,
    };
    customAmountValues[_currentUserId!] =
        double.tryParse(_ownerCustomAmount.text) ?? 0;

    final payerIds = {..._selectedUsers, _currentUserId};

    await widget.onSubmit(
      title,
      total,
      payerIds,
      customAmountValues,
      _isEqualSplit,
    );

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: _totalController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Total'),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 20),

            const Text(
              'Split Mode:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<bool>(
                    title: const Text('Equal'),
                    value: true,
                    groupValue: _isEqualSplit,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (_) => setState(() => _isEqualSplit = true),
                  ),
                ),
                Expanded(
                  child: RadioListTile<bool>(
                    title: const Text('Custom'),
                    value: false,
                    groupValue: _isEqualSplit,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (_) => setState(() => _isEqualSplit = false),
                  ),
                ),
              ],
            ),

            const Text(
              'Select Payers:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            // Equal split preview
            if (_isEqualSplit && _selectedUsers.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '₱${((double.tryParse(_totalController.text) ?? 0) / (_selectedUsers.length + 1)).toStringAsFixed(2)} each (${_selectedUsers.length + 1} people incl. you)',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
              ),
            ],

            const SizedBox(height: 8),

            // Owner share in custom mode
            if (!_isEqualSplit)
              Padding(
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: 8,
                  top: 4,
                ),
                child: TextField(
                  controller: _ownerCustomAmount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '₱ Your share',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),

            // Payer list
            if (_users.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              )
            else
              ..._users.map((user) {
                final name = '${user['firstname']} ${user['lastname']}';
                final uid = user['id'] as String;
                final isSelected = _selectedUsers.contains(uid);

                return Column(
                  children: [
                    CheckboxListTile(
                      title: Text(name),
                      value: isSelected,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedUsers.add(uid);
                          } else {
                            _selectedUsers.remove(uid);
                            _customAmounts[uid]?.clear();
                          }
                        });
                      },
                    ),
                    if (!_isEqualSplit && isSelected)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 16,
                          right: 16,
                          bottom: 8,
                        ),
                        child: TextField(
                          controller: _customAmounts[uid],
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: '₱ Amount for $name',
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                  ],
                );
              }),

            // Remaining indicator
            if (!_isEqualSplit && _selectedUsers.isNotEmpty) ...[
              Builder(builder: (_) {
                final total = double.tryParse(_totalController.text) ?? 0;
                final remaining = total - _assignedTotal;
                final isOver = remaining < -0.01;
                final isExact = remaining.abs() <= 0.01;
                return Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    isExact
                        ? '✓ Amounts match total'
                        : isOver
                            ? 'Over by ₱${remaining.abs().toStringAsFixed(2)}'
                            : 'Remaining: ₱${remaining.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: isExact
                          ? Colors.green
                          : isOver
                              ? Colors.redAccent
                              : Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                );
              }),
            ],

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create'),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}