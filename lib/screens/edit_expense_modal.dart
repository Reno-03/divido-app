import 'package:divido_app/providers/group_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:divido_app/services/current_user.dart';

class EditExpenseModal extends StatefulWidget {
  final String expenseId;
  final String initialTitle;
  final double initialTotal;
  final List<Map<String, dynamic>> initialBreakdowns;
  final Future<void> Function() onSaved;

  const EditExpenseModal({
    super.key,
    required this.expenseId,
    required this.initialTitle,
    required this.initialTotal,
    required this.initialBreakdowns,
    required this.onSaved,
  });

  @override
  State<EditExpenseModal> createState() => _EditExpenseModalState();
}

class _EditExpenseModalState extends State<EditExpenseModal> {
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
    _titleController.text = widget.initialTitle;
    _totalController.text = widget.initialTotal.toStringAsFixed(2);
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final groupProvider = Provider.of<GroupProvider>(context, listen: false);
    final memberIds = groupProvider.members
        .map((m) => m['id'] as String)
        .toList();

    final response = await _supabase
        .from('profiles')
        .select('id, firstname, lastname, color, avatar_url')
        .inFilter('id', memberIds);

    final users = List<Map<String, dynamic>>.from(
      response,
    ).where((u) => u['id'] != _currentUserId).toList();

    final Set<String> preSelected = {};
    final Map<String, String> preAmounts = {};

    for (final breakdown in widget.initialBreakdowns) {
      final payerId = breakdown['payer_id'] as String;
      final amount = (breakdown['amount'] as num).toDouble();

      if (payerId == _currentUserId) {
        _ownerCustomAmount.text = amount.toStringAsFixed(2);
      } else {
        preSelected.add(payerId);
        preAmounts[payerId] = amount.toStringAsFixed(2);
      }
    }

    final allAmounts = widget.initialBreakdowns
        .map((b) => (b['amount'] as num).toDouble())
        .toList();
    final isEqual =
        allAmounts.isNotEmpty &&
        allAmounts.every((a) => (a - allAmounts.first).abs() < 0.01);

    setState(() {
      _users = users;
      _selectedUsers.addAll(preSelected);
      _isEqualSplit = isEqual;

      for (final user in users) {
        final uid = user['id'] as String;
        _customAmounts[uid] = TextEditingController(
          text: preAmounts[uid] ?? '',
        );
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

    try {
      await _supabase
          .from('expenses')
          .update({'title': title, 'total': total})
          .eq('id', widget.expenseId);

      await _supabase
          .from('expense_breakdowns')
          .delete()
          .eq('expense_id', widget.expenseId);

      final allPayerIds = {..._selectedUsers, _currentUserId!};

      for (final payerId in allPayerIds) {
        final amount = _isEqualSplit
            ? ((total / allPayerIds.length) * 100).round() / 100
            : payerId == _currentUserId
            ? double.tryParse(_ownerCustomAmount.text) ?? 0
            : double.tryParse(_customAmounts[payerId]?.text ?? '') ?? 0;

        await _supabase.from('expense_breakdowns').insert({
          'expense_id': widget.expenseId,
          'payer_id': payerId,
          'amount': amount,
        });
      }

      await widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _avatar(Map<String, dynamic> user) {
    final raw = user['color'] as String? ?? '#6366F1';
    final color = Color(int.parse('FF${raw.replaceAll('#', '')}', radix: 16));
    final firstName = user['firstname'] as String? ?? '';
    final lastName = user['lastname'] as String? ?? '';
    final initials =
        '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'
            .toUpperCase();
    final avatarUrl = user['avatar_url'] as String?;

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
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
  }

  InputDecoration _inputDecoration(String label, {String? prefix}) {
    return InputDecoration(
      labelText: label,
      prefixText: prefix,
      prefixStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.white.withValues(alpha: 0.5),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.blue, width: 1.5),
      ),
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
      isDense: true,
    );
  }

  InputDecoration _inlineAmountDecoration() {
    return InputDecoration(
      prefixText: '₱ ',
      prefixStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
      hintText: '0.00',
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.blue, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = double.tryParse(_totalController.text) ?? 0;
    final perPerson = _selectedUsers.isNotEmpty
        ? total / (_selectedUsers.length + 1)
        : 0.0;

    final remaining = total - _assignedTotal;
    final isOver = remaining < -0.01;
    final isExact = remaining.abs() <= 0.01;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF171A3F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // drag handle
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

            // header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Edit Expense',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

            const SizedBox(height: 20),

            // title
            TextField(
              controller: _titleController,
              decoration: _inputDecoration('Title'),
              style: const TextStyle(fontSize: 16),
            ),

            const SizedBox(height: 14),

            // total
            TextField(
              controller: _totalController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: _inputDecoration('Total Amount', prefix: '₱  '),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 20),

            // split mode label
            const Text(
              'Split Mode',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),

            // split mode segmented button
            SegmentedButton<bool>(
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Equal'),
                  icon: Icon(Icons.balance, size: 16),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Custom'),
                  icon: Icon(Icons.tune, size: 16),
                ),
              ],
              selected: {_isEqualSplit},
              onSelectionChanged: (val) =>
                  setState(() => _isEqualSplit = val.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.standard,
                backgroundColor: WidgetStateProperty.resolveWith<Color>(
                  (states) => states.contains(WidgetState.selected)
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.transparent,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // payers header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Payers',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                if (_isEqualSplit && _selectedUsers.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      '₱${perPerson.toStringAsFixed(2)} each',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade300,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // owner row in custom mode
            if (!_isEqualSplit) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    () {
                      final raw = CurrentUser.instance.color ?? '#6366F1';
                      final color = Color(
                        int.parse('FF${raw.replaceAll('#', '')}', radix: 16),
                      );
                      final initials =
                          '${CurrentUser.instance.firstname?[0].toUpperCase() ?? ''}${CurrentUser.instance.lastname?[0].toUpperCase() ?? ''}';
                      final avatarUrl = CurrentUser.instance.avatarUrl;
                      return Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
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
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${CurrentUser.instance.firstname ?? ''} (you)',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _ownerCustomAmount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.right,
                        decoration: _inlineAmountDecoration(),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // user list
            if (_users.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              ..._users.map((user) {
                final name = '${user['firstname']} ${user['lastname']}';
                final uid = user['id'] as String;
                final isSelected = _selectedUsers.contains(uid);

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedUsers.remove(uid);
                        _customAmounts[uid]?.clear();
                      } else {
                        _selectedUsers.add(uid);
                      }
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.blue.withValues(alpha: 0.1)
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? Colors.blue.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      children: [
                        _avatar(user),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (!_isEqualSplit && isSelected)
                          SizedBox(
                            width: 100,
                            child: TextField(
                              controller: _customAmounts[uid],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              textAlign: TextAlign.right,
                              decoration: _inlineAmountDecoration(),
                              onChanged: (_) => setState(() {}),
                            ),
                          )
                        else
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              isSelected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              key: ValueKey(isSelected),
                              size: 20,
                              color: isSelected
                                  ? Colors.blue.shade300
                                  : Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),

            // remaining indicator
            if (!_isEqualSplit && _selectedUsers.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isExact
                      ? Colors.green.withValues(alpha: 0.1)
                      : isOver
                      ? Colors.red.withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isExact
                        ? Colors.green.withValues(alpha: 0.3)
                        : isOver
                        ? Colors.red.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isExact
                          ? Icons.check_circle_outline
                          : isOver
                          ? Icons.error_outline
                          : Icons.info_outline,
                      size: 16,
                      color: isExact
                          ? Colors.green.shade400
                          : isOver
                          ? Colors.red.shade400
                          : Colors.white54,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isExact
                          ? 'Amounts match total'
                          : isOver
                          ? 'Over by ₱${remaining.abs().toStringAsFixed(2)}'
                          : 'Remaining: ₱${remaining.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: isExact
                            ? Colors.green.shade400
                            : isOver
                            ? Colors.red.shade400
                            : Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // save button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isLoading ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF171A3F),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF171A3F),
                        ),
                      )
                    : const Text(
                        'Save Changes',
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
    );
  }
}
